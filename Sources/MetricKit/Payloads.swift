import Foundation

/// Facts about the process a diagnostic or metric describes.
public final class MXMetaData: Sendable {
    public let applicationBuildVersion: String
    public let osVersion: String
    public let platformArchitecture: String
    public let pid: Int32?

    init(applicationBuildVersion: String, osVersion: String, platformArchitecture: String, pid: Int32?) {
        self.applicationBuildVersion = applicationBuildVersion
        self.osVersion = osVersion
        self.platformArchitecture = platformArchitecture
        self.pid = pid
    }

    static func current(pid: Int32? = nil) -> MXMetaData {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? ProcessInfo.processInfo.environment["SWIFTOPENUI_APP_VERSION"]
            ?? "unknown"
        #if arch(x86_64)
        let architecture = "x86_64"
        #elseif arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "unknown"
        #endif
        return MXMetaData(
            applicationBuildVersion: build,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            platformArchitecture: architecture,
            pid: pid
        )
    }

    public func dictionaryRepresentation() -> [String: Any] {
        var result: [String: Any] = [
            "appBuildVersion": applicationBuildVersion,
            "osVersion": osVersion,
            "platformArchitecture": platformArchitecture,
        ]
        if let pid { result["pid"] = Int(pid) }
        return result
    }

    public func jsonRepresentation() -> Data { MetricJSON.encode(dictionaryRepresentation()) }
}

/// A call stack tree. On Linux it carries the textual backtrace that
/// systemd-coredump recorded, under
/// `callStacks[].callStackRootFrames[].symbolicatedText`.
public final class MXCallStackTree: Sendable {
    let backtrace: String

    init(backtrace: String) { self.backtrace = backtrace }

    public func dictionaryRepresentation() -> [String: Any] {
        [
            "callStackPerThread": true,
            "callStacks": [["threadAttributed": true, "callStackRootFrames": [["symbolicatedText": backtrace]]]],
        ]
    }

    public func jsonRepresentation() -> Data { MetricJSON.encode(dictionaryRepresentation()) }
}

/// A crash, from a systemd-coredump record of the application's executable.
public final class MXCrashDiagnostic: Sendable {
    public let metaData: MXMetaData
    public let applicationVersion: String
    public let callStackTree: MXCallStackTree
    public let signal: NSNumber?
    public let exceptionType: NSNumber?
    public let exceptionCode: NSNumber?
    public let terminationReason: String?
    public let virtualMemoryRegionInfo: String?

    init(metaData: MXMetaData, callStackTree: MXCallStackTree, signal: Int32?, terminationReason: String?) {
        self.metaData = metaData
        applicationVersion = metaData.applicationBuildVersion
        self.callStackTree = callStackTree
        self.signal = signal.map { NSNumber(value: $0) }
        exceptionType = nil
        exceptionCode = nil
        self.terminationReason = terminationReason
        virtualMemoryRegionInfo = nil
    }

    public func dictionaryRepresentation() -> [String: Any] {
        var diagnosticMetaData = metaData.dictionaryRepresentation()
        if let signal { diagnosticMetaData["signal"] = signal.intValue }
        if let terminationReason { diagnosticMetaData["terminationReason"] = terminationReason }
        return [
            "version": "1.0.0",
            "diagnosticMetaData": diagnosticMetaData,
            "callStackTree": callStackTree.dictionaryRepresentation(),
        ]
    }

    public func jsonRepresentation() -> Data { MetricJSON.encode(dictionaryRepresentation()) }
}

/// A period in which the main thread did not respond. Nothing on Linux
/// produces these yet; the type exists so subscriber code is shared.
public final class MXHangDiagnostic: Sendable {
    public let metaData: MXMetaData
    public let applicationVersion: String
    public let callStackTree: MXCallStackTree
    public let hangDuration: Measurement<UnitDuration>

    init(metaData: MXMetaData, callStackTree: MXCallStackTree, hangDuration: Measurement<UnitDuration>) {
        self.metaData = metaData
        applicationVersion = metaData.applicationBuildVersion
        self.callStackTree = callStackTree
        self.hangDuration = hangDuration
    }

    public func dictionaryRepresentation() -> [String: Any] {
        var diagnosticMetaData = metaData.dictionaryRepresentation()
        diagnosticMetaData["hangDuration"] = "\(hangDuration.converted(to: .seconds).value) sec"
        return [
            "version": "1.0.0",
            "diagnosticMetaData": diagnosticMetaData,
            "callStackTree": callStackTree.dictionaryRepresentation(),
        ]
    }

    public func jsonRepresentation() -> Data { MetricJSON.encode(dictionaryRepresentation()) }
}

