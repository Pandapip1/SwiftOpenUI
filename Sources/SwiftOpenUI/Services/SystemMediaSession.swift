import Foundation

/// The system's side of media playback (audio session events, remote
/// commands, Now Playing). Same API on every backend; this renderer has none
/// of them yet (MPRIS would be the Linux counterpart), so nothing is reported
/// and nothing is published.
@MainActor
public enum SystemMediaSession {
    public enum AudioEvent: Equatable, Sendable {
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        case outputLost
        case mediaServicesReset
    }

    public enum RemoteCommand: Equatable, Sendable {
        case play, pause, togglePlayPause
        case seek(to: Double)
        case skip(by: Double)
    }

    public struct NowPlaying: Equatable, Sendable {
        public var title: String
        public var duration: Double
        public var position: Double
        public var rate: Float
        public init(title: String, duration: Double, position: Double, rate: Float) {
            self.title = title
            self.duration = duration
            self.position = position
            self.rate = rate
        }
    }

    @discardableResult
    public static func observeAudio(_ handler: @escaping @MainActor (AudioEvent) -> Void) -> UUID { UUID() }
    public static func stopObserving(_ id: UUID) {}
    public static func activateForPlayback(failed: @escaping @MainActor (String) -> Void = { _ in }) {}
    public static func deactivate() {}

    private static var owner: ObjectIdentifier?
    public static func takeRemoteCommands(owner: AnyObject, _ handler: @escaping @MainActor (RemoteCommand) -> Bool) {
        self.owner = ObjectIdentifier(owner)
    }
    public static func releaseRemoteCommands(owner: AnyObject) {
        if self.owner == ObjectIdentifier(owner) { self.owner = nil }
    }
    public static func ownsRemoteCommands(_ owner: AnyObject) -> Bool { self.owner == ObjectIdentifier(owner) }
    public static func publishNowPlaying(_ nowPlaying: NowPlaying?) {}
}
