#if canImport(SwiftUI)
import Foundation
import Synchronization
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Whether the application is the one the user is using, from the system's
/// application activation. Observers may be called from any thread, and are
/// called with the current state when they subscribe.
public enum ApplicationActivity {
    nonisolated private static let observers = Mutex<[@Sendable (Bool) -> Void]>([])
    nonisolated private static let active = Mutex(true)
    nonisolated private static let started = Mutex(false)

    nonisolated public static var isActive: Bool { active.withLock { $0 } }

    nonisolated public static func observe(_ observer: @escaping @Sendable (Bool) -> Void) {
        observers.withLock { $0.append(observer) }
        startObserving()
        observer(isActive)
    }

    nonisolated private static func startObserving() {
        let first = started.withLock { started in
            defer { started = true }
            return !started
        }
        guard first else { return }
        let center = NotificationCenter.default
        #if canImport(UIKit)
        let becameActive = UIApplication.didBecomeActiveNotification
        let resigned = UIApplication.willResignActiveNotification
        #elseif canImport(AppKit)
        let becameActive = NSApplication.didBecomeActiveNotification
        let resigned = NSApplication.didResignActiveNotification
        #endif
        _ = center.addObserver(forName: becameActive, object: nil, queue: nil) { _ in set(true) }
        _ = center.addObserver(forName: resigned, object: nil, queue: nil) { _ in set(false) }
    }

    nonisolated private static func set(_ value: Bool) {
        let changed = active.withLock { active in
            defer { active = value }
            return active != value
        }
        guard changed else { return }
        for observer in observers.withLock({ $0 }) { observer(value) }
    }
}
#endif