/// Excessive CPU use. Nothing on Linux produces these yet.
public final class MXCPUExceptionDiagnostic: Sendable {
    public let metaData: MXMetaData
    public let applicationVersion: String
    public let callStackTree: MXCallStackTree
    public let totalCPUTime: Measurement<UnitDuration>
    public let totalSampledTime: Measurement<UnitDuration>

    init(metaData: MXMetaData, callStackTree: MXCallStackTree,
         totalCPUTime: Measurement<UnitDuration>, totalSampledTime: Measurement<UnitDuration>) {
        self.metaData = metaData
        applicationVersion = metaData.applicationBuildVersion
        self.callStackTree = callStackTree
        self.totalCPUTime = totalCPUTime
        self.totalSampledTime = totalSampledTime
    }

    public func jsonRepresentation() -> Data {
        MetricJSON.encode(["version": "1.0.0", "diagnosticMetaData": metaData.dictionaryRepresentation()])
    }
}

/// Excessive disk writes. Nothing on Linux produces these yet.
public final class MXDiskWriteExceptionDiagnostic: Sendable {
    public let metaData: MXMetaData
    public let applicationVersion: String
    public let callStackTree: MXCallStackTree
    public let totalWritesCaused: Measurement<UnitInformationStorage>

    init(metaData: MXMetaData, callStackTree: MXCallStackTree, totalWritesCaused: Measurement<UnitInformationStorage>) {
        self.metaData = metaData
        applicationVersion = metaData.applicationBuildVersion
        self.callStackTree = callStackTree
        self.totalWritesCaused = totalWritesCaused
    }

    public func jsonRepresentation() -> Data {
        MetricJSON.encode(["version": "1.0.0", "diagnosticMetaData": metaData.dictionaryRepresentation()])
    }
}

/// Diagnostics covering one period, as delivered to subscribers.
public final class MXDiagnosticPayload: Sendable {
    public let timeStampBegin: Date
    public let timeStampEnd: Date
    public let crashDiagnostics: [MXCrashDiagnostic]?
    public let hangDiagnostics: [MXHangDiagnostic]?
    public let cpuExceptionDiagnostics: [MXCPUExceptionDiagnostic]?
    public let diskWriteExceptionDiagnostics: [MXDiskWriteExceptionDiagnostic]?

    init(timeStampBegin: Date, timeStampEnd: Date, crashDiagnostics: [MXCrashDiagnostic]? = nil,
         hangDiagnostics: [MXHangDiagnostic]? = nil) {
        self.timeStampBegin = timeStampBegin
        self.timeStampEnd = timeStampEnd
        self.crashDiagnostics = crashDiagnostics
        self.hangDiagnostics = hangDiagnostics
        cpuExceptionDiagnostics = nil
        diskWriteExceptionDiagnostics = nil
    }

    public func dictionaryRepresentation() -> [String: Any] {
        var result: [String: Any] = [
            "timeStampBegin": MetricJSON.timestamp(timeStampBegin),
            "timeStampEnd": MetricJSON.timestamp(timeStampEnd),
        ]
        if let crashDiagnostics { result["crashDiagnostics"] = crashDiagnostics.map { $0.dictionaryRepresentation() } }
        if let hangDiagnostics { result["hangDiagnostics"] = hangDiagnostics.map { $0.dictionaryRepresentation() } }
        return result
    }

    public func jsonRepresentation() -> Data { MetricJSON.encode(dictionaryRepresentation()) }
}

/// Daily metrics. Linux has no equivalent source, so none are delivered; the
/// type exists so subscriber code is shared.
public final class MXMetricPayload: Sendable {
    public let timeStampBegin: Date
    public let timeStampEnd: Date
    public let latestApplicationVersion: String
    public let includesMultipleApplicationVersions: Bool

    init(timeStampBegin: Date, timeStampEnd: Date, latestApplicationVersion: String) {
        self.timeStampBegin = timeStampBegin
        self.timeStampEnd = timeStampEnd
        self.latestApplicationVersion = latestApplicationVersion
        includesMultipleApplicationVersions = false
    }

    public func dictionaryRepresentation() -> [String: Any] {
        [
            "timeStampBegin": MetricJSON.timestamp(timeStampBegin),
            "timeStampEnd": MetricJSON.timestamp(timeStampEnd),
            "latestApplicationVersion": latestApplicationVersion,
        ]
    }

    public func jsonRepresentation() -> Data { MetricJSON.encode(dictionaryRepresentation()) }
}

enum MetricJSON {
    static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }

    static func timestamp(_ date: Date) -> String {
        Date.ISO8601FormatStyle().format(date)
    }
}
