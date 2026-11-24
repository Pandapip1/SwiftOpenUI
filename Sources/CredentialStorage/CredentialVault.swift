import Foundation
import Security
@_exported import SecureMemory
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Stores secrets by account name. Secrets cross this API only as
/// `SecureBytes`, so they stay in protected memory on both sides of it.
///
/// Every operation reports failure. A vault never drops a write silently:
/// callers can tell an absent item (`load` returns `nil`) from a store that
/// refused the operation (a thrown error, usually `CredentialVaultError`).
public protocol CredentialDataVault: Sendable {
    /// Returns `nil` only when no item exists for `account`.
    func load(account: String) throws -> SecureBytes?
    func save(_ secret: SecureBytes, account: String) throws
    /// Deleting an item that does not exist succeeds.
    func delete(account: String) throws
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

/// Which platform store a `PlatformCredentialVault` uses.
public enum CredentialStorageMode: String, Codable, Sendable, CaseIterable {
    /// The preferred store, and the default. On Apple platforms this is the
    /// Data Protection Keychain (`kSecUseDataProtectionKeychain`, plus the
    /// access group when one is given): items are confined to the app's team
    /// and access group, which requires a team-signed app with a provisioning
    /// profile. On Linux it is the Secret Service, through SwiftOpenUI's
    /// Security stand-in.
    case dataProtection

    #if os(macOS)
    /// The macOS file-based login keychain: no `kSecUseDataProtectionKeychain`
    /// and no access group. It works for ad-hoc signed builds, but is much
    /// weaker: items are not confined to the app or team, access is governed
    /// by per-item ACLs tied to the creating app's code signature, and any app
    /// the user approves at a keychain prompt can read them. A vault never
    /// selects this mode on its own; only the application may choose it, and
    /// only after the user explicitly opts in.
    case legacyLoginKeychain
    #endif

    /// The weaker store this platform offers when `.dataProtection` refuses
    /// the process, or nil where there is none. An application may use it
    /// only after the user explicitly opts in, so it asks the user only
    /// where this is non-nil, with one code path on every platform.
    ///
    /// macOS: `.legacyLoginKeychain` (ad-hoc signed builds cannot use the
    /// Data Protection Keychain). The iOS family and Linux's Secret Service
    /// have no weaker alternative: nil.
    public static var optInFallback: CredentialStorageMode? {
        #if os(macOS)
        .legacyLoginKeychain
        #else
        nil
        #endif
    }
}

/// Whether a vault can store secrets, as established by
/// `PlatformCredentialVault.probeAvailability()` before any secret is written.
public enum CredentialVaultAvailability: Equatable, Sendable {
    case available
    /// The store exists but refused a non-interactive write, typically because
    /// the device is locked. Writes may succeed after the user unlocks.
    case locked
    /// The Data Protection Keychain refused the process, typically
    /// `errSecMissingEntitlement` (-34018) because the app is not team-signed
    /// with a provisioning profile. Only reported in `.dataProtection` mode.
    case dataProtectionKeychainUnavailable(CredentialVaultError)
    case failed(CredentialVaultError)
}

/// The Security.framework item calls `PlatformCredentialVault` makes. The
/// default backend is the real keychain (or Secret Service on Linux); tests
/// inject a fake to exercise each failure status deterministically.
public protocol KeychainItemBackend: Sendable {
    func copyMatching(_ query: [CFString: Any]) -> (status: OSStatus, item: CFTypeRef?)
    func add(_ attributes: [CFString: Any]) -> OSStatus
    func update(_ query: [CFString: Any], attributes: [CFString: Any]) -> OSStatus
    func delete(_ query: [CFString: Any]) -> OSStatus
}

public struct SystemKeychainBackend: KeychainItemBackend {
    public init() {}

    public func copyMatching(_ query: [CFString: Any]) -> (status: OSStatus, item: CFTypeRef?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item)
    }

