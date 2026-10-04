import Foundation

/// A media asset used to create a player item. A supplemental audio URL models
/// the video and audio tracks of a composition while keeping URL loading in the
/// platform driver.
public struct MediaAsset: Hashable, Sendable {
    public let videoURL: URL
    public let audioURL: URL?

    public init(url: URL) {
        videoURL = url
        audioURL = nil
    }

    public init(videoURL: URL, audioURL: URL) {
        self.videoURL = videoURL
        self.audioURL = audioURL
    }
}

/// The item installed on a `MediaPlayer`, analogous to `AVPlayerItem`.
public final class MediaPlayerItem: @unchecked Sendable {
    public let asset: MediaAsset
    public init(asset: MediaAsset) { self.asset = asset }
    public convenience init(url: URL) { self.init(asset: MediaAsset(url: url)) }
}

/// A selectable media rendition exposed by a backend.
public struct MediaTrack: Hashable, Sendable {
    public enum Kind: String, Sendable { case video, audio, subtitles }
    public let id: String
    public let kind: Kind
    public let language: String?
    public let label: String?

    public init(id: String, kind: Kind, language: String? = nil, label: String? = nil) {
        self.id = id; self.kind = kind; self.language = language; self.label = label
    }
}

/// What a backend provides to play media for a `VideoPlayer`.
public protocol MediaPlayerDriver: AnyObject {
    func open(url: URL, autoplay: Bool, startAt: Double)
    func replaceCurrentItem(with item: MediaPlayerItem?)
    func play()
    func pause()
    func seek(to seconds: Double)
    func stop()
    var currentTime: Double { get }
    var duration: Double { get }
    var isPlaying: Bool { get }
    var tracks: [MediaTrack] { get }
    func selectTrack(_ track: MediaTrack?)
    func setExternalSubtitle(_ url: URL?)
    var pictureInPictureSupported: Bool { get }
    func startPictureInPicture()
    func stopPictureInPicture()
}

public extension MediaPlayerDriver {
    func replaceCurrentItem(with item: MediaPlayerItem?) {
        guard let item else { stop(); return }
        open(url: item.asset.videoURL, autoplay: false, startAt: 0)
    }
    var tracks: [MediaTrack] { [] }
    func selectTrack(_: MediaTrack?) {}
    func setExternalSubtitle(_: URL?) {}
    var pictureInPictureSupported: Bool { false }
    func startPictureInPicture() {}
    func stopPictureInPicture() {}
}

/// Controls playback for a `VideoPlayer`, standing in for AVKit's `AVPlayer`.
///
/// The player works before its view exists: calls made earlier are remembered and applied when the backend attaches
/// its driver. Backends that cannot play media never attach a driver, and `onFailure` reports that.
public final class MediaPlayer: @unchecked Sendable {
    private let lock = NSLock()
    private var _driver: MediaPlayerDriver?
    private var pendingItem: MediaPlayerItem?
    private var pendingSeek: Double?
    private var pendingPlayback: Bool?

    public private(set) var url: URL?
    /// Called on the main thread when playback reaches the end.
    public var onEnded: (@Sendable () -> Void)?
    /// Called on the main thread with a human-readable reason when media cannot be opened or played.
    public var onFailure: (@Sendable (String) -> Void)?

    public init() {}

    /// Installed by the backend that renders the player's view.
    public var driver: MediaPlayerDriver? {
        get { lock.lock(); defer { lock.unlock() }; return _driver }
        set {
            lock.lock()
            _driver = newValue
            let item = pendingItem
            let seek = pendingSeek
            let playback = pendingPlayback
            pendingItem = nil
            pendingSeek = nil
            pendingPlayback = nil
            lock.unlock()
            if let newValue {
                if let item { newValue.replaceCurrentItem(with: item) }
                if let seek { newValue.seek(to: seek) }
                if playback == true { newValue.play() }
                else if playback == false { newValue.pause() }
            }
        }
    }

    public func open(_ url: URL, autoplay: Bool = true, startAt: Double = 0) {
        replaceCurrentItem(with: MediaPlayerItem(url: url))
        if startAt > 0 { seek(to: startAt) }
        if autoplay { play() } else { pause() }
    }

    /// Replaces the current item, matching AVPlayer's item-based API.
    public func replaceCurrentItem(with item: MediaPlayerItem?) {
        lock.lock()
        self.url = item?.asset.videoURL
        if let d = _driver {
            lock.unlock()
            d.replaceCurrentItem(with: item)
        } else if let item {
            pendingItem = item
            lock.unlock()
        } else {
            pendingItem = nil
            pendingSeek = nil
            pendingPlayback = nil
            lock.unlock()
        }
    }

    public func play() {
        lock.lock()
        if let driver = _driver { lock.unlock(); driver.play() }
        else { pendingPlayback = true; lock.unlock() }
    }
    public func pause() {
        lock.lock()
        if let driver = _driver { lock.unlock(); driver.pause() }
        else { pendingPlayback = false; lock.unlock() }
    }
    public func seek(to seconds: Double) {
        lock.lock()
        if let driver = _driver { lock.unlock(); driver.seek(to: seconds) }
        else { pendingSeek = seconds; lock.unlock() }
    }

    public func stop() {
        lock.lock(); pendingItem = nil; pendingSeek = nil; pendingPlayback = nil; url = nil; lock.unlock()
        driver?.stop()
    }

    public var currentTime: Double { driver?.currentTime ?? 0 }
    public var duration: Double { driver?.duration ?? 0 }
    public var isPlaying: Bool { driver?.isPlaying ?? false }

    public var tracks: [MediaTrack] { driver?.tracks ?? [] }
    public func selectTrack(_ track: MediaTrack?) { driver?.selectTrack(track) }
    public func setExternalSubtitle(_ url: URL?) { driver?.setExternalSubtitle(url) }
    public var pictureInPictureSupported: Bool { driver?.pictureInPictureSupported ?? false }
    public func startPictureInPicture() { driver?.startPictureInPicture() }
    public func stopPictureInPicture() { driver?.stopPictureInPicture() }
}

/// A video surface with the platform's playback controls, driven by a `MediaPlayer`.
public struct VideoPlayer: View, PrimitiveView {
    public typealias Body = Never
    public let player: MediaPlayer
    public init(player: MediaPlayer) { self.player = player }
    public var body: Never { fatalError("VideoPlayer is a primitive view") }
}
