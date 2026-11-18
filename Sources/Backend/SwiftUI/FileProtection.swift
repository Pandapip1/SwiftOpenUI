#if canImport(SwiftUI)
import Foundation

/// File protection for data the app must read while the device is locked
/// (media that keeps playing in the background or after sleep). Same API on
/// every backend.
nonisolated public enum FileProtection {
    /// Attributes for creating such a file: protected until the first unlock
    /// after boot (never `complete`, which makes files unreadable shortly
    /// after locking). nil where the platform has no such protection.
    public static var readableWhileLocked: [FileAttributeKey: Any]? {
        #if os(iOS) || os(tvOS) || os(visionOS)
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        nil
        #endif
    }
}
#endif
