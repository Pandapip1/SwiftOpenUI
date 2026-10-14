import CSecret
import CoreFoundation
import Foundation

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
    let data: Data?

    init?(_ dictionary: CFDictionary) {
        let values = dictionary as NSDictionary
        guard (values[kSecClass] as? String) == (kSecClassGenericPassword as String),
              let service = values[kSecAttrService] as? String,
              let account = values[kSecAttrAccount] as? String else { return nil }
        self.service = service
        self.account = account
        accessGroup = values[kSecAttrAccessGroup] as? String ?? ""
        label = values[kSecAttrLabel] as? String ?? service
        data = values[kSecValueData] as? Data
    }
}

@discardableResult
public func SecItemAdd(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard let query = Query(attributes), let data = query.data else { return errSecParam }
    if lookup(query) != nil { return errSecDuplicateItem }
    return store(query, data: data)
}

@discardableResult
public func SecItemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
    guard var item = Query(query) else { return errSecParam }
    guard lookup(item) != nil else { return errSecItemNotFound }
    let updates = attributesToUpdate as NSDictionary
    guard let data = updates[kSecValueData] as? Data else { return errSecParam }
    item = QueryFields.replacingData(item, data: data)
    return store(item, data: data)
}

@discardableResult
public func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard let item = Query(query) else { return errSecParam }
    guard let data = lookup(item) else { return errSecItemNotFound }
    result?.pointee = data as CFData
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

private enum QueryFields {
    static func replacingData(_ query: Query, data: Data) -> Query {
        // `data` is passed separately to `store`; identity fields are unchanged.
        query
    }
}

private func lookup(_ query: Query) -> Data? {
    var error: UnsafeMutablePointer<GError>?
    guard let password = swift_openui_secret_lookup(query.service, query.account, query.accessGroup, &error) else {
        if let error { g_error_free(error) }
        return nil
    }
    defer { secret_password_free(password) }
    return Data(base64Encoded: String(cString: password))
}

private func store(_ query: Query, data: Data) -> OSStatus {
    var error: UnsafeMutablePointer<GError>?
    let stored = swift_openui_secret_store(
        query.service, query.account, query.accessGroup, query.label,
        data.base64EncodedString(), &error
    )
    if let error { g_error_free(error) }
    return stored != 0 ? errSecSuccess : errSecUnimplemented
}
