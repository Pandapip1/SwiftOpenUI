import CSecret
import CSodium
import Foundation
import SecureMemory

// The Core Foundation types Security's API is written in, as the Swift types
// they bridge to on Apple platforms. Swift's Foundation on Linux does not
// bridge Swift and Core Foundation types (`"x" as CFString` doesn't compile),
// so callers shared with Apple platforms (`query as CFDictionary`,
// `item as? Data`) compile here against these instead.
public typealias CFString = String
public typealias CFData = Data
public typealias CFDictionary = [CFString: Any]
public typealias CFTypeRef = AnyObject

public typealias OSStatus = Int32

public let errSecSuccess: OSStatus = 0
public let errSecUnimplemented: OSStatus = -4
public let errSecParam: OSStatus = -50
public let errSecDuplicateItem: OSStatus = -25299
public let errSecItemNotFound: OSStatus = -25300

public let kSecClass = "class" as CFString
public let kSecClassGenericPassword = "genp" as CFString
public let kSecAttrService = "svce" as CFString
public let kSecAttrAccount = "acct" as CFString
public let kSecAttrAccessGroup = "agrp" as CFString
public let kSecAttrLabel = "labl" as CFString
public let kSecValueData = "v_Data" as CFString
public let kSecReturnData = "r_Data" as CFString
public let kSecMatchLimit = "m_Limit" as CFString
public let kSecMatchLimitOne = "m_LimitOne" as CFString
public let kSecAttrAccessible = "pdmn" as CFString
public let kSecAttrAccessibleAfterFirstUnlock = "ak" as CFString
public let kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly = "akpu" as CFString
public let kSecAttrAccessibleWhenUnlocked = "ck" as CFString
public let kSecAttrAccessibleWhenUnlockedThisDeviceOnly = "cku" as CFString
public let kSecUseDataProtectionKeychain = "u_DPK" as CFString

private struct Query {
    let service: String
    let account: String
    let accessGroup: String
    let label: String
    let secret: SecureBytes?

    init?(_ values: CFDictionary) {
        guard (values[kSecClass] as? String) == kSecClassGenericPassword,
              let service = values[kSecAttrService] as? String,
              let account = values[kSecAttrAccount] as? String else { return nil }
        self.service = service
        self.account = account
        accessGroup = values[kSecAttrAccessGroup] as? String ?? ""
        label = values[kSecAttrLabel] as? String ?? service
        secret = values[kSecValueData] as? SecureBytes
    }
}

// Unlike Apple's Security framework, this stand-in exchanges secret values as
// `SecureBytes`, never `Data`: `kSecValueData` must hold a `SecureBytes`, and
// `SecItemCopyMatching` returns one. Secret Service stores a base64 string,
// which is encoded and decoded here between libsecret's own non-pageable
// memory and libsodium allocations, without a Swift `String` or `Data` copy.

@discardableResult
public func SecItemAdd(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard let query = Query(attributes), let secret = query.secret else { return errSecParam }
    if lookup(query) != nil { return errSecDuplicateItem }
    return store(query, secret: secret)
}

@discardableResult
public func SecItemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
    guard let item = Query(query) else { return errSecParam }
    guard lookup(item) != nil else { return errSecItemNotFound }
    guard let secret = attributesToUpdate[kSecValueData] as? SecureBytes else { return errSecParam }
    return store(item, secret: secret)
}

@discardableResult
public func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard let item = Query(query) else { return errSecParam }
    guard let secret = lookup(item) else { return errSecItemNotFound }
    result?.pointee = secret
    return errSecSuccess
}

@discardableResult
public func SecItemDelete(_ query: CFDictionary) -> OSStatus {
    guard let item = Query(query) else { return errSecParam }
    guard lookup(item) != nil else { return errSecItemNotFound }
    var error: UnsafeMutablePointer<GError>?
    let cleared = swift_openui_secret_clear(item.service, item.account, item.accessGroup, &error)
    if let error { g_error_free(error) }
    return cleared != 0 ? errSecSuccess : errSecItemNotFound
}

private struct Base64DecodingFailed: Error {}
private struct Base64EncodingFailed: Error {}

/// Reads the stored password and decodes its base64 straight from libsecret's
/// buffer into a libsodium allocation.
private func lookup(_ query: Query) -> SecureBytes? {
    var error: UnsafeMutablePointer<GError>?
    guard let password = swift_openui_secret_lookup(query.service, query.account, query.accessGroup, &error) else {
        if let error { g_error_free(error) }
        return nil
    }
    // secret_password_free wipes the password before freeing it.
    defer { secret_password_free(password) }
    let encodedLength = strlen(password)
    guard encodedLength % 4 == 0 else { return nil }
    let equals = CChar(UInt8(ascii: "="))
    var padding = 0
    if encodedLength > 0, password[encodedLength - 1] == equals { padding += 1 }
    if encodedLength > 1, password[encodedLength - 2] == equals { padding += 1 }
    let decodedLength = encodedLength / 4 * 3 - padding
    return try? SecureBytes(count: decodedLength) { destination in
        // libsodium declares its pointers nonnull; SecureBytes buffers always
        // have a base address, even when empty.
        guard let output = destination.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            throw Base64DecodingFailed()
        }
        var written = 0
        let status = sodium_base642bin(
            output, destination.count,
            password, encodedLength, nil, &written, nil, sodium_base64_VARIANT_ORIGINAL
        )
        guard status == 0, written == decodedLength else { throw Base64DecodingFailed() }
    }
}

/// Encodes the secret as base64 into a libsodium allocation and hands that
/// buffer to libsecret, which copies it into its own non-pageable memory.
private func store(_ query: Query, secret: SecureBytes) -> OSStatus {
    // Includes the terminating NUL.
    let encodedLength = sodium_base64_encoded_len(secret.count, sodium_base64_VARIANT_ORIGINAL)
    guard let encoded = try? SecureBytes(count: encodedLength, initializingWith: { destination in
        try secret.withUnsafeBytes { source in
            // libsodium declares its pointers nonnull; SecureBytes buffers
            // always have a base address, even when empty.
            guard let output = destination.baseAddress?.assumingMemoryBound(to: CChar.self),
                  let input = source.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw Base64EncodingFailed()
            }
            _ = sodium_bin2base64(output, destination.count, input, source.count, sodium_base64_VARIANT_ORIGINAL)
        }
    }) else { return errSecParam }
    var error: UnsafeMutablePointer<GError>?
    let stored = encoded.withUnsafeBytes { password in
        swift_openui_secret_store(
            query.service, query.account, query.accessGroup, query.label,
            password.baseAddress?.assumingMemoryBound(to: CChar.self), &error
        )
    }
    if let error { g_error_free(error) }
    return stored != 0 ? errSecSuccess : errSecUnimplemented
}
