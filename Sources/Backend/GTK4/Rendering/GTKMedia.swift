import CGTK
import CGTKBridge
import CGStreamer
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@_spi(SwiftOpenUIBackend) import SwiftOpenUI

// MARK: - VideoPlayer

/// Direct GStreamer playbin3 driver. Frames are delivered through appsink and
/// uploaded to a GtkPicture, avoiding GtkVideo's single-stream limitations.
@MainActor
final class GTKVideoDriver: _AVPlayerDriver {
    let widget: UnsafeMutablePointer<GtkWidget>
    private let videoWidget: UnsafeMutablePointer<GtkWidget>
    private weak var player: AVPlayer?
    private var gst: UnsafeMutablePointer<SwiftOpenUIGStreamerPlayer>?
    private var pendingSeek: Double?
    private var startSource: guint = 0
    private var pendingAutoplay = true
    private var pictureInPictureWindow: UnsafeMutablePointer<GtkWidget>?
    private var pictureInPictureActiveHandler: (@MainActor (Bool) -> Void)?
    private var sourceVideoURL: URL?
    private var sourceAudioURL: URL?
    private var localVideoURL: URL?
    private var downloadTask: URLSessionDownloadTask?

    init(player: AVPlayer) {
        self.player = player
        widget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)
        videoWidget = gtk_swift_video_surface_new()!
        g_object_ref_sink(gpointer(videoWidget))
        gtk_box_append(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkBox.self), videoWidget)
        g_object_ref_sink(gpointer(widget))
        gst = swift_openui_gst_player_new()
        let context = Unmanaged.passUnretained(self).toOpaque()
        // GStreamer invokes this as clock-eligible samples arrive. The C shim
        // coalesces delivery onto GTK's main context before calling Swift.
        if let gst { swift_openui_gst_player_set_frame_callback(gst, { data in
            guard let data else { return }
            MainActor.assumeIsolated {
                Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue().presentFrame()
            }
        }, context) }
    }

    deinit {
        downloadTask?.cancel()
        if let localVideoURL { try? FileManager.default.removeItem(at: localVideoURL) }
        if startSource != 0 { g_source_remove(startSource) }
        MainActor.assumeIsolated { stopPictureInPicture() }
        if let gst { swift_openui_gst_player_free(gst) }
        if gtk_widget_get_parent(videoWidget) != nil { gtk_widget_unparent(videoWidget) }
        g_object_unref(gpointer(videoWidget))
        g_object_unref(gpointer(widget))
    }

    func replaceCurrentItem(with item: AVPlayerItem?) {
        guard let item else { stop(); return }
        let videoURL: URL?
        let audioURL: URL?
        if let asset = item.asset as? AVURLAsset {
            videoURL = asset.url
            audioURL = nil
        } else if let asset = item.asset as? AVMutableComposition {
            videoURL = asset._swiftOpenUICompositionTracks
                .first(where: { $0.mediaType == .video })?._swiftOpenUISourceTrack?._swiftOpenUISourceURL
            audioURL = asset._swiftOpenUICompositionTracks
                .first(where: { $0.mediaType == .audio })?._swiftOpenUISourceTrack?._swiftOpenUISourceURL
        } else {
            videoURL = nil
            audioURL = nil
        }
        guard let videoURL else {
            player?._swiftOpenUIOnFailure?("The player item has no video track")
            return
        }
        guard let gst else {
            stop()
            player?._swiftOpenUIOnFailure?("GStreamer playbin3 is unavailable")
            return
        }
        downloadTask?.cancel()
        downloadTask = nil
        if let localVideoURL { try? FileManager.default.removeItem(at: localVideoURL) }
        localVideoURL = nil
        sourceVideoURL = videoURL
        sourceAudioURL = audioURL
        pendingSeek = nil
        swift_openui_gst_player_stop(gst)
        swift_openui_gst_player_set_uris(gst, videoURL.absoluteString, audioURL?.absoluteString)
        pendingAutoplay = false
        if startSource != 0 { g_source_remove(startSource) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        startSource = g_idle_add({ data in
            guard let data else { return 0 }
            let driver = Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue()
            driver.startSource = 0
            guard let gst = driver.gst else { return 0 }
            if driver.pendingAutoplay { swift_openui_gst_player_play(gst) } else { swift_openui_gst_player_pause(gst) }
            return 0
        }, context)
    }

    func play() {
        pendingAutoplay = true
        if startSource == 0, let gst { swift_openui_gst_player_play(gst) }
    }
    func pause() {
        pendingAutoplay = false
        if startSource == 0, let gst { swift_openui_gst_player_pause(gst) }
    }

    func seek(to time: CMTime) {
        let seconds = time.seconds
        guard let gst else { pendingSeek = seconds; return }
        guard durationSeconds > 0 else { pendingSeek = seconds; return }
        if swift_openui_gst_player_is_seekable(gst) != 0 {
            _ = swift_openui_gst_player_seek(gst, gint64(max(0, seconds) * 1_000_000_000))
        } else {
            pendingSeek = seconds
            downloadForSeekingIfNeeded()
        }
    }

    func stop() {
        if let gst { swift_openui_gst_player_stop(gst) }
        pendingSeek = nil
    }

    private func downloadForSeekingIfNeeded() {
        guard downloadTask == nil, localVideoURL == nil, let sourceVideoURL,
              sourceVideoURL.scheme == "http" || sourceVideoURL.scheme == "https" else { return }
        downloadTask = URLSession.shared.downloadTask(with: sourceVideoURL) { [weak self] temporaryURL, _, error in
            guard let self else { return }
            var result: Result<URL, Error>
            do {
                if let error { throw error }
                guard let temporaryURL else { throw URLError(.cannotCreateFile) }
                let extensionName = sourceVideoURL.pathExtension
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("swift-openui-\(UUID().uuidString)")
                    .appendingPathExtension(extensionName)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                result = .success(destination)
            } catch { result = .failure(error) }
            Task { @MainActor [weak self] in self?.finishSeekDownload(result, sourceURL: sourceVideoURL) }
        }
        downloadTask?.resume()
    }

    private func finishSeekDownload(_ result: Result<URL, Error>, sourceURL: URL) {
        downloadTask = nil
        guard sourceVideoURL == sourceURL else {
            if case .success(let url) = result { try? FileManager.default.removeItem(at: url) }
            return
        }
        switch result {
        case .failure(let error):
            pendingSeek = nil
            player?._swiftOpenUIOnFailure?("Could not buffer this video for seeking: \(error.localizedDescription)")
        case .success(let localURL):
            guard let gst else { try? FileManager.default.removeItem(at: localURL); return }
            localVideoURL = localURL
            swift_openui_gst_player_stop(gst)
            swift_openui_gst_player_set_uris(gst, localURL.absoluteString, sourceAudioURL?.absoluteString)
            if pendingAutoplay { swift_openui_gst_player_play(gst) } else { swift_openui_gst_player_pause(gst) }
        }
    }

    var currentTime: CMTime {
        CMTime(seconds: gst.map { Double(swift_openui_gst_player_position($0)) / 1_000_000_000 } ?? 0,
               preferredTimescale: 600)
    }
    var duration: CMTime { CMTime(seconds: durationSeconds, preferredTimescale: 600) }
    private var durationSeconds: Double {
        gst.map { Double(swift_openui_gst_player_duration($0)) / 1_000_000_000 } ?? 0
    }
    var rate: Float { gst.map { swift_openui_gst_player_is_playing($0) != 0 ? 1 : 0 } ?? 0 }
    var isPictureInPicturePossible: Bool { player?.currentItem != nil }
    func setPictureInPictureActiveHandler(_ handler: (@MainActor (Bool) -> Void)?) {
        pictureInPictureActiveHandler = handler
    }

    func startPictureInPicture() {
        guard pictureInPictureWindow == nil else { return }
        if gtk_widget_get_parent(videoWidget) != nil { gtk_widget_unparent(videoWidget) }
        let window = gtk_window_new()!
        pictureInPictureWindow = window
        gtk_window_set_title(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), "Picture in Picture")
        gtk_window_set_default_size(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), 480, 270)
        gtk_window_set_resizable(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), 1)
        gtk_window_set_child(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), videoWidget)
        let context = Unmanaged.passUnretained(self).toOpaque()
        g_signal_connect_data(gpointer(window), "close-request", unsafeBitCast({ (_: gpointer?, data: gpointer?) -> gboolean in
            guard let data else { return 0 }
            MainActor.assumeIsolated {
                Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue().stopPictureInPicture()
            }
            return 1
        } as @convention(c) (gpointer?, gpointer?) -> gboolean, to: GCallback.self), context, nil,
        GConnectFlags(rawValue: 0))
        gtk_window_present(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self))
    }

    func stopPictureInPicture() {
        guard let window = pictureInPictureWindow else { return }
        pictureInPictureWindow = nil
        let gtkWindow = UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self)
        gtk_window_set_child(gtkWindow, nil)
        if gtk_widget_get_parent(videoWidget) != nil { gtk_widget_unparent(videoWidget) }
        gtk_box_append(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkBox.self), videoWidget)
        gtk_window_destroy(gtkWindow)
        pictureInPictureActiveHandler?(false)
    }

    private func presentFrame() {
        if let target = pendingSeek, durationSeconds > 0 {
            pendingSeek = nil
            seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }
        guard let gst else { return }
        var data: UnsafeMutablePointer<UInt8>?
        var length: gsize = 0
        var width: gint = 0
        var height: gint = 0
        var stride: gint = 0
        if swift_openui_gst_player_pull_frame(gst, &data, &length, &width, &height, &stride) != 0, let data {
            gtk_swift_video_surface_set_pixels(videoWidget, data, length, width, height, stride)
            swift_openui_gst_player_free_frame(data)
        }
        if durationSeconds > 0, currentTime.seconds >= durationSeconds - 0.1, rate == 0 { player?._swiftOpenUIOnEnded?() }
    }
}

