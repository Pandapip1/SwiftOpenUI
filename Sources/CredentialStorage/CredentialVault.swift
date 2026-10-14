import Foundation
import Security
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

public protocol CredentialDataVault: Sendable {
    func load(account: String) -> Data?
    func save(_ data: Data?, account: String)
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

    public func load(account: String) -> Data? {
        var item: CFTypeRef?
        guard SecItemCopyMatching(query(account: account, interactive: false) as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    public func save(_ data: Data?, account: String) {
        let identity = baseQuery(account: account)
        let status = SecItemCopyMatching(query(account: account, interactive: false) as CFDictionary, nil)
        if status == errSecSuccess {
            if let data {
                SecItemUpdate(identity as CFDictionary, [kSecValueData: data] as CFDictionary)
            } else {
                SecItemDelete(identity as CFDictionary)
            }
            return
        }
        guard status == errSecItemNotFound, let data else { return }
        var addition = identity
        addition[kSecValueData] = data
        addition[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(addition as CFDictionary, nil)
    }

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

    private func query(account: String, interactive: Bool) -> [CFString: Any] {
        var result = baseQuery(account: account)
        result[kSecReturnData] = true
        result[kSecMatchLimit] = kSecMatchLimitOne
        #if canImport(LocalAuthentication)
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
