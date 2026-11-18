import Foundation
import Synchronization

/// The device's power conditions: whether the user asked to save energy
/// (Low Power Mode, a power-saver profile) and how hot it runs.
public struct PowerConditions: Equatable, Sendable {
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

/// The device's power conditions, observable from any thread. Backends report
/// them: on Linux the GTK backend follows power-profiles-daemon (the
/// "power-saver" profile); renderers that cannot tell report nothing, so the
/// conditions stay "not saving energy".
public enum PowerState {
    private struct State {
        var conditions = PowerConditions()
        var observers: [@Sendable (PowerConditions) -> Void] = []
    }

    nonisolated private static let state = Mutex(State())

    nonisolated public static var current: PowerConditions { state.withLock { $0.conditions } }

    /// Calls `observer` now and whenever the conditions change.
    nonisolated public static func observe(_ observer: @escaping @Sendable (PowerConditions) -> Void) {
        let conditions = state.withLock { state in
            state.observers.append(observer)
            return state.conditions
        }
        observer(conditions)
    }

    /// For backends (and tests): the conditions are now `conditions` (nil: not
    /// saving energy, the default when a renderer cannot tell).
    nonisolated public static func report(_ reported: PowerConditions?) {
        let conditions = reported ?? PowerConditions()
        let (changed, observers) = state.withLock { state in
            let changed = state.conditions != conditions
            state.conditions = conditions
            return (changed, state.observers)
        }
        guard changed else { return }
        for observer in observers { observer(conditions) }
    }
}