extension VideoPlayer: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        MainActor.assumeIsolated { gtkCreateWidgetOnMainActor() }
    }

    @MainActor
    private func gtkCreateWidgetOnMainActor() -> OpaquePointer {
        AVPictureInPictureController._swiftOpenUISetPictureInPictureSupported(true)
        guard let player else { return opaqueFromWidget(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)) }
        let driver: GTKVideoDriver
        if let existing = player._swiftOpenUIDriver as? GTKVideoDriver {
            driver = existing
        } else {
            driver = GTKVideoDriver(player: player)
            player._swiftOpenUIAttachDriver(driver)
        }
        // Keep one GtkPicture alive so playback is not interrupted by view updates.
        if gtk_widget_get_parent(driver.widget) != nil { gtk_widget_unparent(driver.widget) }
        if VideoOverlay.self == EmptyView.self { return opaqueFromWidget(driver.widget) }
        let overlay = gtk_overlay_new()!
        gtk_overlay_set_child(OpaquePointer(overlay), driver.widget)
        let overlayView = widgetFromOpaque(gtkRenderView(videoOverlay))
        gtk_overlay_add_overlay(OpaquePointer(overlay), overlayView)
        return opaqueFromWidget(overlay)
    }
}

// MARK: - fileImporter

private final class FileDialogRequest {
    let allowsMultiple: Bool
    let finish: (Result<[URL], Error>) -> Void
    init(allowsMultiple: Bool, finish: @escaping (Result<[URL], Error>) -> Void) {
        self.allowsMultiple = allowsMultiple
        self.finish = finish
    }
}

