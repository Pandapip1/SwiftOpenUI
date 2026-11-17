import Foundation
import Synchronization

/// Whether the application is the one the user is using: one of its windows
/// is active. Backends report changes; anything may observe them, from any
/// thread. Observers are called with the current state when they subscribe.
public enum ApplicationActivity {
    private struct State {
        var activeWindows: Set<Int> = []
        var observers: [@Sendable (Bool) -> Void] = []
    }

    nonisolated private static let state = Mutex(State())

    /// Whether a window of this application is active.
    nonisolated public static var isActive: Bool { state.withLock { !$0.activeWindows.isEmpty } }

    /// Calls `observer` now and whenever the application becomes active or
    /// inactive.
    nonisolated public static func observe(_ observer: @escaping @Sendable (Bool) -> Void) {
        let active = state.withLock { state in
            state.observers.append(observer)
            return !state.activeWindows.isEmpty
        }
        observer(active)
    }

    /// For backends: window `id` became active or inactive.
    nonisolated public static func windowActivityChanged(_ id: Int, isActive: Bool) {
        let (changed, active, observers) = state.withLock { state in
            let before = !state.activeWindows.isEmpty
            if isActive { state.activeWindows.insert(id) } else { state.activeWindows.remove(id) }
            let after = !state.activeWindows.isEmpty
            return (before != after, after, state.observers)
        }
        guard changed else { return }
        for observer in observers { observer(active) }
    }
}
