import Foundation

/// The severity of a log message, as on Apple platforms.
public struct OSLogType: Sendable, Equatable, Hashable {
    let rank: Int

    public static let debug = OSLogType(rank: 0)
    public static let info = OSLogType(rank: 1)
    public static let `default` = OSLogType(rank: 2)
    public static let error = OSLogType(rank: 3)
    public static let fault = OSLogType(rank: 4)

    /// syslog(3) priority, which journald stores as `PRIORITY`.
    var syslogPriority: Int {
        switch rank {
        case 0: 7
        case 1: 6
        case 2: 5
        case 3: 3
        default: 2
        }
    }

    var name: String {
        switch rank {
        case 0: "debug"
        case 1: "info"
        case 2: "notice"
        case 3: "error"
        default: "fault"
        }
    }

    init(rank: Int) { self.rank = rank }

    init?(name: String) {
        switch name.lowercased() {
        case "debug", "trace": self = .debug
        case "info": self = .info
        case "default", "notice": self = .default
        case "error", "warning": self = .error
        case "fault", "critical": self = .fault
        default: return nil
        }
    }
}

/// Unified-logging-shaped logger for platforms without `os`.
///
/// Messages go to the systemd journal as structured entries (`MESSAGE`,
/// `PRIORITY`, `OSLOG_SUBSYSTEM`, `OSLOG_CATEGORY`) when the journal is
/// running, and to standard error when it is not or when standard error is a
/// terminal. `SWIFTOPENUI_LOG_LEVEL` (debug, info, notice, error, fault; info
/// by default) sets the lowest level written, and `SWIFTOPENUI_LOG_PRIVATE=1`
/// reveals private values.
public struct Logger: Sendable {
    public let subsystem: String
    public let category: String

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    /// A logger with no subsystem or category, like Apple's default logger.
    public init() {
        self.init(subsystem: "", category: "")
    }

    public func log(_ message: OSLogMessage) { log(level: .default, message) }

    public func log(level: OSLogType, _ message: OSLogMessage) {
        LogSink.shared.write(level: level, subsystem: subsystem, category: category, message: message, extraFields: [])
    }

    public func trace(_ message: OSLogMessage) { log(level: .debug, message) }
    public func debug(_ message: OSLogMessage) { log(level: .debug, message) }
    public func info(_ message: OSLogMessage) { log(level: .info, message) }
    public func notice(_ message: OSLogMessage) { log(level: .default, message) }
    public func warning(_ message: OSLogMessage) { log(level: .error, message) }
    public func error(_ message: OSLogMessage) { log(level: .error, message) }
    public func critical(_ message: OSLogMessage) { log(level: .fault, message) }
    public func fault(_ message: OSLogMessage) { log(level: .fault, message) }
}

/// Where log and signpost records go: the journal, standard error, or both.
final class LogSink: Sendable {
    static let shared = LogSink(environment: ProcessInfo.processInfo.environment)

    let threshold: OSLogType
    let revealPrivate: Bool
    let signpostsEnabled: Bool
    let journal: JournalConnection?
    let writesStandardError: Bool
    let identifier: String

    init(environment: [String: String]) {
        threshold = environment["SWIFTOPENUI_LOG_LEVEL"].flatMap(OSLogType.init(name:)) ?? .info
        revealPrivate = environment["SWIFTOPENUI_LOG_PRIVATE"] == "1"
        // Signposts are trace data: off unless asked for, or when debug-level
        // logging is on.
        signpostsEnabled = environment["SWIFTOPENUI_SIGNPOSTS"] == "1" || threshold == .debug
        journal = environment["SWIFTOPENUI_LOG_JOURNAL"] == "0" ? nil : JournalConnection.open()
        writesStandardError = journal == nil || StandardError.isTerminal
        identifier = ProcessInfo.processInfo.processName
    }

    func write(level: OSLogType, subsystem: String, category: String, message: OSLogMessage,
               extraFields: [(String, String)], bypassThreshold: Bool = false) {
        guard bypassThreshold || level.rank >= threshold.rank else { return }
        let text = message.formatted(revealPrivate: revealPrivate)
        if let journal {
            var fields: [(String, String)] = [
                ("MESSAGE", text),
                ("PRIORITY", String(level.syslogPriority)),
                ("SYSLOG_IDENTIFIER", identifier),
            ]
            if !subsystem.isEmpty { fields.append(("OSLOG_SUBSYSTEM", subsystem)) }
            if !category.isEmpty { fields.append(("OSLOG_CATEGORY", category)) }
            fields += extraFields
            if journal.send(fields) {
                guard writesStandardError else { return }
            }
        }
        let scope = category.isEmpty ? subsystem : "\(subsystem)[\(category)]"
        let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(Date())
        let extras = extraFields.map { " \($0.0.lowercased())=\($0.1)" }.joined()
        StandardError.write("\(timestamp) \(scope) \(level.name): \(text)\(extras)\n")
    }
}
