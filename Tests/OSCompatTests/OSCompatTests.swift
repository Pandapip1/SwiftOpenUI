import Foundation
import Synchronization
import Testing
@testable import MetricKit
@testable import os

@Suite struct OSLogMessageTests {
    @Test func redactsDynamicStringsByDefaultAndKeepsScalars() {
        let user = "alice"
        let count = 3
        let message: OSLogMessage = "user=\(user) count=\(count) ok=\(true)"
        #expect(message.formatted(revealPrivate: false) == "user=<private> count=3 ok=true")
        #expect(message.formatted(revealPrivate: true) == "user=alice count=3 ok=true")
    }

    @Test func honoursExplicitPrivacy() {
        let host = "example.com"
        let token = "secret"
        let message: OSLogMessage = "\(host, privacy: .public) \(token, privacy: .sensitive) \(host, privacy: .private(mask: .hash))"
        let redacted = message.formatted(revealPrivate: false)
        #expect(redacted.hasPrefix("example.com <private> <mask.hash: '"))
        // Sensitive values stay hidden even with private data revealed.
        #expect(message.formatted(revealPrivate: true) == "example.com <private> example.com")
    }

    @Test func hashMasksAreStable() {
        #expect(OSLogMessage.stableHash("abc") == OSLogMessage.stableHash("abc"))
        #expect(OSLogMessage.stableHash("abc") != OSLogMessage.stableHash("abd"))
    }

    @Test func formatsNumbers() {
        let value = 255
        let ratio = 0.5
        let message: OSLogMessage = "\(value, format: .hex) \(ratio, format: .fixed(precision: 2))"
        #expect(message.formatted(revealPrivate: false) == "ff 0.50")
    }
}

@Suite struct JournalEncodingTests {
    @Test func encodesSimpleAndMultilineFields() {
        let datagram = JournalConnection.encode([("MESSAGE", "one\ntwo"), ("priority", "6")])
        var expected = Array("MESSAGE\n".utf8)
        var length = UInt64(7).littleEndian
        withUnsafeBytes(of: &length) { expected += $0 }
        expected += Array("one\ntwo\nPRIORITY=6\n".utf8)
        #expect(datagram == expected)
    }

    @Test func sanitizesFieldNames() {
        #expect(JournalConnection.sanitizedFieldName("_signpost-name") == "SIGNPOST_NAME")
    }
}

@Suite struct SignposterTests {
    @Test func intervalsAndEventsDoNotTrap() {
        let signposter = OSSignposter(subsystem: "org.swiftopenui.tests", category: "signposts")
        let id = signposter.makeSignpostID()
        #expect(id != signposter.makeSignpostID())
        let state = signposter.beginInterval("work", id: id, "\(1)")
        signposter.emitEvent("tick")
        signposter.endInterval("work", state)
        #expect(signposter.withIntervalSignpost("sync") { 7 } == 7)
    }
}

@Suite struct CoredumpTests {
    @Test func parsesCoredumpctlJSON() throws {
        let json = #"[{"time":1700000000000000,"pid":42,"uid":1000,"gid":1000,"sig":11,"corefile":"present","exe":"/app","size":1}]"#
        let entries = try #require(CoredumpSource.parseList(Data(json.utf8)))
        #expect(entries == [CoredumpSource.Entry(time: Date(timeIntervalSince1970: 1_700_000_000), pid: 42, signal: 11)])
    }

    @Test func extractsStackTraces() {
        let info = "PID: 42\nSignal: 11 (SEGV)\n\nStack trace of thread 42:\n#0 0x1 main (app)\n"
        #expect(CoredumpSource.backtrace(fromInfo: info) == "Stack trace of thread 42:\n#0 0x1 main (app)\n")
    }

    @Test func deliversSimulatedPayloadsToSubscribers() {
        final class Recorder: MXMetricManagerSubscriber {
            let received = Mutex<[MXDiagnosticPayload]>([])
            func didReceive(_ payloads: [MXDiagnosticPayload]) { received.withLock { $0 += payloads } }
        }
        let manager = MXMetricManager(source: nil)
        let recorder = Recorder()
        manager.add(recorder)
        manager.simulateDiagnosticPayload(hangDuration: 3, crashSignal: 6)
        let payloads = recorder.received.withLock { $0 }
        #expect(payloads.count == 1)
        #expect(payloads.first?.hangDiagnostics?.first?.hangDuration.value == 3)
        #expect(payloads.first?.crashDiagnostics?.first?.signal?.int32Value == 6)
        #expect(manager.pastDiagnosticPayloads.count == 1)
    }
}
