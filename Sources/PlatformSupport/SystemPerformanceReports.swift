import Foundation
import Synchronization
#if canImport(MetricKit) && !os(tvOS)
import MetricKit
#endif

/// What a system diagnostic says, reduced to values that are safe to log in
/// public: kind, build number, signal, duration and size. Call stacks and
/// termination reasons stay in the payload's JSON.
public struct SystemPerformanceDiagnostic: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case crash, hang, cpuException, diskWriteException
    }

    public let kind: Kind
    public let applicationBuild: String
    /// Hang duration, or CPU time for a CPU exception, in milliseconds.
    public let milliseconds: Int?
    /// Bytes written, for a disk-write exception.
    public let bytes: Int?
    /// The signal, for a crash.
    public let signal: Int?

    public init(kind: Kind, applicationBuild: String, milliseconds: Int? = nil, bytes: Int? = nil, signal: Int? = nil) {
        self.kind = kind
        self.applicationBuild = applicationBuild
        self.milliseconds = milliseconds
        self.bytes = bytes
        self.signal = signal
    }
}

/// A report the system delivered about the application's performance.
public enum SystemPerformancePayload: Sendable {
    /// Crashes, hangs and resource exceptions, with the payload's JSON.
    case diagnostics([SystemPerformanceDiagnostic], json: Data, begin: Date, end: Date)
    /// Aggregated metrics (typically daily), with the payload's JSON.
    case metrics(latestApplicationVersion: String, includesMultipleApplicationVersions: Bool,
                 json: Data, begin: Date, end: Date)
}

/// The system's performance reports: MetricKit on Apple platforms that have
/// it, and SwiftOpenUI's MetricKit on Linux, which delivers crashes recorded
/// by systemd-coredump. tvOS has none.
public enum SystemPerformanceReports {
    /// Whether the system delivers reports here.
    public static var isAvailable: Bool {
        #if canImport(MetricKit) && !os(tvOS)
        true
        #else
        false
        #endif
    }

    #if canImport(MetricKit) && !os(tvOS)
    /// Kept for the life of the process.
    private static let subscribers = Mutex<[Subscriber]>([])
    #endif

    /// Delivers the system's reports to `receiver`, on the system's delivery
    /// thread. Reports arrive later, typically on the next launch (crashes)
    /// or at most once a day (metrics); in Xcode use Debug > Simulate
    /// MetricKit Payloads. Does nothing where `isAvailable` is false.
    public static func subscribe(_ receiver: @escaping @Sendable (SystemPerformancePayload) -> Void) {
        #if canImport(MetricKit) && !os(tvOS)
        let subscriber = Subscriber(receiver: receiver)
        subscribers.withLock { $0.append(subscriber) }
        MXMetricManager.shared.add(subscriber)
        #endif
    }
}

#if canImport(MetricKit) && !os(tvOS)
private final class Subscriber: NSObject, MXMetricManagerSubscriber, Sendable {
    private let receiver: @Sendable (SystemPerformancePayload) -> Void

    init(receiver: @escaping @Sendable (SystemPerformancePayload) -> Void) {
        self.receiver = receiver
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            receiver(.diagnostics(
                Self.diagnostics(in: payload), json: payload.jsonRepresentation(),
                begin: payload.timeStampBegin, end: payload.timeStampEnd
            ))
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            receiver(.metrics(
                latestApplicationVersion: payload.latestApplicationVersion,
                includesMultipleApplicationVersions: payload.includesMultipleApplicationVersions,
                json: payload.jsonRepresentation(),
                begin: payload.timeStampBegin, end: payload.timeStampEnd
            ))
        }
    }

    private static func diagnostics(in payload: MXDiagnosticPayload) -> [SystemPerformanceDiagnostic] {
        var result: [SystemPerformanceDiagnostic] = []
        for crash in payload.crashDiagnostics ?? [] {
            result.append(SystemPerformanceDiagnostic(
                kind: .crash, applicationBuild: crash.metaData.applicationBuildVersion,
                signal: crash.signal?.intValue
            ))
        }
        for hang in payload.hangDiagnostics ?? [] {
            result.append(SystemPerformanceDiagnostic(
                kind: .hang, applicationBuild: hang.metaData.applicationBuildVersion,
                milliseconds: Int(hang.hangDuration.converted(to: .milliseconds).value)
            ))
        }
        for exception in payload.cpuExceptionDiagnostics ?? [] {
            result.append(SystemPerformanceDiagnostic(
                kind: .cpuException, applicationBuild: exception.metaData.applicationBuildVersion,
                milliseconds: Int(exception.totalCPUTime.converted(to: .milliseconds).value)
            ))
        }
        for exception in payload.diskWriteExceptionDiagnostics ?? [] {
            result.append(SystemPerformanceDiagnostic(
                kind: .diskWriteException, applicationBuild: exception.metaData.applicationBuildVersion,
                bytes: Int(exception.totalWritesCaused.converted(to: .bytes).value)
            ))
        }
        return result
    }
}
#endif
