import Foundation
#if os(Linux)
import Glibc
#endif

/// The platform's answer to "how old is the person using this device?",
/// asked at the moment a decision needs it. Nothing here caches or stores
/// the answer: age changes over time, and the platform is the authority.
/// Same API as the SwiftUI backend's implementation.
public enum AgeAssurance {
    public enum Answer: Sendable, Equatable {
        /// The age range the platform shared, bounds inclusive and in years.
        /// Either bound can be open. The bounds are no finer than the gates
        /// that were asked for.
        case range(lowerBound: Int?, upperBound: Int?)
        /// The person, or whoever manages their account, chose not to share.
        case declined
        /// This platform, account or region has no age source right now.
        case unavailable
    }

    /// Asks the platform now. `gates` are the ages the decision cares about.
    ///
    /// Linux: the current user's systemd JSON user record (`birthDate`,
    /// YYYY-MM-DD, systemd 261+, set by an administrator with homectl), read
    /// over the io.systemd.UserDatabase Varlink interface. Only the range
    /// between the gates leaves this function; the date is never kept.
    /// Missing field, older systemd or no userdb: `.unavailable`.
    ///
    /// Windows: not wired up yet. The source is WinRT
    /// `Windows.System.User.CheckUserAgeConsentGroupAsync` (Windows 11,
    /// legacy; Microsoft's announced successor is `CheckAgeStatusAsync`),
    /// which needs WinRT bindings in the Win32 backend; until then
    /// `.unavailable`.
    @MainActor
    public static func currentAgeRange(gates: [Int]) async -> Answer {
        let sorted = Array(Set(gates.filter { $0 > 0 })).sorted()
        guard !sorted.isEmpty else { return .unavailable }
        #if os(Linux)
        guard let age = await Task.detached(priority: .userInitiated, operation: { UserDatabase.currentUserAge() }).value else {
            return .unavailable
        }
        return range(forAge: age, gates: sorted)
        #else
        return .unavailable
        #endif
    }

    /// The narrowest range between `gates` that contains `age`.
    static func range(forAge age: Int, gates: [Int]) -> Answer {
        let lower = gates.last { $0 <= age }
        let upper = gates.first { $0 > age }.map { $0 - 1 }
        return .range(lowerBound: lower ?? 0, upperBound: upper)
    }
}

#if os(Linux)
/// A minimal Varlink client for systemd's user database.
private enum UserDatabase {
    static let socketPath = "/run/systemd/userdb/io.systemd.Multiplexer"

    /// The current user's age in whole years from their user record's
    /// `birthDate`, or nil when the record, the field or userdb is missing.
    static func currentUserAge(now: Date = Date()) -> Int? {
        guard let entry = getpwuid(getuid()), let namePointer = entry.pointee.pw_name else { return nil }
        let userName = String(cString: namePointer)
        let request: [String: Any] = [
            "method": "io.systemd.UserDatabase.GetUserRecord",
            "parameters": ["userName": userName, "service": "io.systemd.Multiplexer"],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: request),
              let reply = exchange(body),
              let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              object["error"] == nil,
              let parameters = object["parameters"] as? [String: Any],
              let record = parameters["record"] as? [String: Any] else { return nil }
        let privileged = record["privileged"] as? [String: Any]
        guard let birthDate = (record["birthDate"] ?? privileged?["birthDate"]) as? String else { return nil }
        return age(fromISODate: birthDate, now: now)
    }

    static func age(fromISODate text: String, now: Date) -> Int? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let birth = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              birth <= now,
              let years = calendar.dateComponents([.year], from: birth, to: now).year else { return nil }
        return years
    }

    /// Sends one Varlink message (NUL-terminated JSON) and reads one reply.
    private static func exchange(_ message: Data) -> Data? {
        let descriptor = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue) | Int32(SOCK_CLOEXEC.rawValue), 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        var outgoing = message
        outgoing.append(0)
        let sent = outgoing.withUnsafeBytes { send(descriptor, $0.baseAddress, $0.count, Int32(MSG_NOSIGNAL)) }
        guard sent == outgoing.count else { return nil }

        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while reply.count < 1 << 20 {
            let count = chunk.withUnsafeMutableBytes { recv(descriptor, $0.baseAddress, $0.count, 0) }
            guard count > 0 else { return nil }
            if let end = chunk[0..<count].firstIndex(of: 0) {
                reply.append(contentsOf: chunk[0..<end])
                return reply
            }
            reply.append(contentsOf: chunk[0..<count])
        }
        return nil
    }
}
#endif
