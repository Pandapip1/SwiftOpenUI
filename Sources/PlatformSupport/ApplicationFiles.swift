import Foundation

/// Where an application keeps its data, and how its files are protected.
/// Applications state what they want once; how each operating system
/// provides it lives here. These follow the operating system, not the UI
/// backend.
public enum ApplicationStorage {
    public enum DurableDataLocation: Sendable {
        /// The Application Support directory.
        case applicationSupport
        /// The Caches directory.
        case caches
    }

    /// Where data meant to last belongs. tvOS gives applications no durable
    /// application-managed local storage: its Caches directory is the
    /// supported home for downloaded data and, unlike Application Support,
    /// is present in the app container. Everywhere else it is Application
    /// Support.
    public static var durableDataLocation: DurableDataLocation {
        #if os(tvOS)
        .caches
        #else
        .applicationSupport
        #endif
    }
}

public enum FileProtection {
    /// Writes `data` atomically, readable only while the device is unlocked
    /// where the system protects files that way (iOS and iPadOS: complete
    /// file protection). Elsewhere an ordinary atomic write.
    public static func writeProtected(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    /// Makes the existing files among `paths` readable only while the device
    /// is unlocked, where the system protects files that way (iOS and
    /// iPadOS). Missing files are skipped; elsewhere nothing changes.
    public static func protectExistingFiles(atPaths paths: [String]) {
        #if os(iOS)
        for path in paths where FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        }
        #endif
    }

    /// Keeps the file at `url` out of the device's backups, where the
    /// system backs devices up as a whole (iOS, iPadOS, tvOS, visionOS).
    /// Elsewhere nothing changes.
    public static func excludeFromDeviceBackup(_ url: URL) throws {
        #if os(iOS) || os(tvOS) || os(visionOS)
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        #endif
    }
}

/// Which kind of device the application runs on, for integrations that
/// describe the host to code written for other clients (for example,
/// Grayjay plugins' `buildPlatform`).
public enum HostPlatform {
    public enum Family: Sendable {
        /// macOS, Linux, Windows.
        case desktop
        case android
        /// iOS, iPadOS, tvOS, visionOS, watchOS.
        case appleMobile
    }

    public static var family: Family {
        #if os(macOS) || os(Linux) || os(Windows)
        .desktop
        #elseif os(Android)
        .android
        #else
        .appleMobile
        #endif
    }
}
