#if canImport(SwiftUI)
import Foundation
import Synchronization

/// The device's power conditions: whether the user asked to save energy
/// (Low Power Mode) and how hot it runs. Same API as the portable version.
nonisolated public struct PowerConditions: Equatable, Sendable {
    public enum Thermal: Int, Comparable, Sendable {
        case nominal, fair, serious, critical
        public static func < (lhs: Thermal, rhs: Thermal) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var lowPower: Bool
    public var thermal: Thermal

    public init(lowPower: Bool = false, thermal: Thermal = .nominal) {
        self.lowPower = lowPower
        self.thermal = thermal
    }

    /// Work that can wait should wait.
    public var savesEnergy: Bool { lowPower || thermal >= .serious }
}

/// The device's power conditions from the system (Low Power Mode on iOS and
/// macOS, the thermal state), observable from any thread.
public enum PowerState {
    private struct State {
        var override: PowerConditions?
        var observers: [@Sendable (PowerConditions) -> Void] = []
        var last: PowerConditions?
        var started = false
    }

    nonisolated private static let state = Mutex(State())

    nonisolated private static var system: PowerConditions {
        let info = ProcessInfo.processInfo
        let thermal: PowerConditions.Thermal = switch info.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
        return PowerConditions(lowPower: info.isLowPowerModeEnabled, thermal: thermal)
    }

    nonisolated public static var current: PowerConditions { state.withLock { $0.override } ?? system }

    /// Calls `observer` now and whenever the conditions change.
    nonisolated public static func observe(_ observer: @escaping @Sendable (PowerConditions) -> Void) {
        let start = state.withLock { state in
            state.observers.append(observer)
            defer { state.started = true }
            return !state.started
        }
        if start {
            let center = NotificationCenter.default
            for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
                _ = center.addObserver(forName: name, object: nil, queue: nil) { _ in changed() }
            }
        }
        observer(current)
    }

    /// Replaces the system's conditions (tests, previews); nil: the system's again.
    nonisolated public static func report(_ conditions: PowerConditions?) {
        state.withLock { $0.override = conditions }
        changed()
    }

    nonisolated private static func changed() {
        let conditions = current
        let observers = state.withLock { state -> [@Sendable (PowerConditions) -> Void] in
            guard state.last != conditions else { return [] }
            state.last = conditions
            return state.observers
        }
        for observer in observers { observer(conditions) }
    }
}
#endif