    public func add(_ attributes: [CFString: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func update(_ query: [CFString: Any], attributes: [CFString: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    public func delete(_ query: [CFString: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// When a stored secret can be read.
///
/// Apple platforms: a keychain accessibility class, always "this device
/// only" (never backed up, never synced). Linux: the Secret Service has no
/// per-item classes; its collection is unlocked with the login session
/// (gnome-keyring, KWallet) and stays unlocked until the session ends or the
/// user locks it, so both cases read the same there: available whenever the
/// user's session has unlocked the keyring, screen lock or not.
public enum CredentialAccessibility: Sendable, Equatable {
    /// Only while the device is unlocked (sign-ins and tokens).
    case whenUnlocked
    /// From the first unlock after boot on, also while the device is locked
    /// again: for keys that work done while locked needs (at-rest keys).
    case afterFirstUnlock
}

/// The platform credential adapter. Apple uses the Data Protection Keychain
/// unless the application explicitly selects `.legacyLoginKeychain` (macOS
/// only); Linux uses SwiftOpenUI's Security-compatible Secret Service layer.
public struct PlatformCredentialVault: CredentialDataVault {
    public let service: String
    /// Applied only in `.dataProtection` mode.
    public let accessGroup: String?
    public let mode: CredentialStorageMode
    /// Applied only in `.dataProtection` mode.
    public let accessibility: CredentialAccessibility
    private let backend: any KeychainItemBackend

    public init(service: String, accessGroup: String? = nil, mode: CredentialStorageMode = .dataProtection,
                accessibility: CredentialAccessibility = .whenUnlocked,
                backend: any KeychainItemBackend = SystemKeychainBackend()) {
        self.service = service
        self.accessibility = accessibility
        self.accessGroup = accessGroup
        self.mode = mode
        self.backend = backend
    }

    /// Establishes whether this vault can store secrets, by adding and then
    /// deleting a uniquely named, non-secret marker item. Reads cannot answer
    /// this: an unentitled process gets `errSecItemNotFound` from
    /// `SecItemCopyMatching` against the Data Protection Keychain, exactly as
    /// if the store were merely empty, and only a write reveals
    /// `errSecMissingEntitlement`. Check this before writing real secrets.
    public func probeAvailability() -> CredentialVaultAvailability {
        let account = "\(service).\(Self.probeAccountMarker).\(UUID().uuidString.lowercased())"
        let identity = baseQuery(account: account)
        let status = Self.withSecValue(SecureBytes(copyingUTF8: "probe")) { value in
            backend.add(additionAttributes(identity: identity, value: value))
        }
        switch status {
        case errSecSuccess:
            let removal = backend.delete(identity)
            guard removal == errSecSuccess || removal == errSecItemNotFound else {
                return .failed(CredentialVaultError(status: removal))
            }
            return .available
        case CredentialVaultError.interactionNotAllowedStatus:
            return .locked
        case CredentialVaultError.missingEntitlementStatus where mode == .dataProtection:
            return .dataProtectionKeychainUnavailable(CredentialVaultError(status: status))
        default:
            return .failed(CredentialVaultError(status: status))
        }
    }

    public func access(to account: String) -> CredentialVaultAccess {
        let status = backend.copyMatching(query(account: account, interactive: false)).status
        switch status {
        case errSecSuccess: return .available
        case errSecItemNotFound: return .missing
        case CredentialVaultError.interactionNotAllowedStatus, CredentialVaultError.authFailedStatus,
             CredentialVaultError.notAvailableStatus:
            return .locked
        default: return .unavailable(status)
        }
    }

    public func requestAccess(to account: String) throws {
        let status = backend.copyMatching(query(account: account, interactive: true)).status
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialVaultError(status: status)
        }
    }

    public func load(account: String) throws -> SecureBytes? {
        let (status, item) = backend.copyMatching(query(account: account, interactive: false))
        switch status {
        case errSecSuccess:
            guard let secret = Self.secureBytes(fromSecValue: item) else {
                throw CredentialVaultError(status: CredentialVaultError.decodeStatus)
            }
            return secret
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialVaultError(status: status)
        }
    }

    public func save(_ secret: SecureBytes, account: String) throws {
        let identity = baseQuery(account: account)
        let status = Self.withSecValue(secret) { value -> OSStatus in
            let added = backend.add(additionAttributes(identity: identity, value: value))
            guard added == errSecDuplicateItem else { return added }
            return backend.update(identity, attributes: [kSecValueData: value])
        }
        guard status == errSecSuccess else { throw CredentialVaultError(status: status) }
    }

    public func delete(account: String) throws {
        let status = backend.delete(baseQuery(account: account))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialVaultError(status: status)
        }
    }

    #if !os(Linux)
    /// The accounts of every item this vault holds, read from attributes only,
    /// so no secret is decrypted and no keychain ACL prompt is shown. Used to
    /// find items to migrate or remove when the storage mode changes.
    public func accounts() throws -> [String] {
        var query: [CFString: Any] = baseQuery(account: nil)
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitAll
        let (status, item) = backend.copyMatching(query)
        switch status {
        case errSecSuccess:
            guard let rows = item as? [[String: Any]] else {
                throw CredentialVaultError(status: CredentialVaultError.decodeStatus)
            }
            return rows.compactMap { $0[kSecAttrAccount as String] as? String }
                .filter { !$0.hasPrefix("\(service).\(Self.probeAccountMarker).") }
                .sorted()
        case errSecItemNotFound:
            return []
        default:
            throw CredentialVaultError(status: status)
        }
    }
    #endif

    private static let probeAccountMarker = "credential-storage-availability-probe"

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

    private func baseQuery(account: String?) -> [CFString: Any] {
        var result: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
        ]
        if let account { result[kSecAttrAccount] = account }
        switch mode {
        case .dataProtection:
            if let accessGroup { result[kSecAttrAccessGroup] = accessGroup }
            #if canImport(LocalAuthentication)
            result[kSecUseDataProtectionKeychain] = true
            #endif
        #if os(macOS)
        case .legacyLoginKeychain:
            // The file-based keychain has no access groups; access is decided
            // by each item's ACL, which names the creating app's signature.
            break
        #endif
        }
        return result
    }

    private func additionAttributes(identity: [CFString: Any], value: Any) -> [CFString: Any] {
        var addition = identity
        addition[kSecValueData] = value
        // Accessibility classes belong to the Data Protection Keychain; the
        // macOS file-based keychain does not use them.
        if mode == .dataProtection {
            addition[kSecAttrAccessible] = accessibility == .afterFirstUnlock
                ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        return addition
    }

    private func query(account: String, interactive: Bool) -> [CFString: Any] {
        var result = baseQuery(account: account)
        result[kSecReturnData] = true
        result[kSecMatchLimit] = kSecMatchLimitOne
        #if canImport(LocalAuthentication) && !os(tvOS)
        if mode == .dataProtection {
            let context = LAContext()
            context.interactionNotAllowed = !interactive
            result[kSecUseAuthenticationContext] = context
        }
        #endif
        return result
    }
}

public struct CredentialVaultError: LocalizedError, Equatable, Sendable {
    public let status: Int32

    public init(status: Int32) {
        self.status = status
    }

    // Spelled out so the classification below also compiles against
    // SwiftOpenUI's Linux Security stand-in, which defines only the statuses
    // its Secret Service backend can return.

    /// `errSecMissingEntitlement`: the process lacks the entitlement the
    /// Data Protection Keychain requires (a team-signed application identifier
    /// and keychain access group).
    public static let missingEntitlementStatus: Int32 = -34018
    /// `errSecInteractionNotAllowed`
    public static let interactionNotAllowedStatus: Int32 = -25308
    /// `errSecAuthFailed`
    public static let authFailedStatus: Int32 = -25293
    /// `errSecNotAvailable`
    public static let notAvailableStatus: Int32 = -25291
    /// `errSecDecode`: the store returned something that is not a secret value.
    public static let decodeStatus: Int32 = -26275

    /// Whether the Data Protection Keychain itself is unusable by this
    /// process, as opposed to a failure of one item or operation.
    public var isMissingEntitlement: Bool { status == Self.missingEntitlementStatus }

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
