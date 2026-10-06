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
    private var acceptedSeek: Double?
    private var startSource: guint = 0
    private var pendingAutoplay = true
    private var playbackRate: Float = 1
    private var rateNeedsApplication = false
    private var pendingRatePosition: Double?
    private var pictureInPictureWindow: UnsafeMutablePointer<GtkWidget>?
    private var pictureInPicturePlayButton: UnsafeMutablePointer<GtkWidget>?
    private var pictureInPictureTimeLabel: UnsafeMutablePointer<GtkWidget>?
    private var pictureInPictureUpdateSource: guint = 0
    private var pictureInPictureActiveHandler: (@MainActor (Bool) -> Void)?
    private var sourceVideoURL: URL?
    private var sourceAudioURL: URL?
    private var sourceVideoHeaders: [String: String] = [:]
    private var sourceAudioHeaders: [String: String] = [:]
    private var localVideoURL: URL?
    private var localAudioURL: URL?
    private var downloadTask: URLSessionDownloadTask?
    private var sourceGeneration: UInt = 0
    private weak var mediaSelectionAsset: AVAsset?
    private var mediaSelectionGeneration: UInt = 0

    init(player: AVPlayer) {
        self.player = player
        widget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)
        videoWidget = gtk_swift_video_surface_new()!
        g_object_ref_sink(gpointer(videoWidget))
        gtk_box_append(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkBox.self), videoWidget)
        g_object_ref_sink(gpointer(widget))
        gst = swift_openui_gst_player_new_with_paintable(1)
        let context = Unmanaged.passUnretained(self).toOpaque()
        // GStreamer invokes this as clock-eligible samples arrive. The C shim
        // coalesces delivery onto GTK's main context before calling Swift.
        if let gst { swift_openui_gst_player_set_frame_callback(gst, { data in
            guard let data else { return }
            MainActor.assumeIsolated {
                Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue().presentFrame()
            }
        }, context) }
        if let gst { swift_openui_gst_player_set_event_callback(gst, { data in
            guard let data else { return }
            MainActor.assumeIsolated {
                Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue().handlePlaybackEvent()
            }
        }, context) }
    }

    deinit {
        downloadTask?.cancel()
        if let localVideoURL { try? FileManager.default.removeItem(at: localVideoURL) }
        if let localAudioURL { try? FileManager.default.removeItem(at: localAudioURL) }
        if startSource != 0 { g_source_remove(startSource) }
        MainActor.assumeIsolated { stopPictureInPicture() }
        if pictureInPictureUpdateSource != 0 { g_source_remove(pictureInPictureUpdateSource) }
        if let gst { swift_openui_gst_player_free(gst) }
        if gtk_widget_get_parent(videoWidget) != nil { gtk_widget_unparent(videoWidget) }
        g_object_unref(gpointer(videoWidget))
        g_object_unref(gpointer(widget))
    }

    func replaceCurrentItem(with item: AVPlayerItem?) {
        guard let item else { stop(); return }
        cancelSeekFallback()
        let videoURL: URL?
        let audioURL: URL?
        let videoOptions: [String: Any]?
        let audioOptions: [String: Any]?
        if let asset = item.asset as? AVURLAsset {
            videoURL = asset.url
            audioURL = nil
            videoOptions = asset._swiftOpenUIOptions
            audioOptions = nil
        } else if let asset = item.asset as? AVMutableComposition {
            let videoTrack = asset._swiftOpenUICompositionTracks
                .first(where: { $0.mediaType == .video })?._swiftOpenUISourceTrack
            let audioTrack = asset._swiftOpenUICompositionTracks
                .first(where: { $0.mediaType == .audio })?._swiftOpenUISourceTrack
            videoURL = videoTrack?._swiftOpenUISourceURL
            audioURL = audioTrack?._swiftOpenUISourceURL
            videoOptions = videoTrack?._swiftOpenUISourceOptions
            audioOptions = audioTrack?._swiftOpenUISourceOptions
        } else {
            videoURL = nil
            audioURL = nil
            videoOptions = nil
            audioOptions = nil
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
        sourceVideoURL = videoURL
        sourceAudioURL = audioURL
        sourceVideoHeaders = Self.headers(from: videoOptions)
        sourceAudioHeaders = Self.headers(from: audioOptions)
        mediaSelectionAsset = item.asset
        mediaSelectionGeneration = 0
        item.asset._swiftOpenUIRefreshMediaSelectionGroups = { [weak self, weak asset = item.asset] in
            guard let self, let asset else { return }
            self.refreshMediaSelectionGroups(on: asset)
        }
        item._swiftOpenUISelectMediaOption = { [weak self] option, group in
            Task { @MainActor [weak self] in self?.selectMediaOption(option, in: group) }
        }
        pendingSeek = nil
        acceptedSeek = nil
        pendingRatePosition = nil
        rateNeedsApplication = true
        swift_openui_gst_player_stop(gst)
        swift_openui_gst_player_clear_headers(gst)
        for (name, value) in sourceVideoHeaders {
            swift_openui_gst_player_set_header(gst, 0, name, value)
        }
        for (name, value) in sourceAudioHeaders {
            swift_openui_gst_player_set_header(gst, 1, name, value)
        }
        swift_openui_gst_player_set_uris(gst, videoURL.absoluteString, audioURL?.absoluteString)
        bindVideoPaintable()
        pendingAutoplay = false
        if startSource != 0 { g_source_remove(startSource) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        startSource = g_idle_add({ data in
            guard let data else { return 0 }
            let driver = Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue()
            driver.startSource = 0
            guard let gst = driver.gst else { return 0 }
            if driver.pendingAutoplay {
                swift_openui_gst_player_play(gst)
                driver.applyPlaybackRateIfReady()
            } else {
                swift_openui_gst_player_pause(gst)
            }
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
    func setRate(_ rate: Float) {
        guard rate > 0 else { pause(); return }
        let position = currentTime.seconds
        if position.isFinite, position > 0 { pendingRatePosition = position }
        playbackRate = rate
        rateNeedsApplication = true
        pendingAutoplay = true
        if startSource == 0, let gst {
            swift_openui_gst_player_play(gst)
            applyPlaybackRateIfReady()
        }
    }

    func seek(to time: CMTime) {
        let seconds = time.seconds
        acceptedSeek = nil
        guard let gst else { pendingSeek = seconds; return }
        guard durationSeconds > 0 else { pendingSeek = seconds; return }
        if swift_openui_gst_player_is_seekable(gst) != 0 {
            let target = max(0, seconds)
            if swift_openui_gst_player_seek(
                gst, gint64(max(0, seconds) * 1_000_000_000), Double(playbackRate)
            ) != 0 {
                // A flushing seek temporarily makes position queries return the
                // old clock or zero. Keep AVPlayer's clock at the requested
                // position until the pipeline produces a post-seek frame.
                acceptedSeek = target
                pendingSeek = nil
                return
            }
        }
        pendingSeek = seconds
        downloadForSeekingIfNeeded()
    }

    func stop() {
        cancelSeekFallback()
        if let gst { swift_openui_gst_player_stop(gst) }
        pendingSeek = nil
        acceptedSeek = nil
        pendingRatePosition = nil
    }

    private func cancelSeekFallback() {
        sourceGeneration &+= 1
        downloadTask?.cancel()
        downloadTask = nil
        if let localVideoURL { try? FileManager.default.removeItem(at: localVideoURL) }
        if let localAudioURL { try? FileManager.default.removeItem(at: localAudioURL) }
        localVideoURL = nil
        localAudioURL = nil
    }

    private func downloadForSeekingIfNeeded() {
        guard downloadTask == nil, localVideoURL == nil, let sourceVideoURL,
              sourceVideoURL.scheme == "http" || sourceVideoURL.scheme == "https" else { return }
        downloadSeekSource(sourceVideoURL, headers: sourceVideoHeaders, isAudio: false,
                           generation: sourceGeneration)
    }

    private func downloadSeekSource(_ sourceURL: URL, headers: [String: String], isAudio: Bool,
                                    generation: UInt) {
        var request = URLRequest(url: sourceURL)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        downloadTask = URLSession.shared.downloadTask(with: request) { [weak self] temporaryURL, _, error in
            guard let self else { return }
            var result: Result<URL, Error>
            do {
                if let error { throw error }
                guard let temporaryURL else { throw URLError(.cannotCreateFile) }
                let extensionName = sourceURL.pathExtension
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("swift-openui-\(UUID().uuidString)")
                    .appendingPathExtension(extensionName)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                result = .success(destination)
            } catch { result = .failure(error) }
            Task { @MainActor [weak self] in
                self?.finishSeekDownload(result, sourceURL: sourceURL, isAudio: isAudio,
                                         generation: generation)
            }
        }
        downloadTask?.resume()
    }

    private static func headers(from options: [String: Any]?) -> [String: String] {
        options?["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String] ?? [:]
    }

    private func mediaSelectionGroups() -> [AVMediaCharacteristic: AVMediaSelectionGroup] {
        guard let gst else { return [:] }
        var groups: [AVMediaCharacteristic: AVMediaSelectionGroup] = [:]
        for (characteristic, kind, mediaType, baseName): (AVMediaCharacteristic, Int32, AVMediaType, String) in [
            (.visual, 0, .video, "Video"), (.audible, 1, .audio, "Audio"),
            (.legible, 2, .subtitle, "Subtitles")
        ] {
            let count = Int(swift_openui_gst_player_track_count(gst, kind))
            guard count > 0 else { continue }
            let options = (0..<count).map { index in
                let rawLabel = swift_openui_gst_player_track_label(gst, kind, Int32(index))
                let label = rawLabel.map { String(cString: $0) } ?? "\(baseName) \(index + 1)"
                if let rawLabel { g_free(rawLabel) }
                return AVMediaSelectionOption(mediaType: mediaType, displayName: label, locale: nil,
                                              index: index, characteristic: characteristic)
            }
            groups[characteristic] = AVMediaSelectionGroup(
                options: options, allowsEmptySelection: characteristic == .legible,
                characteristic: characteristic
            )
        }
        return groups
    }

    private func refreshMediaSelectionGroups(on asset: AVAsset) {
        let groups = mediaSelectionGroups()
        guard !groups.isEmpty else { return }
        asset._swiftOpenUISetMediaSelectionGroups(groups)
        if let gst {
            mediaSelectionGeneration = swift_openui_gst_player_stream_collection_generation(gst)
        }
    }

    private func selectMediaOption(_ option: AVMediaSelectionOption?, in group: AVMediaSelectionGroup) {
        guard let gst else { return }
        let kind: Int32
        switch group._swiftOpenUICharacteristic {
        case .visual: kind = 0
        case .audible: kind = 1
        case .legible: kind = 2
        default: return
        }
        swift_openui_gst_player_select_track(gst, kind, Int32(option?._swiftOpenUIIndex ?? -1))
    }

    private func finishSeekDownload(_ result: Result<URL, Error>, sourceURL: URL, isAudio: Bool,
                                    generation: UInt) {
        guard generation == sourceGeneration else {
            if case .success(let url) = result { try? FileManager.default.removeItem(at: url) }
            return
        }
        downloadTask = nil
        let expectedURL = isAudio ? sourceAudioURL : sourceVideoURL
        guard expectedURL == sourceURL else {
            if case .success(let url) = result { try? FileManager.default.removeItem(at: url) }
            return
        }
        switch result {
        case .failure(let error):
            pendingSeek = nil
            if let localVideoURL { try? FileManager.default.removeItem(at: localVideoURL); self.localVideoURL = nil }
            if let localAudioURL { try? FileManager.default.removeItem(at: localAudioURL); self.localAudioURL = nil }
            player?._swiftOpenUIOnFailure?("Could not buffer this video for seeking: \(error.localizedDescription)")
        case .success(let localURL):
            guard let gst else { try? FileManager.default.removeItem(at: localURL); return }
            if isAudio { localAudioURL = localURL } else { localVideoURL = localURL }
            if !isAudio, let sourceAudioURL,
               sourceAudioURL.scheme == "http" || sourceAudioURL.scheme == "https" {
                downloadSeekSource(sourceAudioURL, headers: sourceAudioHeaders, isAudio: true,
                                   generation: generation)
                return
            }
            guard let localVideoURL else { return }
            swift_openui_gst_player_stop(gst)
            swift_openui_gst_player_set_uris(
                gst, localVideoURL.absoluteString, (localAudioURL ?? sourceAudioURL)?.absoluteString
            )
            bindVideoPaintable()
            if pendingAutoplay {
                swift_openui_gst_player_play(gst)
                rateNeedsApplication = true
                applyPlaybackRateIfReady()
            } else {
                swift_openui_gst_player_pause(gst)
            }
        }
    }

    var currentTime: CMTime {
        acknowledgeNativeSeekIfReady()
        let observed = gst.map { Double(swift_openui_gst_player_position($0)) / 1_000_000_000 } ?? 0
        if let target = pendingSeek {
            return CMTime(seconds: max(0, target), preferredTimescale: 600)
        }
        if let target = acceptedSeek {
            return CMTime(seconds: target, preferredTimescale: 600)
        }
        return CMTime(seconds: observed, preferredTimescale: 600)
    }
    var duration: CMTime { CMTime(seconds: durationSeconds, preferredTimescale: 600) }
    private var durationSeconds: Double {
        gst.map { Double(swift_openui_gst_player_duration($0)) / 1_000_000_000 } ?? 0
    }
    var rate: Float { gst.map { swift_openui_gst_player_is_playing($0) != 0 ? playbackRate : 0 } ?? 0 }
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
        gtk_window_set_decorated(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), 0)
        let content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(videoWidget, 1)
        gtk_widget_set_vexpand(videoWidget, 1)
        gtk_box_append(UnsafeMutableRawPointer(content).assumingMemoryBound(to: GtkBox.self), videoWidget)
        let controls = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
        gtk_widget_set_halign(controls, GTK_ALIGN_CENTER)
        gtk_widget_set_margin_top(controls, 6)
        gtk_widget_set_margin_bottom(controls, 6)
        let backward = gtk_button_new_with_label("−10")!
        let playPause = gtk_button_new_with_label(pendingAutoplay ? "Pause" : "Play")!
        let forward = gtk_button_new_with_label("+10")!
        let time = gtk_label_new(nil)!
        let close = gtk_button_new_with_label("×")!
        pictureInPicturePlayButton = playPause
        pictureInPictureTimeLabel = time
        for child in [backward, playPause, forward, time, close] {
            gtk_box_append(UnsafeMutableRawPointer(controls).assumingMemoryBound(to: GtkBox.self), child)
        }
        gtk_box_append(UnsafeMutableRawPointer(content).assumingMemoryBound(to: GtkBox.self), controls)
        let windowHandle = gtk_window_handle_new()!
        gtk_window_handle_set_child(
            OpaquePointer(windowHandle),
            content
        )
        gtk_window_set_child(
            UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self),
            windowHandle
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        g_signal_connect_data(gpointer(backward), "clicked", unsafeBitCast({ (_: gpointer?, data: gpointer?) in
            guard let data else { return }
            MainActor.assumeIsolated {
                let driver = Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue()
                driver.seek(to: CMTime(seconds: max(0, driver.currentTime.seconds - 10), preferredTimescale: 600))
            }
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self), context, nil,
        GConnectFlags(rawValue: 0))
        g_signal_connect_data(gpointer(playPause), "clicked", unsafeBitCast({ (_: gpointer?, data: gpointer?) in
            guard let data else { return }
            MainActor.assumeIsolated {
                let driver = Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue()
                if driver.pendingAutoplay { driver.pause() } else { driver.setRate(driver.playbackRate) }
                driver.updatePictureInPictureControls()
            }
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self), context, nil,
        GConnectFlags(rawValue: 0))
        g_signal_connect_data(gpointer(forward), "clicked", unsafeBitCast({ (_: gpointer?, data: gpointer?) in
            guard let data else { return }
            MainActor.assumeIsolated {
                let driver = Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue()
                driver.seek(to: CMTime(seconds: driver.currentTime.seconds + 10, preferredTimescale: 600))
            }
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self), context, nil,
        GConnectFlags(rawValue: 0))
        g_signal_connect_data(gpointer(close), "clicked", unsafeBitCast({ (_: gpointer?, data: gpointer?) in
            guard let data else { return }
            MainActor.assumeIsolated {
                Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue().stopPictureInPicture()
            }
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self), context, nil,
        GConnectFlags(rawValue: 0))
        g_signal_connect_data(gpointer(window), "close-request", unsafeBitCast({ (_: gpointer?, data: gpointer?) -> gboolean in
            guard let data else { return 0 }
            MainActor.assumeIsolated {
                Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue().stopPictureInPicture()
            }
            return 1
        } as @convention(c) (gpointer?, gpointer?) -> gboolean, to: GCallback.self), context, nil,
        GConnectFlags(rawValue: 0))
        updatePictureInPictureControls()
        pictureInPictureUpdateSource = g_timeout_add(250, { data -> gboolean in
            guard let data else { return 0 }
            return MainActor.assumeIsolated {
                let driver = Unmanaged<GTKVideoDriver>.fromOpaque(data).takeUnretainedValue()
                guard driver.pictureInPictureWindow != nil else { return 0 }
                driver.updatePictureInPictureControls()
                return 1
            }
        }, context)
        gtk_window_present(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self))
    }

    func stopPictureInPicture() {
        guard let window = pictureInPictureWindow else { return }
        pictureInPictureWindow = nil
        if pictureInPictureUpdateSource != 0 {
            g_source_remove(pictureInPictureUpdateSource)
            pictureInPictureUpdateSource = 0
        }
        pictureInPicturePlayButton = nil
        pictureInPictureTimeLabel = nil
        let gtkWindow = UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self)
        if gtk_widget_get_parent(videoWidget) != nil { gtk_widget_unparent(videoWidget) }
        gtk_window_set_child(gtkWindow, nil)
        gtk_box_append(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkBox.self), videoWidget)
        gtk_window_destroy(gtkWindow)
        pictureInPictureActiveHandler?(false)
    }

    private func updatePictureInPictureControls() {
        if let button = pictureInPicturePlayButton {
            gtk_button_set_label(UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self),
                                 pendingAutoplay ? "Pause" : "Play")
        }
        if let label = pictureInPictureTimeLabel {
            let current = max(0, Int(currentTime.seconds))
            let total = max(0, Int(durationSeconds))
            gtk_swift_label_set_text(label, String(format: "%d:%02d / %d:%02d",
                                                   current / 60, current % 60, total / 60, total % 60))
        }
    }

    private func bindVideoPaintable() {
        guard let gst, let paintable = swift_openui_gst_player_paintable(gst) else { return }
        gtk_swift_video_surface_set_paintable(videoWidget, paintable)
    }

    private func acknowledgeNativeSeekIfReady() {
        if acceptedSeek != nil, let gst,
           swift_openui_gst_player_native_seek_completed(gst) != 0 {
            acceptedSeek = nil
        }
    }

    private func presentFrame() {
        if let gst, let mediaSelectionAsset,
           swift_openui_gst_player_stream_collection_generation(gst) != mediaSelectionGeneration {
            refreshMediaSelectionGroups(on: mediaSelectionAsset)
        }
        if let target = pendingSeek, durationSeconds > 0 {
            pendingSeek = nil
            seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }
        applyPlaybackRateIfReady()
        guard let gst else { return }
        if swift_openui_gst_player_paintable(gst) != nil {
            // A queued invalidation may belong to the previous segment. Only
            // the matching seek segment plus completed preroll acknowledges it.
            acknowledgeNativeSeekIfReady()
            return
        }
        var data: UnsafeMutablePointer<UInt8>?
        var length: gsize = 0
        var width: gint = 0
        var height: gint = 0
        var stride: gint = 0
        if swift_openui_gst_player_pull_frame(gst, &data, &length, &width, &height, &stride) != 0, let data {
            // A flushing seek discards every pre-seek sample. The first sample
            // that can be pulled afterward therefore acknowledges the new
            // segment without relying on transient position-query values.
            acceptedSeek = nil
            gtk_swift_video_surface_set_pixels(videoWidget, data, length, width, height, stride)
            swift_openui_gst_player_free_frame(data)
        }
    }

    private func handlePlaybackEvent() {
        guard let gst else { return }
        if let message = swift_openui_gst_player_take_error(gst) {
            let description = String(cString: message)
            g_free(message)
            player?._swiftOpenUIOnFailure?(description)
        } else if swift_openui_gst_player_has_ended(gst) != 0 {
            // Preserve the final paintable, including any coalesced last frame.
            presentFrame()
            player?._swiftOpenUIOnEnded?()
        }
    }

    private func applyPlaybackRateIfReady() {
        guard rateNeedsApplication, let gst else { return }
        let position = pendingRatePosition
        let nanoseconds = position.map { gint64($0 * 1_000_000_000) } ?? -1
        if swift_openui_gst_player_set_rate(gst, Double(playbackRate), nanoseconds) != 0 {
            rateNeedsApplication = false
            pendingRatePosition = nil
            if let position { acceptedSeek = position }
        }
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
