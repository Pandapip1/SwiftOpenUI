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
        let filter = oarsSections.compactMapValues { $0 as? String }
        guard filtersApps || !filter.isEmpty || !allowsUserInstallation else { return .notSupervised }
        return .supervised(allowsInstallingApps: allowsUserInstallation,
                           contentAgeLimit: OARS.contentAgeLimit(filter: filter))
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

/// Open Age Ratings Service (OARS) categories and their ages, for turning a
/// per-category content filter into one age limit.
///
/// The ages are libappstream's published OARS → Common Sense Media mapping
/// (`oars_to_csm_mappings` in AppStream's src/as-content-rating.c, used by
/// `as_content_rating_attribute_to_csm_age`, which gnome-software and
/// malcontent rely on): for each category, the age at which content of
/// intensity none, mild, moderate and intense is appropriate.
enum OARS {
    static let intensities = ["none", "mild", "moderate", "intense"]

    static let ages: [String: [Int]] = [
        // OARS 1.0
        "violence-cartoon": [0, 3, 4, 6],
        "violence-fantasy": [0, 3, 7, 8],
        "violence-realistic": [0, 4, 9, 14],
        "violence-bloodshed": [0, 9, 11, 18],
        "violence-sexual": [0, 18, 18, 18],
        "drugs-alcohol": [0, 11, 13, 16],
        "drugs-narcotics": [0, 12, 14, 17],
        "drugs-tobacco": [0, 10, 13, 13],
        "sex-nudity": [0, 12, 14, 14],
        "sex-themes": [0, 13, 14, 15],
        "language-profanity": [0, 8, 11, 14],
        "language-humor": [0, 3, 8, 14],
        "language-discrimination": [0, 9, 10, 11],
        "money-advertising": [0, 7, 8, 10],
        "money-gambling": [0, 7, 10, 18],
        "money-purchasing": [0, 12, 14, 15],
        "social-chat": [0, 4, 10, 13],
        "social-audio": [0, 15, 15, 15],
        "social-contacts": [0, 12, 12, 12],
        "social-info": [0, 0, 13, 13],
        "social-location": [0, 13, 13, 13],
        // OARS 1.1
        "sex-homosexuality": [0, 13, 14, 15],
        "sex-prostitution": [0, 12, 14, 18],
        "sex-adultery": [0, 8, 10, 18],
        "sex-appearance": [0, 10, 10, 15],
        "violence-worship": [0, 13, 15, 18],
        "violence-desecration": [0, 13, 15, 18],
        "violence-slavery": [0, 13, 15, 18],
    ]

    /// The highest content age a filter allows, or nil for no limit.
    ///
    /// The filter maps a category to the most intense level allowed in it.
    /// A source is rated only by age, so a source rated A may contain, in
    /// every category, anything appropriate at age A. It fits a category
    /// whose filter allows level L only if A is below the age of the next
    /// level up: the category's limit is that age minus one (no limit when
    /// L is "intense"). The strictest category wins, never below 0. An
    /// unknown category or level counts as allowing nothing above "none".
    static func contentAgeLimit(filter: [String: String]) -> Int? {
        var limit: Int?
        for (category, allowed) in filter {
            let level = intensities.firstIndex(of: allowed) ?? 0
            guard level < intensities.count - 1 else { continue }
            let next = ages[category]?[level + 1] ?? 0
            let categoryLimit = max(0, next - 1)
            limit = min(limit ?? categoryLimit, categoryLimit)
        }
        return limit
    }
}
