import Foundation
import SwiftOpenUICore

public let ASWebAuthenticationSessionErrorDomain = "com.apple.AuthenticationServices.WebAuthenticationSession"

public enum ASWebAuthenticationSessionError: Int, Error, Sendable {
    case canceledLogin = 1
    case presentationContextNotProvided = 2
    case presentationContextInvalid = 3
}

/// Linux has no presentation window requirement, but retains Apple's protocol
/// and method signature so shared source can use the native API unchanged.
public final class ASPresentationAnchor: @unchecked Sendable {
    public init() {}
}

@MainActor
public protocol ASWebAuthenticationPresentationContextProviding: AnyObject {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor
}

public final class ASWebAuthenticationSession: @unchecked Sendable {
    public typealias CompletionHandler = @Sendable (URL?, (any Error)?) -> Void

    public struct Callback: Hashable, Sendable {
        private enum Match: Hashable, Sendable { case customScheme(String); case https(String, String) }
        private let match: Match

        public static func customScheme(_ customScheme: String) -> Self {
            Self(match: .customScheme(customScheme.lowercased()))
        }

        public static func https(host: String, path: String) -> Self {
            Self(match: .https(host.lowercased(), path))
        }

        public func matchesURL(_ url: URL) -> Bool {
            switch match {
            case .customScheme(let scheme):
                return url.scheme?.lowercased() == scheme
            case .https(let host, let path):
                return url.scheme?.lowercased() == "https"
                    && url.host?.lowercased() == host && url.path == path
            }
        }
    }

    public weak var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)?
    public var prefersEphemeralWebBrowserSession = false
    public var additionalHeaderFields: [String: String]?
    public var canStart: Bool { state.withLock { !$0.started } }

    private struct State { var started = false; var completed = false }
    private let state = NSLock.State(State())
    private let url: URL
    private let callback: Callback
    private let completionHandler: CompletionHandler

    public init(url: URL, callback: Callback, completionHandler: @escaping CompletionHandler) {
        self.url = url
        self.callback = callback
        self.completionHandler = completionHandler
    }

    @discardableResult
    public func start() -> Bool {
        let shouldStart = state.withLock { state -> Bool in
            guard !state.started else { return false }
            state.started = true
            return true
        }
        guard shouldStart else { return false }
        SessionRegistry.shared.add(self)
        SystemServices.openURL(url)
        return true
    }

    public func cancel() {
        finish(url: nil, error: ASWebAuthenticationSessionError.canceledLogin)
    }

    fileprivate func receive(_ url: URL) -> Bool {
        guard callback.matchesURL(url) else { return false }
        finish(url: url, error: nil)
        return true
    }

    private func finish(url: URL?, error: (any Error)?) {
        let shouldFinish = state.withLock { state -> Bool in
            guard state.started, !state.completed else { return false }
            state.completed = true
            return true
        }
        guard shouldFinish else { return }
        SessionRegistry.shared.remove(self)
        completionHandler(url, error)
    }
}

private final class SessionRegistry: @unchecked Sendable {
    static let shared = SessionRegistry()
    private let lock = NSLock()
    private var sessions: [ObjectIdentifier: ASWebAuthenticationSession] = [:]

    private init() {
        SystemServices.handleAuthenticationURL = { [weak self] url in self?.receive(url) ?? false }
    }

    func add(_ session: ASWebAuthenticationSession) {
        lock.withLock { sessions[ObjectIdentifier(session)] = session }
    }

    func remove(_ session: ASWebAuthenticationSession) {
        _ = lock.withLock { sessions.removeValue(forKey: ObjectIdentifier(session)) }
    }

    func receive(_ url: URL) -> Bool {
        let current = lock.withLock { Array(sessions.values) }
        return current.contains { $0.receive(url) }
    }
}

private extension NSLock {
    final class State<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value
        init(_ value: Value) { self.value = value }
        func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
            lock.lock(); defer { lock.unlock() }
            return body(&value)
        }
    }
}
