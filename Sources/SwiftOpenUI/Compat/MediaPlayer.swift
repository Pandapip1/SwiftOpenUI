import Foundation

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
    func play()
    func pause()
    func seek(to seconds: Double)
    func stop()
    var currentTime: Double { get }
    var duration: Double { get }
    var isPlaying: Bool { get }
    var tracks: [MediaTrack] { get }
    func selectTrack(_ track: MediaTrack?)
    var pictureInPictureSupported: Bool { get }
    func startPictureInPicture()
    func stopPictureInPicture()
}

public extension MediaPlayerDriver {
    var tracks: [MediaTrack] { [] }
    func selectTrack(_: MediaTrack?) {}
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
    private var pending: (url: URL, autoplay: Bool, startAt: Double)?

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
            let queued = pending
            pending = nil
            lock.unlock()
            if let queued, let newValue { newValue.open(url: queued.url, autoplay: queued.autoplay, startAt: queued.startAt) }
        }
    }

    public func open(_ url: URL, autoplay: Bool = true, startAt: Double = 0) {
        lock.lock()
        self.url = url
        if let d = _driver { lock.unlock(); d.open(url: url, autoplay: autoplay, startAt: startAt) }
        else { pending = (url, autoplay, startAt); lock.unlock() }
    }

    public func play() { driver?.play() }
    public func pause() { driver?.pause() }
    public func seek(to seconds: Double) { driver?.seek(to: seconds) }

    public func stop() {
        lock.lock(); pending = nil; url = nil; lock.unlock()
        driver?.stop()
    }

    public var currentTime: Double { driver?.currentTime ?? 0 }
    public var duration: Double { driver?.duration ?? 0 }
    public var isPlaying: Bool { driver?.isPlaying ?? false }

    public var tracks: [MediaTrack] { driver?.tracks ?? [] }
    public func selectTrack(_ track: MediaTrack?) { driver?.selectTrack(track) }
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
