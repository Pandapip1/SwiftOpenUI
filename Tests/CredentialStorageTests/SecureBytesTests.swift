import CredentialStorage
import Foundation
@testable import SecureMemory
import Synchronization
import XCTest

final class SecureBytesTests: XCTestCase {
    func testRoundTripsBytes() {
        let original: [UInt8] = Array(0...255)
        let secret = original.withUnsafeBytes { SecureBytes(copying: $0) }
        XCTAssertEqual(secret.count, original.count)
        XCTAssertEqual(secret.withUnsafeBytes { Array($0) }, original)
        // Nested and repeated access keep the memory readable.
        secret.withUnsafeBytes { outer in
            secret.withUnsafeBytes { inner in XCTAssertEqual(Array(inner), Array(outer)) }
        }
        XCTAssertEqual(secret.withUnsafeBytes { Array($0) }, original)
    }

    @available(macOS 15, iOS 18, tvOS 18, visionOS 2, *)
    func testRoundTripsThroughAVault() throws {
        let vault = MemoryVault()
        let credential = Credential(user: "alice", token: "s3cr3t-token")
        vault.save(try SecureBytes(jsonEncoding: credential), account: "a")
        let loaded = try XCTUnwrap(vault.load(account: "a"))
        XCTAssertEqual(try loaded.decodeJSON(Credential.self), credential)
        vault.save(nil, account: "a")
        XCTAssertNil(vault.load(account: "a"))
    }

    func testWipingInitializerZeroesTheSource() {
        var data = Data("hunter2".utf8)
        let secret = SecureBytes(wiping: &data)
        XCTAssertEqual(data, Data(count: 7))
        XCTAssertEqual(secret.unsafeUnprotectedString(), "hunter2")
    }

    func testEmptySecret() throws {
        let secret = SecureBytes(copyingUTF8: "")
        XCTAssertTrue(secret.isEmpty)
        XCTAssertEqual(secret, SecureBytes(count: 0) { _ in })
        XCTAssertEqual(secret.unsafeUnprotectedString(), "")
    }

    func testFailedInitializerReleasesMemory() {
        struct Failure: Error {}
        XCTAssertThrowsError(try SecureBytes(count: 16) { _ in throw Failure() })
    }

    func testEqualityComparesContents() {
        XCTAssertEqual(SecureBytes(copyingUTF8: "abc"), SecureBytes(copyingUTF8: "abc"))
        XCTAssertNotEqual(SecureBytes(copyingUTF8: "abc"), SecureBytes(copyingUTF8: "abd"))
        XCTAssertNotEqual(SecureBytes(copyingUTF8: "abc"), SecureBytes(copyingUTF8: "abcd"))
        XCTAssertEqual(Set([SecureBytes(copyingUTF8: "x"), SecureBytes(copyingUTF8: "x")]).count, 1)
    }

    func testReleaseWipesBeforeFreeing() {
        // SecureBytes.deinit is exactly `region.release()`; observe the bytes
        // at the last moment they are still mapped.
        let marker = Array("wipe-me-please".utf8)
        let region = ProtectedRegion.allocate(count: marker.count)
        region.makeWritable()
        marker.withUnsafeBytes { region.start.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        var observed: [UInt8]?
        region.release { observed = Array($0) }
        XCTAssertEqual(observed, [UInt8](repeating: 0, count: marker.count))
    }

    func testSecretDoesNotLeakThroughDescriptionsOrReflection() {
        let secret = SecureBytes(copyingUTF8: "top-secret-value")
        var dumped = ""
        dump(secret, to: &dumped)
        for text in ["\(secret)", String(describing: secret), String(reflecting: secret), dumped] {
            XCTAssertFalse(text.contains("top-secret-value"), text)
        }
        XCTAssertTrue(Mirror(reflecting: secret).children.isEmpty)
    }

    func testPublicAPIDoesNotExposeData() {
        let secret = SecureBytes(copyingUTF8: "value") as Any
        XCTAssertNil(secret as? Data)
        XCTAssertNil(secret as? String)
        XCTAssertNil(secret as? any Encodable)
        XCTAssertNil(secret as? any Collection)
        XCTAssertNil(secret as? any DataProtocol)
        // The vault API traffics only in SecureBytes; these fail to compile
        // if a Data-based signature returns.
        let load: (any CredentialDataVault, String) -> SecureBytes? = { $0.load(account: $1) }
        let save: (any CredentialDataVault, SecureBytes?, String) -> Void = { $0.save($1, account: $2) }
        _ = (load, save)
    }
}

private struct Credential: Codable, Equatable {
    let user: String
    let token: String
}

@available(macOS 15, iOS 18, tvOS 18, visionOS 2, *)
private final class MemoryVault: CredentialDataVault {
    private let secrets = Mutex<[String: SecureBytes]>([:])
    func load(account: String) -> SecureBytes? { secrets.withLock { $0[account] } }
    func save(_ secret: SecureBytes?, account: String) { secrets.withLock { $0[account] = secret } }
}
