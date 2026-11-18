import Foundation
#if os(iOS) || os(macOS)
import AVFoundation
#endif
#if os(macOS)
import Security
#endif

/// The system's per-application camera authorization.
public enum CameraAuthorization {
    public enum Status: Sendable, Equatable {
        case authorized
        case notDetermined
        /// Denied by the user, or restricted (parental controls, management).
        case denied
    }

    /// The system's decision for this application, or nil where the system
    /// keeps no per-application camera authorization to report (tvOS,
    /// visionOS, Linux, whose portal asks at each use).
    public static func status() -> Status? {
        #if os(iOS) || os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .notDetermined
        }
        #else
        nil
        #endif
    }

    /// Asks the system for camera access, prompting if it hasn't been
    /// decided. Nil where `status()` is nil.
    public static func request() async -> Bool? {
        #if os(iOS) || os(macOS)
        await AVCaptureDevice.requestAccess(for: .video)
        #else
        nil
        #endif
    }
}

/// What the system's privacy controls know this application as, where they
/// key decisions by code signature (macOS). The code-signing calls must not
/// run on the main thread (Security reports them as a runtime issue there).
public enum CodeSigningIdentity {
    /// Whether the system identifies applications by code signature here.
    /// Where it doesn't, both accessors return nil.
    public static var isAvailable: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// The running code's signing identifier.
    public static func signingIdentifier() -> String? {
        #if os(macOS)
        guard let staticCode = staticSelf() else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let values = information as? [String: Any] else { return nil }
        return values[kSecCodeInfoIdentifier as String] as? String
        #else
        nil
        #endif
    }

    /// The running code's designated requirement, as text.
    public static func designatedRequirement() -> String? {
        #if os(macOS)
        guard let staticCode = staticSelf() else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
        return text as String
        #else
        nil
        #endif
    }

    #if os(macOS)
    private static func staticSelf() -> SecStaticCode? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess else { return nil }
        return staticCode
    }
    #endif
}

/// The system's stored local network privacy decisions.
public enum LocalNetworkPrivacy {
    /// The world-readable file in which the system keeps per-application
    /// local network decisions, so they can be read without touching the
    /// network (macOS: an undocumented keyed archive of rules matched by
    /// signing identifier). Nil where decisions can't be read this way.
    public static var recordedDecisionsFile: URL? {
        #if os(macOS)
        URL(fileURLWithPath: "/Library/Preferences/com.apple.networkextension.plist")
        #else
        nil
        #endif
    }
}

/// Whether the operating system asks the user before an application uses
/// protected resources (local network, camera): Apple platforms do; Linux
/// desktops have no such prompts, so access is simply open there.
public enum PrivacyPrompts {
    public static var areShownBySystem: Bool {
        #if canImport(Darwin)
        true
        #else
        false
        #endif
    }
}
