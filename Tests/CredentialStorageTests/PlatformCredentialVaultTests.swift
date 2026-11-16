import CredentialStorage
import Foundation
#if os(Linux)
import Security
#endif
import Synchronization
import XCTest

final class PlatformCredentialVaultTests: XCTestCase {
    func testDataProtectionModeTargetsTheDataProtectionKeychainAndAccessGroup() throws {
        let keychain = FakeKeychain()
        let vault = PlatformCredentialVault(service: "svc", accessGroup: "group", backend: keychain)

        try vault.save(SecureBytes(copyingUTF8: "secret"), account: "a")

        let call = try XCTUnwrap(keychain.calls.first)
        XCTAssertEqual(call.operation, .add)
        XCTAssertEqual(call.accessGroup, "group")
        #if !os(Linux)
        XCTAssertTrue(call.dataProtection)
        #endif
        XCTAssertEqual(try vault.load(account: "a")?.unsafeUnprotectedString(), "secret")
    }

    #if os(macOS)
    func testLegacyModeOmitsDataProtectionAndAccessGroup() throws {
        let keychain = FakeKeychain()
        let vault = PlatformCredentialVault(
            service: "svc", accessGroup: "group", mode: .legacyLoginKeychain, backend: keychain
        )

        try vault.save(SecureBytes(copyingUTF8: "secret"), account: "a")
        XCTAssertEqual(try vault.load(account: "a")?.unsafeUnprotectedString(), "secret")
        try vault.delete(account: "a")

        XCTAssertFalse(keychain.calls.isEmpty)
        for call in keychain.calls {
            XCTAssertFalse(call.dataProtection, "\(call.operation) used the Data Protection Keychain")
            XCTAssertNil(call.accessGroup, "\(call.operation) carried an access group")
            XCTAssertFalse(call.accessibility, "\(call.operation) set a Data Protection accessibility class")
        }
    }

    func testMissingEntitlementIsReportedAndNeverFallsBackToTheLoginKeychain() {
        let keychain = FakeKeychain(dataProtectionStatus: CredentialVaultError.missingEntitlementStatus)
        let vault = PlatformCredentialVault(service: "svc", accessGroup: "group", backend: keychain)

        XCTAssertThrowsError(try vault.save(SecureBytes(copyingUTF8: "secret"), account: "a")) { error in
            XCTAssertEqual(error as? CredentialVaultError, CredentialVaultError(status: -34018))
            XCTAssertTrue((error as? CredentialVaultError)?.isMissingEntitlement == true)
        }
        XCTAssertThrowsError(try vault.delete(account: "a")) { error in
            XCTAssertTrue((error as? CredentialVaultError)?.isMissingEntitlement == true)
        }
        XCTAssertTrue(keychain.calls.allSatisfy(\.dataProtection))
        XCTAssertEqual(keychain.storedAccounts(dataProtection: false), [])
    }

    func testMissingEntitlementStatusMatchesSecurityFramework() {
        XCTAssertEqual(CredentialVaultError.missingEntitlementStatus, errSecMissingEntitlement)
        XCTAssertEqual(CredentialVaultError.interactionNotAllowedStatus, errSecInteractionNotAllowed)
        XCTAssertEqual(CredentialVaultError.authFailedStatus, errSecAuthFailed)
        XCTAssertEqual(CredentialVaultError.notAvailableStatus, errSecNotAvailable)
        XCTAssertEqual(CredentialVaultError.decodeStatus, errSecDecode)
    }
    #endif

    func testProbeReportsUnavailableDataProtectionKeychainBeforeAnySecretIsWritten() {
        let keychain = FakeKeychain(dataProtectionStatus: CredentialVaultError.missingEntitlementStatus)
        let vault = PlatformCredentialVault(service: "svc", backend: keychain)

        XCTAssertEqual(
            vault.probeAvailability(),
            .dataProtectionKeychainUnavailable(CredentialVaultError(status: -34018))
        )
        XCTAssertEqual(keychain.calls.map(\.operation), [.add])
    }

    func testSuccessfulProbeLeavesNoMarkerBehind() throws {
        let keychain = FakeKeychain()
        let vault = PlatformCredentialVault(service: "svc", backend: keychain)

        XCTAssertEqual(vault.probeAvailability(), .available)
        XCTAssertEqual(keychain.calls.map(\.operation), [.add, .delete])
        XCTAssertEqual(keychain.storedAccounts(dataProtection: true), [])
    }

    func testProbeReportsLockedStore() {
        let keychain = FakeKeychain(dataProtectionStatus: CredentialVaultError.interactionNotAllowedStatus)
        XCTAssertEqual(PlatformCredentialVault(service: "svc", backend: keychain).probeAvailability(), .locked)
    }

    func testProbeReportsOtherFailures() {
        let keychain = FakeKeychain(dataProtectionStatus: -25295)
        XCTAssertEqual(
            PlatformCredentialVault(service: "svc", backend: keychain).probeAvailability(),
            .failed(CredentialVaultError(status: -25295))
        )
    }

