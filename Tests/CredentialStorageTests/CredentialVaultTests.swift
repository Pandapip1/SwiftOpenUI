import CredentialStorage
import Foundation
import XCTest

final class CredentialVaultTests: XCTestCase {
    func testConcurrentRequestsShareOneUnlockCeremony() {
        let manager = CredentialVaultManager()
        let vault = BlockingVault()
        manager.register(vault)

        let finished = expectation(description: "both callers finished")
        finished.expectedFulfillmentCount = 2
        for _ in 0..<2 {
            DispatchQueue.global().async {
                try? manager.requestUnlock()
                finished.fulfill()
            }
        }

        XCTAssertEqual(vault.started.wait(timeout: .now() + 1), .success)
        // Give the second caller time to join the in-flight ceremony.
        Thread.sleep(forTimeInterval: 0.05)
        vault.release.signal()
        wait(for: [finished], timeout: 2)
        XCTAssertEqual(vault.unlockCount, 1)
    }

    func testRegisteringSameSemanticVaultReplacesOldAdapter() throws {
        let manager = CredentialVaultManager()
        let old = CountingVault(id: "shared", locked: true)
        let replacement = CountingVault(id: "shared", locked: true)
        manager.register(old)
        manager.register(replacement)

        try manager.requestUnlock()

        XCTAssertEqual(old.unlockCount, 0)
        XCTAssertEqual(replacement.unlockCount, 1)
    }
}

private final class CountingVault: UnlockableCredentialVault, @unchecked Sendable {
    let credentialVaultID: String
    private let lock = NSLock()
    private var locked: Bool
    private var count = 0

    init(id: String, locked: Bool) {
        credentialVaultID = id
        self.locked = locked
    }

    var unlockCount: Int { lock.withLock { count } }
    func requiresExplicitUnlock() -> Bool { lock.withLock { locked } }
    func requestUnlock() { lock.withLock { count += 1; locked = false } }
    func load(account: String) -> Data? { nil }
    func save(_ data: Data?, account: String) {}
}

private final class BlockingVault: UnlockableCredentialVault, @unchecked Sendable {
    let credentialVaultID = "blocking"
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var locked = true
    private var count = 0

    var unlockCount: Int { lock.withLock { count } }
    func requiresExplicitUnlock() -> Bool { lock.withLock { locked } }
    func requestUnlock() {
        lock.withLock { count += 1 }
        started.signal()
        release.wait()
        lock.withLock { locked = false }
    }
    func load(account: String) -> Data? { nil }
    func save(_ data: Data?, account: String) {}
}
