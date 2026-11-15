import Foundation
import Security
@_exported import SecureMemory
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Stores secrets by account name. Secrets cross this API only as
/// `SecureBytes`, so they stay in protected memory on both sides of it.
public protocol CredentialDataVault: Sendable {
    func load(account: String) -> SecureBytes?
    /// `nil` deletes the entry.
    func save(_ secret: SecureBytes?, account: String)
}

public protocol UnlockableCredentialVault: CredentialDataVault {
    var credentialVaultID: String { get }
    func requiresExplicitUnlock() -> Bool
    func requestUnlock() throws
}

/// Coordinates the single explicit unlock ceremony for every credential vault
/// used by a process. Concurrent requests join the ceremony already underway.
public final class CredentialVaultManager: @unchecked Sendable {
    public static let shared = CredentialVaultManager()

    private struct Registration: Sendable {
        let isLocked: @Sendable () -> Bool
        let unlock: @Sendable () throws -> Void
    }

    private let condition = NSCondition()
    private var registrations: [String: Registration] = [:]
    private var unlockInProgress = false
    private var lastUnlockError: (any Error)?

    public init() {}

    public func register(_ vault: any UnlockableCredentialVault) {
        condition.withLock {
            registrations[vault.credentialVaultID] = Registration(
                isLocked: { vault.requiresExplicitUnlock() },
                unlock: { try vault.requestUnlock() }
            )
        }
    }

    public var requiresExplicitUnlock: Bool {
        let checks = condition.withLock { registrations.values.map(\.isLocked) }
        return checks.contains { $0() }
    }

    public func requestUnlock() throws {
        condition.lock()
        if unlockInProgress {
            repeat { condition.wait() } while unlockInProgress
            let error = lastUnlockError
            condition.unlock()
            if let error { throw error }
            return
        }
        unlockInProgress = true
        lastUnlockError = nil
        let vaults = Array(registrations.values)
        condition.unlock()

        let result: Result<Void, any Error>
        do {
            for vault in vaults where vault.isLocked() { try vault.unlock() }
            result = .success(())
        } catch {
            result = .failure(error)
        }

        condition.withLock {
            if case let .failure(error) = result { lastUnlockError = error }
            unlockInProgress = false
            condition.broadcast()
        }
        try result.get()
    }
}

public enum CredentialVaultAccess: Equatable, Sendable {
    case available
    case missing
    case locked
    case unavailable(Int32)
}

/// The platform credential adapter. Apple uses only the modern Data Protection
/// Keychain; Linux uses SwiftOpenUI's Security-compatible Secret Service layer.
public struct PlatformCredentialVault: CredentialDataVault {
    public let service: String
    public let accessGroup: String?

    public init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func access(to account: String) -> CredentialVaultAccess {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query(account: account, interactive: false) as CFDictionary, &item)
        switch status {
        case errSecSuccess: return .available
        case errSecItemNotFound: return .missing
        #if canImport(LocalAuthentication)
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecNotAvailable: return .locked
        #endif
        default: return .unavailable(status)
        }
    }

    public func requestAccess(to account: String) throws {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query(account: account, interactive: true) as CFDictionary, &item)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialVaultError(status: status)
        }
    }

    public func load(account: String) -> SecureBytes? {
        var item: CFTypeRef?
        guard SecItemCopyMatching(query(account: account, interactive: false) as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return Self.secureBytes(fromSecValue: item)
    }

    public func save(_ secret: SecureBytes?, account: String) {
        let identity = baseQuery(account: account)
        let status = SecItemCopyMatching(
            query(account: account, interactive: false, returnData: false) as CFDictionary, nil
        )
        if status == errSecSuccess {
            if let secret {
                _ = Self.withSecValue(secret) { value in
                    SecItemUpdate(identity as CFDictionary, [kSecValueData: value] as CFDictionary)
                }
            } else {
                SecItemDelete(identity as CFDictionary)
            }
            return
        }
        guard status == errSecItemNotFound, let secret else { return }
        Self.withSecValue(secret) { value in
            var addition = identity
            addition[kSecValueData] = value
            addition[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(addition as CFDictionary, nil)
        }
    }

    #if os(Linux)
    // SwiftOpenUI's Security stand-in takes and returns `SecureBytes` itself,
    // so the secret never leaves protected memory on this side of libsecret.
    private static func withSecValue<R>(_ secret: SecureBytes, _ body: (Any) -> R) -> R {
        body(secret)
    }

    private static func secureBytes(fromSecValue item: CFTypeRef?) -> SecureBytes? {
        item as? SecureBytes
    }
    #else
    /// Security.framework accepts secret values only as `CFData`. Protection
    /// ends at this boundary: the secret is copied into a fixed-capacity
    /// `CFMutableData` (so it is never reallocated) for the duration of the
    /// call, and that copy is wiped afterwards. What securityd does with the
    /// value is outside this process.
    private static func withSecValue<R>(_ secret: SecureBytes, _ body: (Any) -> R) -> R {
        guard let data = CFDataCreateMutable(kCFAllocatorDefault, secret.count) else {
            fatalError("CredentialStorage: could not allocate a keychain value buffer")
        }
        secret.withUnsafeBytes { bytes in
            CFDataAppendBytes(data, bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count)
        }
        defer {
            let length = CFDataGetLength(data)
            if length > 0 { _ = memset_s(CFDataGetMutableBytePtr(data), length, 0, length) }
        }
        return body(data)
    }

    /// Copies the keychain's returned `CFData` straight into protected
    /// memory without bridging through Swift `Data`. The `CFData` itself is
    /// owned by Security.framework, immutable, and released (unwiped) when
    /// `item` goes out of scope.
    private static func secureBytes(fromSecValue item: CFTypeRef?) -> SecureBytes? {
        guard let item, CFGetTypeID(item) == CFDataGetTypeID() else { return nil }
        let data = unsafeDowncast(item, to: CFData.self)
        let length = CFDataGetLength(data)
        guard length > 0, let bytes = CFDataGetBytePtr(data) else {
            return SecureBytes(count: 0) { _ in }
        }
        return SecureBytes(copying: UnsafeRawBufferPointer(start: bytes, count: length))
    }
    #endif

    private func baseQuery(account: String) -> [CFString: Any] {
        var result: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if let accessGroup { result[kSecAttrAccessGroup] = accessGroup }
        #if canImport(LocalAuthentication)
        result[kSecUseDataProtectionKeychain] = true
        #endif
        return result
    }

    private func query(account: String, interactive: Bool, returnData: Bool = true) -> [CFString: Any] {
        var result = baseQuery(account: account)
        if returnData { result[kSecReturnData] = true }
        result[kSecMatchLimit] = kSecMatchLimitOne
        #if canImport(LocalAuthentication) && !os(tvOS)
        let context = LAContext()
        context.interactionNotAllowed = !interactive
        result[kSecUseAuthenticationContext] = context
        #endif
        return result
    }
}

public struct CredentialVaultError: LocalizedError, Sendable {
    public let status: Int32

    public var errorDescription: String? {
        #if canImport(LocalAuthentication)
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown credential-store error"
        return "\(message) (\(status))"
        #else
        return "Credential storage failed with status \(status)."
        #endif
    }
}

private extension NSCondition {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