    func testLoadDistinguishesAnAbsentItemFromAFailure() throws {
        XCTAssertNil(try PlatformCredentialVault(service: "svc", backend: FakeKeychain()).load(account: "a"))

        let failing = FakeKeychain(dataProtectionStatus: -25295)
        XCTAssertThrowsError(try PlatformCredentialVault(service: "svc", backend: failing).load(account: "a")) {
            XCTAssertEqual($0 as? CredentialVaultError, CredentialVaultError(status: -25295))
        }
    }

    func testSaveReplacesAnExistingItem() throws {
        let keychain = FakeKeychain()
        let vault = PlatformCredentialVault(service: "svc", backend: keychain)

        try vault.save(SecureBytes(copyingUTF8: "first"), account: "a")
        try vault.save(SecureBytes(copyingUTF8: "second"), account: "a")

        XCTAssertEqual(try vault.load(account: "a")?.unsafeUnprotectedString(), "second")
        XCTAssertEqual(keychain.calls.map(\.operation), [.add, .add, .update, .copy])
    }

    func testDeletingAnAbsentItemSucceeds() throws {
        try PlatformCredentialVault(service: "svc", backend: FakeKeychain()).delete(account: "missing")
    }

    #if !os(Linux)
    func testAccountsListsOnlyThisServicesItems() throws {
        let keychain = FakeKeychain()
        let vault = PlatformCredentialVault(service: "svc", backend: keychain)
        try vault.save(SecureBytes(copyingUTF8: "1"), account: "b")
        try vault.save(SecureBytes(copyingUTF8: "2"), account: "a")
        try PlatformCredentialVault(service: "other", backend: keychain)
            .save(SecureBytes(copyingUTF8: "3"), account: "c")

        XCTAssertEqual(try vault.accounts(), ["a", "b"])
    }
    #endif

    // MARK: Real keychain

    #if os(macOS)
    /// `swift test` binaries are not team-signed, so this exercises the real
    /// Security.framework path an ad-hoc signed Hummingbird.app takes.
    func testUnsignedProcessCannotUseTheRealDataProtectionKeychain() throws {
        let vault = PlatformCredentialVault(service: "org.swiftopenui.credential-storage.tests")
        let availability = vault.probeAvailability()
        if availability == .available {
            throw XCTSkip("This test process is entitled to the Data Protection Keychain.")
        }
        XCTAssertEqual(availability, .dataProtectionKeychainUnavailable(CredentialVaultError(status: -34018)))
        // Reads alone cannot detect this: an unentitled lookup reports an
        // empty store, which is why callers must probe before writing.
        XCTAssertNil(try vault.load(account: "absent"))
        XCTAssertThrowsError(try vault.save(SecureBytes(copyingUTF8: "secret"), account: "absent")) {
            XCTAssertTrue(($0 as? CredentialVaultError)?.isMissingEntitlement == true)
        }
    }

    /// Writes to the user's real login keychain, so it runs only on request:
    /// `CREDENTIAL_STORAGE_LOGIN_KEYCHAIN_TESTS=1 swift test`.
    func testRealLoginKeychainRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["CREDENTIAL_STORAGE_LOGIN_KEYCHAIN_TESTS"] == "1" else {
            throw XCTSkip("Set CREDENTIAL_STORAGE_LOGIN_KEYCHAIN_TESTS=1 to touch the login keychain.")
        }
        let service = "org.swiftopenui.credential-storage.tests.\(UUID().uuidString.lowercased())"
        let vault = PlatformCredentialVault(service: service, mode: .legacyLoginKeychain)
        XCTAssertEqual(vault.probeAvailability(), .available)
        try vault.save(SecureBytes(copyingUTF8: "first"), account: "a")
        try vault.save(SecureBytes(copyingUTF8: "second"), account: "a")
        XCTAssertEqual(try vault.load(account: "a")?.unsafeUnprotectedString(), "second")
        XCTAssertEqual(try vault.accounts(), ["a"])
        try vault.delete(account: "a")
        XCTAssertNil(try vault.load(account: "a"))
        XCTAssertEqual(try vault.accounts(), [])
    }
    #endif
}

/// An in-memory stand-in for the Security item calls. Items in the Data
/// Protection Keychain and the file-based keychain are kept apart, as they
/// are on macOS. `dataProtectionStatus` makes every Data Protection write and
/// delete fail with that status. Lookups then report either that status or,
/// for `errSecMissingEntitlement`, `errSecItemNotFound`, matching what an
/// unentitled process observes from the real keychain.
final class FakeKeychain: KeychainItemBackend {
    enum Operation: Equatable, Sendable { case add, update, copy, delete }

    struct Call: Sendable {
        let operation: Operation
        let dataProtection: Bool
        let accessGroup: String?
        let accessibility: Bool
    }

