import Foundation

/// Where the scene (window) showing a view is in its life.
public enum LifecyclePhase: Sendable, Hashable {
    /// In front, taking input.
    case active
    /// Visible but not taking input (another window or app is in front).
    case inactive
    /// Not visible: backgrounded (iOS), or its window hidden.
    case background
}

/// Something that happened to the scene showing a view, or to the
/// application. Same API on every backend; see `View.onLifecycle`.
public enum LifecycleEvent: Sendable, Hashable {
    /// The scene's phase changed.
    case phase(LifecyclePhase)
    /// The application is about to quit. Work must finish before the
    /// action returns.
    case willTerminate
    /// The scene (window) is going away for good: closed, or its scene
    /// discarded. Delivered once, before its views are torn down, and not
    /// for hiding, minimising or backgrounding.
    case sceneEnded
}

extension View {
    /// Calls `action` with the lifecycle events of the scene (window) that
    /// shows this view, and with application termination.
    public func onLifecycle(perform action: @escaping @MainActor (LifecycleEvent) -> Void) -> some View {
        LifecycleObservingView(content: self, action: action)
    }

    /// Calls `action` once, when the scene (window) showing this view goes
    /// away for good or the application quits, whichever comes first: the
    /// place to stop what the window owns (playback, audio, timers).
    public func onSceneEnd(perform action: @escaping @MainActor () -> Void) -> some View {
        // At most one of the two reaches a view: a scene that ended is no
        // longer observed, and no scene ends after termination began.
        onLifecycle { event in
            if event == .sceneEnded || event == .willTerminate { action() }
        }
    }
}

/// Registers its action with `SceneLifecycle` for the window it appears in.
public struct LifecycleObservingView<Content: View>: View {
    let content: Content
    let action: @MainActor (LifecycleEvent) -> Void
    @State private var registration = SceneLifecycle.Registration()
    @Environment(\.windowID) private var windowID

    public var body: some View {
        // The latest action and window, as of this render.
        registration.action = action
        registration.windowID = windowID
        let registration = registration
        return content
            .onAppear { SceneLifecycle.attach(registration) }
            .onDisappear { SceneLifecycle.detach(registration) }
    }
}

/// Lifecycle bookkeeping shared by the portable backends. Backends report
/// what happens to their windows and the application; views observe it
/// through `View.onLifecycle` and `View.onSceneEnd`.
public enum SceneLifecycle {
    final class Registration {
        var action: @MainActor (LifecycleEvent) -> Void = { _ in }
        var windowID = 0
        var attached = false
        /// Bumped on every attach, so a detach scheduled before a re-attach
        /// doesn't remove it.
        var generation = 0
    }

    private static var registrations: [ObjectIdentifier: Registration] = [:]
    private static var terminating = false

    static func attach(_ registration: Registration) {
        registration.generation &+= 1
        registration.attached = true
        registrations[ObjectIdentifier(registration)] = registration
    }

    /// A window's views disappear while it closes, before the backend
    /// reports the end, so removal waits a turn of the main loop: a view
    /// in a closing window still hears `.sceneEnded`.
    static func detach(_ registration: Registration) {
        registration.attached = false
        let generation = registration.generation
        Task { @MainActor in
            guard !registration.attached, registration.generation == generation else { return }
            registrations[ObjectIdentifier(registration)] = nil
        }
    }

    /// For backends: window `windowID` changed phase.
    public static func windowPhaseChanged(_ windowID: Int, to phase: LifecyclePhase) {
        deliver(.phase(phase)) { $0.windowID == windowID }
    }

    /// For backends: window `windowID` is going away for good. Call it
    /// before the window's views are destroyed. Its views stop being
    /// observed, so later calls for the same window do nothing.
    public static func windowWillEnd(_ windowID: Int) {
        guard !terminating else { return }
        let ending = registrations.filter { $0.value.windowID == windowID }
        for key in ending.keys { registrations[key] = nil }
        for registration in ending.values { registration.action(.sceneEnded) }
    }

    /// For backends: the application is about to quit.
    public static func applicationWillTerminate() {
        guard !terminating else { return }
        terminating = true
        deliver(.willTerminate) { _ in true }
    }

    private static func deliver(_ event: LifecycleEvent, to matching: (Registration) -> Bool) {
        for registration in registrations.values where matching(registration) {
            registration.action(event)
        }
    }
}
