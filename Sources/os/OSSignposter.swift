import Foundation
import Synchronization

/// Identifies a signpost interval, so overlapping intervals with the same
/// name can be told apart.
public struct OSSignpostID: Sendable, Hashable, Comparable {
    public let rawValue: UInt64

    public init(_ value: UInt64) { rawValue = value }

    /// For intervals that never overlap.
    public static let exclusive = OSSignpostID(0xEEEE_B0B5_B2B2_EEEE)
    public static let invalid = OSSignpostID(~0)
    public static let null = OSSignpostID(0)

    public static func < (lhs: OSSignpostID, rhs: OSSignpostID) -> Bool { lhs.rawValue < rhs.rawValue }

    static let counter = Atomic<UInt64>(0)

    static func next() -> OSSignpostID {
        OSSignpostID(counter.add(1, ordering: .relaxed).newValue)
    }
}

/// The state of an interval between `beginInterval` and `endInterval`.
public final class OSSignpostIntervalState: Sendable {
    let id: OSSignpostID
    let begin: ContinuousClock.Instant

    init(id: OSSignpostID, begin: ContinuousClock.Instant) {
        self.id = id
        self.begin = begin
    }
}

/// Signposts for platforms without `os`.
///
/// Every interval begin and end and every event becomes a journal entry with
/// `SIGNPOST_NAME`, `SIGNPOST_ID` and `SIGNPOST_TYPE` (`begin`, `end` or
/// `event`) fields, plus `SIGNPOST_DURATION_US` on ends, in the logger's
/// subsystem and category at debug priority. Query them with, for example,
/// `journalctl --user OSLOG_SUBSYSTEM=com.example SIGNPOST_TYPE=end -o json`.
/// They are written only with `SWIFTOPENUI_SIGNPOSTS=1` or when the log level
/// is debug; `isEnabled` reports which.
public struct OSSignposter: Sendable {
    let logger: Logger
    let enabled: Bool

    public init(subsystem: String, category: String) {
        self.init(logger: Logger(subsystem: subsystem, category: category))
    }

    public init(logger: Logger) {
        self.logger = logger
        enabled = LogSink.shared.signpostsEnabled
    }

    private init(disabledLogger logger: Logger) {
        self.logger = logger
        enabled = false
    }

    public static let disabled = OSSignposter(disabledLogger: Logger())

    public var isEnabled: Bool { enabled }

    public func makeSignpostID() -> OSSignpostID { .next() }

    public func makeSignpostID(from object: AnyObject) -> OSSignpostID {
        OSSignpostID(UInt64(UInt(bitPattern: ObjectIdentifier(object).hashValue)))
    }

    public func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive) -> OSSignpostIntervalState {
        beginInterval(name, id: id, "")
    }

    public func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: OSLogMessage) -> OSSignpostIntervalState {
        let state = OSSignpostIntervalState(id: id, begin: .now)
        record(type: "begin", name: name, id: id, message: message, extra: [])
        return state
    }

    public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        endInterval(name, state, "")
    }

    public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState, _ message: OSLogMessage) {
        let elapsed = ContinuousClock.now - state.begin
        let (seconds, attoseconds) = elapsed.components
        let microseconds = seconds * 1_000_000 + attoseconds / 1_000_000_000_000
        record(type: "end", name: name, id: state.id, message: message,
               extra: [("SIGNPOST_DURATION_US", String(microseconds))])
    }

    public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive) {
        emitEvent(name, id: id, "")
    }

    public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: OSLogMessage) {
        record(type: "event", name: name, id: id, message: message, extra: [])
    }

    public func withIntervalSignpost<T>(
        _ name: StaticString, id: OSSignpostID = .exclusive, _ message: OSLogMessage = "",
        around task: () throws -> T
    ) rethrows -> T {
        let state = beginInterval(name, id: id, message)
        defer { endInterval(name, state) }
        return try task()
    }

    private func record(type: String, name: StaticString, id: OSSignpostID, message: OSLogMessage,
                        extra: [(String, String)]) {
        guard enabled else { return }
        let detail = message.formatted(revealPrivate: LogSink.shared.revealPrivate)
        let summary = OSLogMessage(stringLiteral: "signpost \(type) \(name)\(detail.isEmpty ? "" : ": \(detail)")")
        LogSink.shared.write(
            level: .debug, subsystem: logger.subsystem, category: logger.category, message: summary,
            extraFields: [
                ("SIGNPOST_TYPE", type),
                ("SIGNPOST_NAME", name.description),
                ("SIGNPOST_ID", String(id.rawValue, radix: 16)),
            ] + extra,
            bypassThreshold: true
        )
    }
}
