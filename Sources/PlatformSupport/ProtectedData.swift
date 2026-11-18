import Foundation
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

/// Whether files protected until the device is unlocked can be read and
/// written now, and when that changes: the system's protected-data
/// availability on iOS, iPadOS, tvOS and visionOS. Elsewhere (macOS, Linux,
/// Windows) files have no such protection and it is always available.
public enum ProtectedData {
    private struct State {
        var available = true
        var started = false
        var observers: [@Sendable (Bool) -> Void] = []
    }

    nonisolated private static let state = Mutex(State())

    /// Whether protected data is available. True until `startObserving()`
    /// has read the system's answer.
    nonisolated public static var isAvailable: Bool { state.withLock { $0.available } }

    /// Starts following the system's state. Call once at launch.
    @MainActor
    public static func startObserving() {
        let first = state.withLock { state in
            defer { state.started = true }
            return !state.started
        }
        guard first else { return }
        #if os(iOS) || os(tvOS) || os(visionOS)
        set(UIApplication.shared.isProtectedDataAvailable)
        let center = NotificationCenter.default
        _ = center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
                               object: nil, queue: nil) { _ in set(false) }
        _ = center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                               object: nil, queue: nil) { _ in set(true) }
        #endif
    }

    /// Calls `observer`, from any thread, whenever availability changes.
    nonisolated public static func observe(_ observer: @escaping @Sendable (Bool) -> Void) {
        state.withLock { $0.observers.append(observer) }
    }

    nonisolated private static func set(_ available: Bool) {
        let observers: [@Sendable (Bool) -> Void]? = state.withLock { state in
            guard state.available != available else { return nil }
            state.available = available
            return state.observers
        }
        for observer in observers ?? [] { observer(available) }
    }
}

extension FileProtection {
    /// A file's protection class: when its contents can be read.
    public enum Class: String, Sendable, CaseIterable {
        /// Readable only while the device is unlocked.
        case complete
        /// Can be created and, once open, written and read while locked;
        /// closed, readable only while unlocked.
        case completeUnlessOpen
        /// Readable after the first unlock since boot.
        case completeUntilFirstUserAuthentication
        /// Always readable.
        case unprotected
    }

    /// Sets the protection class of the file at `url`, where the system
    /// protects files (iOS, iPadOS, tvOS, visionOS); elsewhere nothing changes.
    public static func set(_ protection: Class, for url: URL) throws {
        #if os(iOS) || os(tvOS) || os(visionOS)
        try FileManager.default.setAttributes([.protectionKey: protection.type], ofItemAtPath: url.path)
        #endif
    }

    /// The protection class of the file at `url`; nil where the system has none.
    public static func current(of url: URL) -> Class? {
        #if os(iOS) || os(tvOS) || os(visionOS)
        guard let type = try? FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey]
                as? FileProtectionType else { return nil }
        return Class.allCases.first { $0.type == type }
        #else
        return nil
        #endif
    }
}

#if os(iOS) || os(tvOS) || os(visionOS)
extension FileProtection.Class {
    fileprivate var type: FileProtectionType {
        switch self {
        case .complete: .complete
        case .completeUnlessOpen: .completeUnlessOpen
        case .completeUntilFirstUserAuthentication: .completeUntilFirstUserAuthentication
        case .unprotected: .none
        }
    }
}
#endif