extension FileImporterView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))

        let anchor: UnsafeMutablePointer<GtkWidget>
        if let host = GTKViewHost.getCurrentRebuilding() { anchor = host.container } else { anchor = widget }
        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)

        guard isPresented.wrappedValue else { return opaqueFromWidget(widget) }
        guard g_object_get_data(gobject, "swift-file-active") == nil else { return opaqueFromWidget(widget) }
        g_object_set_data(gobject, "swift-file-active", gpointer(bitPattern: 1))
        g_object_ref(gpointer(anchor))

        let binding = isPresented
        let completion = self.completion
        let multiple = allowsMultipleSelection
        let extensions = allowedExtensions

        let finish: (Result<[URL], Error>) -> Void = { result in
            let obj = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
            g_object_set_data(obj, "swift-file-active", nil)
            binding.wrappedValue = false
            completion(result)
        }

        g_idle_add({ userData -> gboolean in
            Unmanaged<ClosureBox>.fromOpaque(userData!).takeRetainedValue().closure()
            return 0
        }, Unmanaged.passRetained(ClosureBox { [anchor] in
            defer { g_object_unref(gpointer(anchor)) }
            guard let root = gtk_widget_get_root(anchor) else { finish(.failure(CocoaError(.userCancelled))); return }
            let parent = UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)

            let dialog = gtk_file_dialog_new()!
            gtk_file_dialog_set_title(dialog, "Open")
            if let extensions {
                let filter = gtk_file_filter_new()!
                gtk_file_filter_set_name(filter, "Supported files")
                for ext in extensions { gtk_file_filter_add_suffix(filter, ext) }
                let store = g_list_store_new(gtk_file_filter_get_type())!
                g_list_store_append(store, UnsafeMutableRawPointer(filter))
                gtk_file_dialog_set_filters(dialog, store)
                g_object_unref(UnsafeMutableRawPointer(filter))
                g_object_unref(UnsafeMutableRawPointer(store))
            }

            let request = Unmanaged.passRetained(FileDialogRequest(allowsMultiple: multiple, finish: finish)).toOpaque()
            let callback: GAsyncReadyCallback = { source, result, userData in
                let request = Unmanaged<FileDialogRequest>.fromOpaque(userData!).takeRetainedValue()
                let dialog = OpaquePointer(source!)
                var error: UnsafeMutablePointer<GError>?
                var urls: [URL] = []
                if request.allowsMultiple {
                    if let list = gtk_file_dialog_open_multiple_finish(dialog, result, &error) {
                        for i in 0..<g_list_model_get_n_items(list) {
                            if let item = g_list_model_get_item(list, i) {
                                if let path = g_file_get_path(OpaquePointer(item)) {
                                    urls.append(URL(fileURLWithPath: String(cString: path)))
                                    g_free(path)
                                }
                                g_object_unref(item)
                            }
                        }
                        g_object_unref(UnsafeMutableRawPointer(list))
                    }
                } else if let file = gtk_file_dialog_open_finish(dialog, result, &error) {
                    if let path = g_file_get_path(file) {
                        urls.append(URL(fileURLWithPath: String(cString: path)))
                        g_free(path)
                    }
                    g_object_unref(UnsafeMutableRawPointer(file))
                }
                if let error {
                    let message = String(cString: error.pointee.message)
                    g_error_free(error)
                    // Dismissing the dialog is a cancellation, not a failure.
                    request.finish(.failure(urls.isEmpty ? CocoaError(.userCancelled) : NSError(domain: "GTK", code: 1, userInfo: [NSLocalizedDescriptionKey: message])))
                } else {
                    request.finish(urls.isEmpty ? .failure(CocoaError(.userCancelled)) : .success(urls))
                }
            }
            if multiple { gtk_file_dialog_open_multiple(dialog, parent, nil, callback, request) }
            else { gtk_file_dialog_open(dialog, parent, nil, callback, request) }
            g_object_unref(UnsafeMutableRawPointer(dialog))
        }).toOpaque())

        return opaqueFromWidget(widget)
    }
}
