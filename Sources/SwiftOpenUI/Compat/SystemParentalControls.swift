import Foundation
#if os(Linux)
import Glibc
#endif

/// The operating system's parental controls for the current user, and its
/// "ask a parent" flow. Apps have no passcode of their own: the parent's
/// authority is the system's. Same API as the SwiftUI backend's.
public enum SystemParentalControls {
    public enum Status: Sendable, Equatable {
        /// The system reports no parental controls for this user.
        case notSupervised
        /// A parent manages this user. `allowsInstallingApps`: whether the
        /// parent lets them install software themselves. `contentAgeLimit`:
        /// the highest content age the parent allows, when the system says.
        case supervised(allowsInstallingApps: Bool, contentAgeLimit: Int?)
        /// The system cannot say (no API, not installed, not available here).
        case unavailable
    }

    public enum Request: Sendable, Equatable {
        /// The question went to the parent; its answer arrives later on
        /// `parentResponses()` with this id.
        case sent(id: UUID)
        /// This system has no way to ask a parent.
        case unavailable
    }

    public struct ParentResponse: Sendable, Equatable {
        public let requestID: UUID
        public let approved: Bool
    }

    /// Linux: GNOME malcontent's app filter for the current user, read from
    /// accountsservice (`org.freedesktop.Accounts`, object
    /// `/org/freedesktop/Accounts/User<uid>`, interface
    /// `com.endlessm.ParentalControls.AppFilter`; reading your own needs no
    /// authentication by default). No accountsservice or no malcontent:
    /// `.unavailable`. Default values throughout: `.notSupervised`.
    ///
    /// Windows: Family Safety needs WinRT bindings the Win32 backend does not
    /// have yet: `.unavailable`.
    @MainActor
    public static func status() async -> Status {
        #if os(Linux)
        return await Task.detached(priority: .userInitiated) { Malcontent.status() }.value
        #else
        return .unavailable
        #endif
    }

    /// malcontent has no "ask a parent" request flow: a parent changes the
    /// child's settings in Parental Controls. So `.unavailable` here.
    @MainActor
    public static func askParent(_ description: String) async -> Request {
        .unavailable
    }

    public static func parentResponses() -> AsyncStream<ParentResponse> {
        AsyncStream { $0.finish() }
    }
}

#if os(Linux)
/// Reads malcontent's settings through `busctl` (systemd), so no D-Bus
/// library is linked.
enum Malcontent {
    static func status() -> SystemParentalControls.Status {
        let path = "/org/freedesktop/Accounts/User\(getuid())"
        guard let data = run([
            "--system", "--json=short", "call", "org.freedesktop.Accounts", path,
            "org.freedesktop.DBus.Properties", "GetAll", "s", "com.endlessm.ParentalControls.AppFilter",
        ]) else { return .unavailable }
        return parse(data)
    }

    /// `busctl --json=short` output for `GetAll` → a{sv}:
    /// `{"type":"a{sv}","data":[{"AppFilter":{"type":"(bas)","data":[false,[]]}, …}]}`.
    static func parse(_ data: Data) -> SystemParentalControls.Status {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outer = root["data"] as? [Any], let properties = outer.first as? [String: Any],
              !properties.isEmpty else { return .unavailable }
        func value(_ name: String) -> Any? { (properties[name] as? [String: Any])?["data"] }

        let appFilter = value("AppFilter") as? [Any]
        let isAllowlist = appFilter?.first as? Bool ?? false
        let appEntries = (appFilter?.dropFirst().first as? [Any]) ?? []
        let oars = value("OarsFilter") as? [Any]
        let oarsSections = (oars?.dropFirst().first as? [String: Any]) ?? [:]
        let allowsUserInstallation = value("AllowUserInstallation") as? Bool ?? true

        let filtersApps = isAllowlist || !appEntries.isEmpty
        let filtersContent = !oarsSections.isEmpty
        guard filtersApps || filtersContent || !allowsUserInstallation else { return .notSupervised }
        // Any OARS content filter: only all-ages content is within it.
        return .supervised(allowsInstallingApps: allowsUserInstallation,
                           contentAgeLimit: filtersContent ? 0 : nil)
    }

    private static let busctlPaths = ["/usr/bin/busctl", "/run/current-system/sw/bin/busctl", "/bin/busctl"]

    private static func run(_ arguments: [String]) -> Data? {
        guard let executable = busctlPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
#endif
