import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class WKHTTPCookieStore: @unchecked Sendable {
    var reader: (@escaping ([HTTPCookie]) -> Void) -> Void = { $0([]) }

    public func getAllCookies(_ completionHandler: @escaping ([HTTPCookie]) -> Void) {
        reader(completionHandler)
    }

    public func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { continuation.resume(returning: $0) }
        }
    }
}

public final class WKWebsiteDataStore: @unchecked Sendable {
    public let httpCookieStore = WKHTTPCookieStore()
    public let isPersistent: Bool
    public var identifier: UUID? { nil }

    private init(isPersistent: Bool) { self.isPersistent = isPersistent }
    public static func `default`() -> WKWebsiteDataStore { WKWebsiteDataStore(isPersistent: true) }
    public static func nonPersistent() -> WKWebsiteDataStore { WKWebsiteDataStore(isPersistent: false) }
}

public enum WKUserScriptInjectionTime: Int, Sendable {
    case atDocumentStart
    case atDocumentEnd
}

public final class WKUserScript: @unchecked Sendable {
    public let source: String
    public let injectionTime: WKUserScriptInjectionTime
    public let isForMainFrameOnly: Bool

    public init(source: String, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool) {
        self.source = source
        self.injectionTime = injectionTime
        self.isForMainFrameOnly = forMainFrameOnly
    }
}

public final class WKUserContentController: @unchecked Sendable {
    private(set) var scripts: [WKUserScript] = []
    public init() {}
    public func addUserScript(_ userScript: WKUserScript) { scripts.append(userScript) }
    public func removeAllUserScripts() { scripts.removeAll() }

}

public final class WKContentWorld: @unchecked Sendable {
    public static let page = WKContentWorld()
    private init() {}
}
