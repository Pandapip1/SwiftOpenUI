import CGTK
import CGTKBridge
import Foundation
import SwiftOpenUI

// MARK: - VideoPlayer

/// Plays through GTK's media stack (GtkVideo, backed by GStreamer when its plugins are installed).
/// GtkMediaFile has no way to set HTTP request headers, and plays one muxed stream; callers that need
/// either should pick sources accordingly or hand playback to an external player.
final class GTKVideoDriver: MediaPlayerDriver {
    let widget: UnsafeMutablePointer<GtkWidget>
    private weak var player: MediaPlayer?
    private var observedStream: UnsafeMutablePointer<GtkMediaStream>?
    private var pendingSeek: Double?

    init(player: MediaPlayer) {
        self.player = player
        widget = gtk_swift_video_new()
        g_object_ref_sink(gpointer(widget))
    }

    deinit {
        gtk_swift_video_clear(widget)
        g_object_unref(gpointer(widget))
    }

    private var stream: UnsafeMutablePointer<GtkMediaStream>? { gtk_swift_video_stream(widget) }

    func open(url: URL, autoplay: Bool, startAt: Double) {
        pendingSeek = startAt > 0 ? startAt : nil
        gtk_swift_video_open_uri(widget, url.absoluteString, autoplay ? 1 : 0)
        observeCurrentStream()
    }

    func play() { stream.map { gtk_media_stream_play($0) } }
    func pause() { stream.map { gtk_media_stream_pause($0) } }

    func seek(to seconds: Double) {
        guard let s = stream else { pendingSeek = seconds; return }
        gtk_media_stream_seek(s, gint64(max(0, seconds) * 1_000_000))
    }

    func stop() {
        gtk_swift_video_clear(widget)
        observedStream = nil
        pendingSeek = nil
    }

    var currentTime: Double { stream.map { Double(gtk_media_stream_get_timestamp($0)) / 1_000_000 } ?? 0 }
    var duration: Double { stream.map { Double(gtk_media_stream_get_duration($0)) / 1_000_000 } ?? 0 }
    var isPlaying: Bool { stream.map { gtk_media_stream_get_playing($0) != 0 } ?? false }

    // MARK: signals

    private func observeCurrentStream() {
        guard let s = stream, s != observedStream else { return }
        observedStream = s
        let unmanaged = Unmanaged.passUnretained(self).toOpaque()
        func connect(_ signal: String, _ handler: @escaping @convention(c) (gpointer?, gpointer?, gpointer?) -> Void) {
            g_signal_connect_data(gpointer(s), signal, unsafeBitCast(handler, to: GCallback.self), unmanaged, nil, GConnectFlags(rawValue: 0))
        }
        connect("notify::prepared") { _, _, data in
            let driver = Unmanaged<GTKVideoDriver>.fromOpaque(data!).takeUnretainedValue()
            if let target = driver.pendingSeek { driver.pendingSeek = nil; driver.seek(to: target) }
        }
        connect("notify::ended") { _, _, data in
            let driver = Unmanaged<GTKVideoDriver>.fromOpaque(data!).takeUnretainedValue()
            if let s = driver.stream, gtk_media_stream_get_ended(s) != 0 { driver.player?.onEnded?() }
        }
        connect("notify::error") { _, _, data in
            let driver = Unmanaged<GTKVideoDriver>.fromOpaque(data!).takeUnretainedValue()
            guard let s = driver.stream, let err = gtk_media_stream_get_error(s) else { return }
            driver.player?.onFailure?(String(cString: err.pointee.message))
        }
    }
}

extension VideoPlayer: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let driver: GTKVideoDriver
        if let existing = player.driver as? GTKVideoDriver {
            driver = existing
        } else {
            driver = GTKVideoDriver(player: player)
            player.driver = driver   // flushes any `open` queued before the view existed
        }
        // The surface is re-created on every render; keep one GtkVideo alive so playback is not interrupted.
        if gtk_widget_get_parent(driver.widget) != nil { gtk_widget_unparent(driver.widget) }
        return opaqueFromWidget(driver.widget)
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
