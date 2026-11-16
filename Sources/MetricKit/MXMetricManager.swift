import Foundation
import Synchronization

/// Receives metric and diagnostic payloads, as on Apple platforms. Both
/// methods have default implementations, matching Apple's optional
/// requirements. Payloads arrive on a background thread.
public protocol MXMetricManagerSubscriber: AnyObject, Sendable {
    func didReceive(_ payloads: [MXMetricPayload])
    func didReceive(_ payloads: [MXDiagnosticPayload])
}

extension MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXMetricPayload]) {}
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {}
}

/// MetricKit's manager for platforms without MetricKit.
///
/// On Linux, diagnostics come from systemd-coredump: when the first subscriber
/// is added, crashes of this executable recorded since the last delivery
/// (`coredumpctl list`, with backtraces from `coredumpctl info`) are delivered
/// once as an `MXDiagnosticPayload` with `crashDiagnostics`. Apple's metrics
/// (launch time, energy, disk) have no Linux source, so no `MXMetricPayload`s
/// are delivered.
public final class MXMetricManager: Sendable {
    public static let shared = MXMetricManager(source: CoredumpSource.forCurrentExecutable())

    private struct State {
        var subscribers: [ObjectIdentifier: any MXMetricManagerSubscriber] = [:]
        var pastDiagnostics: [MXDiagnosticPayload] = []
        var collected = false
    }

    private let state = Mutex(State())
    private let source: CoredumpSource?

    init(source: CoredumpSource?) {
        self.source = source
    }

    /// Diagnostic payloads delivered to subscribers by this process.
    public var pastDiagnosticPayloads: [MXDiagnosticPayload] {
        state.withLock { $0.pastDiagnostics }
    }

    public var pastPayloads: [MXMetricPayload] { [] }

    public func add(_ subscriber: any MXMetricManagerSubscriber) {
        let collect = state.withLock { state in
            state.subscribers[ObjectIdentifier(subscriber)] = subscriber
            defer { state.collected = true }
            return !state.collected
        }
        guard collect, let source else { return }
        // Off the caller's thread: coredumpctl can take a while.
        Thread.detachNewThread { [self] in
            guard let payload = source.collectNewCrashes() else { return }
            deliver(payload)
        }
    }

    public func remove(_ subscriber: any MXMetricManagerSubscriber) {
        state.withLock { _ = $0.subscribers.removeValue(forKey: ObjectIdentifier(subscriber)) }
    }

    func deliver(_ payload: MXDiagnosticPayload) {
        let subscribers = state.withLock { state in
            state.pastDiagnostics.append(payload)
            return Array(state.subscribers.values)
        }
        for subscriber in subscribers {
            subscriber.didReceive([payload])
        }
    }

    /// Delivers a payload as if the system had, for testing subscriber code.
    /// The counterpart of Xcode's Debug > Simulate MetricKit Payloads.
    public func simulateDiagnosticPayload(hangDuration: TimeInterval = 2, crashSignal: Int32? = 11) {
        let metaData = MXMetaData.current(pid: ProcessInfo.processInfo.processIdentifier)
        let stack = MXCallStackTree(backtrace: "#0 simulated frame")
        let now = Date()
        deliver(MXDiagnosticPayload(
            timeStampBegin: now.addingTimeInterval(-60),
            timeStampEnd: now,
            crashDiagnostics: crashSignal.map {
                [MXCrashDiagnostic(metaData: metaData, callStackTree: stack, signal: $0, terminationReason: "simulated")]
            },
            hangDiagnostics: [MXHangDiagnostic(
                metaData: metaData, callStackTree: stack,
                hangDuration: Measurement(value: hangDuration, unit: .seconds)
            )]
        ))
    }
}
