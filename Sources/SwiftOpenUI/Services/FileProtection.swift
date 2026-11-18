import Foundation

/// File protection for data the app must read while the device is locked.
/// Same API on every backend; this platform has no per-file protection.
nonisolated public enum FileProtection {
    public static var readableWhileLocked: [FileAttributeKey: Any]? { nil }
}
