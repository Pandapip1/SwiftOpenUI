import CGTK
import CGTKBridge
import CGStreamer
import Foundation
import SwiftOpenUI

// MARK: - VideoPlayer

/// Direct GStreamer playbin3 driver. Frames are delivered through appsink and
/// uploaded to a GtkPicture, avoiding GtkVideo's single-stream limitations.
final class GTKVideoDriver: MediaPlayerDriver {
    let widget: UnsafeMutablePointer<GtkWidget>
    private weak var player: MediaPlayer?
    private var gst: UnsafeMutablePointer<SwiftOpenUIGStreamerPlayer>?
    private var pendingSeek: Double?
    private var timer: guint = 0

    init(player: MediaPlayer) {
        self.player = player
        widget = gtk_swift_video_surface_new()!
        g_object_ref_sink(gpointer(widget))
        gst = swift_openui_gst_player_new()
        let context = Unmanaged.passUnretained(self).toOpaque()
        timer = g_timeout_add(33, { data in
            guard let data else { return 0 }
            return Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue().tick()
        }, context)
    }

    deinit {
        if timer != 0 { g_source_remove(timer) }
        if let gst { swift_openui_gst_player_free(gst) }
        g_object_unref(gpointer(widget))
    }

    func open(url: URL, autoplay: Bool, startAt: Double) {
        guard let gst else {
            stop()
            player?.onFailure?("GStreamer playbin3 is unavailable")
            return
        }
        pendingSeek = startAt > 0 ? startAt : nil
        swift_openui_gst_player_stop(gst)
        swift_openui_gst_player_set_uri(gst, url.absoluteString)
        if autoplay { swift_openui_gst_player_play(gst) } else { swift_openui_gst_player_pause(gst) }
    }

    func play() { if let gst { swift_openui_gst_player_play(gst) } }
    func pause() { if let gst { swift_openui_gst_player_pause(gst) } }

    func seek(to seconds: Double) {
        guard let gst else { pendingSeek = seconds; return }
        _ = swift_openui_gst_player_seek(gst, gint64(max(0, seconds) * 1_000_000_000))
    }

    func stop() {
        if let gst { swift_openui_gst_player_stop(gst) }
        pendingSeek = nil
    }

    func setExternalSubtitle(_ url: URL?) {
        guard let gst else { return }
        swift_openui_gst_player_set_subtitle_uri(gst, url?.absoluteString)
    }

    var currentTime: Double { gst.map { Double(swift_openui_gst_player_position($0)) / 1_000_000_000 } ?? 0 }
    var duration: Double { gst.map { Double(swift_openui_gst_player_duration($0)) / 1_000_000_000 } ?? 0 }
    var isPlaying: Bool { gst.map { swift_openui_gst_player_is_playing($0) != 0 } ?? false }

    private func tick() -> gboolean {
        if let target = pendingSeek, duration > 0 { pendingSeek = nil; seek(to: target) }
        guard let gst else { return 1 }
        var data: UnsafeMutablePointer<UInt8>?
        var length: gsize = 0
        var width: gint = 0
        var height: gint = 0
        var stride: gint = 0
        if swift_openui_gst_player_pull_frame(gst, &data, &length, &width, &height, &stride) != 0, let data {
            gtk_swift_video_surface_set_pixels(widget, data, length, width, height, stride)
            swift_openui_gst_player_free_frame(data)
        }
        if duration > 0, currentTime >= duration - 0.1, !isPlaying { player?.onEnded?() }
        return 1
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
        // The surface is re-created on every render; keep one GtkPicture alive so playback is not interrupted.
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
