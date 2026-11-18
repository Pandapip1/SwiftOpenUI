#if canImport(SwiftUI)
import Foundation
import AVFoundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// The system's side of media playback, one API on every backend: audio
/// session events (interruptions, lost output, media-services resets), the
/// remote commands of the lock screen, Control Center, headphones, CarPlay
/// and Siri, and the Now Playing information they show.
///
/// SwiftUI backend: AVAudioSession on iOS, tvOS and visionOS (macOS has no
/// audio session, so no session events), MPRemoteCommandCenter and
/// MPNowPlayingInfoCenter where MediaPlayer exists. Other renderers: none yet
/// (MPRIS would be the Linux counterpart).
@MainActor
public enum SystemMediaSession {
    public enum AudioEvent: Equatable, Sendable {
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        /// The output went away (headphones unplugged).
        case outputLost
        /// The system restarted its media services: players must be rebuilt.
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

    // MARK: audio session

    private static var audioObservers: [UUID: (AudioEvent) -> Void] = [:]
    private static var observing = false
    private static var sessionActive = false
    private static let sessionQueue = DispatchQueue(label: "SwiftOpenUI.AudioSession", qos: .userInitiated)

    /// Calls `handler` on the main actor for every audio session event.
    /// Returns a token for `stopObserving`.
    @discardableResult
    public static func observeAudio(_ handler: @escaping @MainActor (AudioEvent) -> Void) -> UUID {
        let id = UUID()
        audioObservers[id] = handler
        startObservingAudio()
        return id
    }

    public static func stopObserving(_ id: UUID) {
        audioObservers[id] = nil
    }

    private static func deliver(_ event: AudioEvent) {
        if case .interruptionBegan = event { sessionActive = false }
        if case .mediaServicesReset = event { sessionActive = false }
        for handler in audioObservers.values { handler(event) }
    }

    private static func startObservingAudio() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        _ = center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            let event: AudioEvent? = switch type {
            case .began?: .interruptionBegan
            case .ended?: .interruptionEnded(shouldResume: options.contains(.shouldResume))
            default: nil
            }
            guard let event else { return }
            MainActor.assumeIsolated { deliver(event) }
        }
        _ = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { deliver(.outputLost) }
        }
        _ = center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { deliver(.mediaServicesReset) }
        }
        #endif
    }

    /// Activates the playback audio session (once; re-applying the category
    /// to an active session is audible). Reports failure to `failed`.
    public static func activateForPlayback(failed: @escaping @MainActor (String) -> Void = { _ in }) {
        #if os(iOS) || os(tvOS) || os(visionOS)
        guard !sessionActive else { return }
        sessionActive = true
        sessionQueue.async {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in
                    sessionActive = false
                    failed(message)
                }
            }
        }
        #endif
    }

    /// Deactivates it (off the main thread: it is a synchronous XPC call).
    public static func deactivate() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        sessionActive = false
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }

    // MARK: remote commands and Now Playing

    private static var commandHandler: ((RemoteCommand) -> Bool)?
    private static var commandOwner: ObjectIdentifier?
    private static var installedCommands = false

    /// `owner` now receives the remote commands (the video that played last).
    /// The handler returns whether it handled the command.
    public static func takeRemoteCommands(owner: AnyObject, _ handler: @escaping @MainActor (RemoteCommand) -> Bool) {
        commandOwner = ObjectIdentifier(owner)
        commandHandler = handler
        installCommands()
    }

    /// `owner` gives up the remote commands and Now Playing (if it has them).
    public static func releaseRemoteCommands(owner: AnyObject) {
        guard commandOwner == ObjectIdentifier(owner) else { return }
        commandOwner = nil
        commandHandler = nil
        publishNowPlaying(nil)
    }

    public static func ownsRemoteCommands(_ owner: AnyObject) -> Bool { commandOwner == ObjectIdentifier(owner) }

    private static func installCommands() {
        #if canImport(MediaPlayer)
        guard !installedCommands else { return }
        installedCommands = true
        let center = MPRemoteCommandCenter.shared()
        func route(_ command: MPRemoteCommand, _ map: @escaping (MPRemoteCommandEvent) -> RemoteCommand?) {
            command.isEnabled = true
            command.addTarget { event in
                let mapped = map(event)
                return MainActor.assumeIsolated {
                    guard let mapped, let handler = commandHandler, handler(mapped) else { return .commandFailed }
                    return .success
                }
            }
        }
        route(center.playCommand) { _ in .play }
        route(center.pauseCommand) { _ in .pause }
        route(center.togglePlayPauseCommand) { _ in .togglePlayPause }
        route(center.changePlaybackPositionCommand) { event in
            (event as? MPChangePlaybackPositionCommandEvent).map { .seek(to: $0.positionTime) }
        }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        route(center.skipForwardCommand) { _ in .skip(by: 10) }
        route(center.skipBackwardCommand) { _ in .skip(by: -10) }
        #endif
    }

    /// What the lock screen and Control Center show (nil: nothing).
    public static func publishNowPlaying(_ nowPlaying: NowPlaying?) {
        #if canImport(MediaPlayer)
        let center = MPNowPlayingInfoCenter.default()
        guard let nowPlaying else {
            center.nowPlayingInfo = nil
            return
        }
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPMediaItemPropertyPlaybackDuration: nowPlaying.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: nowPlaying.position,
            MPNowPlayingInfoPropertyPlaybackRate: nowPlaying.rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        #if os(macOS)
        center.playbackState = nowPlaying.rate > 0 ? .playing : .paused
        #endif
        #endif
    }
}
#endif
