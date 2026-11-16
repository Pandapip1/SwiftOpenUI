import Foundation

/// Reads crashes of one executable from systemd-coredump via `coredumpctl`.
struct CoredumpSource: Sendable {
    let executable: String
    let cursorFile: URL
    let coredumpctl: String

    /// At most this many crashes are delivered per launch, newest first.
    static let maximumCrashes = 5
    /// Backtraces are cut to this many bytes.
    static let maximumBacktraceBytes = 64 * 1024

    static func forCurrentExecutable() -> CoredumpSource? {
        #if os(Linux)
        guard let coredumpctl = ["/usr/bin/coredumpctl", "/bin/coredumpctl", "/run/current-system/sw/bin/coredumpctl"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let executable = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath().path
        let environment = ProcessInfo.processInfo.environment
        let stateHome = environment["XDG_STATE_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
        let cursorFile = stateHome
            .appendingPathComponent(ProcessInfo.processInfo.processName, isDirectory: true)
            .appendingPathComponent("metrickit-coredump-cursor")
        return CoredumpSource(executable: executable, cursorFile: cursorFile, coredumpctl: coredumpctl)
        #else
        return nil
        #endif
    }

    /// Crashes recorded since the last call (or in the last day, the first
    /// time), as one payload; nil when there are none.
    func collectNewCrashes(now: Date = Date()) -> MXDiagnosticPayload? {
        let since = readCursor() ?? now.addingTimeInterval(-86_400)
        guard let listing = runData(["--no-pager", "--json=short", "list", "--since=@\(Int(since.timeIntervalSince1970))", executable]),
              let entries = Self.parseList(listing) else { return nil }
        let fresh = entries.filter { $0.time > since }.sorted { $0.time > $1.time }
        guard let newest = fresh.first else { return nil }
        writeCursor(newest.time)
        let crashes = fresh.prefix(Self.maximumCrashes).map { entry in
            let info = runText(["--no-pager", "info", String(entry.pid)]) ?? ""
            return MXCrashDiagnostic(
                metaData: .current(pid: entry.pid),
                callStackTree: MXCallStackTree(backtrace: Self.backtrace(fromInfo: info)),
                signal: entry.signal,
                terminationReason: entry.signal.map { "Namespace SIGNAL, Code \($0)" }
            )
        }
        return MXDiagnosticPayload(
            timeStampBegin: fresh.last?.time ?? since,
            timeStampEnd: newest.time,
            crashDiagnostics: Array(crashes)
        )
    }

    struct Entry: Equatable {
        let time: Date
        let pid: Int32
        let signal: Int32?
    }

    /// Parses `coredumpctl --json=short list`: an array of objects with
    /// `time` (microseconds since the epoch), `pid` and `sig`.
    static func parseList(_ data: Data) -> [Entry]? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return array.compactMap { object in
            guard let time = (object["time"] as? NSNumber)?.doubleValue,
                  let pid = (object["pid"] as? NSNumber)?.int32Value else { return nil }
            return Entry(
                time: Date(timeIntervalSince1970: time / 1_000_000),
                pid: pid,
                signal: (object["sig"] as? NSNumber)?.int32Value
            )
        }
    }

    /// The "Stack trace of thread" sections of `coredumpctl info`, or the
    /// whole output when it has none (no debuginfo, or no backtrace taken).
    static func backtrace(fromInfo info: String) -> String {
        let marker = info.range(of: "Stack trace of thread")
        let text = marker.map { String(info[$0.lowerBound...]) } ?? info
        let bytes = Array(text.utf8)
        guard bytes.count > maximumBacktraceBytes else { return text }
        return String(decoding: bytes.prefix(maximumBacktraceBytes), as: UTF8.self) + "\n… [truncated]"
    }

    private func readCursor() -> Date? {
        guard let text = try? String(contentsOf: cursorFile, encoding: .utf8),
              let seconds = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func writeCursor(_ date: Date) {
        try? FileManager.default.createDirectory(at: cursorFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? String(date.timeIntervalSince1970).write(to: cursorFile, atomically: true, encoding: .utf8)
    }

    private func runData(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: coredumpctl)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private func runText(_ arguments: [String]) -> String? {
        runData(arguments).map { String(decoding: $0, as: UTF8.self) }
    }
}