    #if os(Linux)
    typealias Value = SecureBytes
    #else
    typealias Value = Data
    #endif

    private struct Key: Hashable {
        let dataProtection: Bool
        let accessGroup: String?
        let service: String
        let account: String
    }

    private struct State {
        var items: [Key: Value] = [:]
        var calls: [Call] = []
    }

    private let state = Mutex(State())
    private let dataProtectionStatus: OSStatus?

    init(dataProtectionStatus: OSStatus? = nil) {
        self.dataProtectionStatus = dataProtectionStatus
    }

    var calls: [Call] { state.withLock { $0.calls } }

    func storedAccounts(dataProtection: Bool) -> [String] {
        state.withLock { state in
            state.items.keys.filter { $0.dataProtection == dataProtection }.map(\.account).sorted()
        }
    }

    func copyMatching(_ query: [CFString: Any]) -> (status: OSStatus, item: CFTypeRef?) {
        let dataProtection = record(.copy, query)
        if dataProtection, let dataProtectionStatus {
            return (dataProtectionStatus == CredentialVaultError.missingEntitlementStatus
                ? errSecItemNotFound : dataProtectionStatus, nil)
        }
        return state.withLock { state in
            #if !os(Linux)
            if query[kSecMatchLimit] as? String == kSecMatchLimitAll as String {
                let rows: [[String: Any]] = state.items.keys
                    .filter { matches($0, query, dataProtection: dataProtection, requireAccount: false) }
                    .map { [kSecAttrAccount as String: $0.account] }
                return rows.isEmpty ? (errSecItemNotFound, nil) : (errSecSuccess, rows as NSArray)
            }
            #endif
            guard let key = Self.key(query, dataProtection: dataProtection), let value = state.items[key] else {
                return (errSecItemNotFound, nil)
            }
            return (errSecSuccess, Self.secValue(value))
        }
    }

    func add(_ attributes: [CFString: Any]) -> OSStatus {
        let dataProtection = record(.add, attributes)
        if dataProtection, let dataProtectionStatus { return dataProtectionStatus }
        guard let key = Self.key(attributes, dataProtection: dataProtection),
              let value = Self.value(attributes[kSecValueData]) else { return errSecParam }
        return state.withLock { state in
            guard state.items[key] == nil else { return errSecDuplicateItem }
            state.items[key] = value
            return errSecSuccess
        }
    }

    func update(_ query: [CFString: Any], attributes: [CFString: Any]) -> OSStatus {
        let dataProtection = record(.update, query)
        if dataProtection, let dataProtectionStatus { return dataProtectionStatus }
        guard let key = Self.key(query, dataProtection: dataProtection),
              let value = Self.value(attributes[kSecValueData]) else { return errSecParam }
        return state.withLock { state in
            guard state.items[key] != nil else { return errSecItemNotFound }
            state.items[key] = value
            return errSecSuccess
        }
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        let dataProtection = record(.delete, query)
        if dataProtection, let dataProtectionStatus { return dataProtectionStatus }
        guard let key = Self.key(query, dataProtection: dataProtection) else { return errSecParam }
        return state.withLock { $0.items.removeValue(forKey: key) == nil ? errSecItemNotFound : errSecSuccess }
    }

    private func record(_ operation: Operation, _ query: [CFString: Any]) -> Bool {
        let dataProtection = query[kSecUseDataProtectionKeychain] as? Bool == true
        state.withLock {
            $0.calls.append(Call(
                operation: operation, dataProtection: dataProtection,
                accessGroup: query[kSecAttrAccessGroup] as? String,
                accessibility: query[kSecAttrAccessible] != nil
            ))
        }
        return dataProtection
    }

    private func matches(_ key: Key, _ query: [CFString: Any], dataProtection: Bool, requireAccount: Bool) -> Bool {
        key.dataProtection == dataProtection
            && key.service == query[kSecAttrService] as? String
            && key.accessGroup == query[kSecAttrAccessGroup] as? String
            && (!requireAccount || key.account == query[kSecAttrAccount] as? String)
    }

    private static func key(_ query: [CFString: Any], dataProtection: Bool) -> Key? {
        guard let service = query[kSecAttrService] as? String,
              let account = query[kSecAttrAccount] as? String else { return nil }
        return Key(dataProtection: dataProtection, accessGroup: query[kSecAttrAccessGroup] as? String,
                   service: service, account: account)
    }

    #if os(Linux)
    private static func value(_ any: Any?) -> Value? { any as? SecureBytes }
    private static func secValue(_ value: Value) -> CFTypeRef { value }
    #else
    // The vault wipes its CFData buffer after each call, so copy the bytes now.
    private static func value(_ any: Any?) -> Value? { (any as? Data).map { Data(Array($0)) } }
    private static func secValue(_ value: Value) -> CFTypeRef { value as NSData }
    #endif
}
