import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
public final class WebPage {
    public struct Configuration: Sendable {
        public var loadsSubresources = true
        public init() {}
    }

    public enum NavigationEvent: Hashable, Sendable {
        case startedProvisionalNavigation
        case receivedServerRedirect
        case committed
        case finished
    }

    public enum NavigationError: Error, @unchecked Sendable {
        case failedProvisionalNavigation(any Error)
        case invalidURL
        case pageClosed
        case webContentProcessTerminated
    }

    public private(set) var url: URL?
    public private(set) var title = ""
    public private(set) var isLoading = false
    public private(set) var estimatedProgress = 0.0
    public var customUserAgent: String? { didSet { _backend?.setCustomUserAgent(customUserAgent) } }

    private enum PendingLoad { case request(URLRequest), html(String, URL) }
    private var pendingLoad: PendingLoad?
    @_spi(SwiftOpenUIBackend) public let _isEphemeral: Bool
    private var userScripts: [String] = []
    @_spi(SwiftOpenUIBackend) public var _backend: (any _WebPageBackend)? {
        didSet {
            _backend?.setCustomUserAgent(customUserAgent)
            for script in userScripts { _backend?.addUserScript(script) }
            if let pendingLoad { perform(pendingLoad) }
        }
    }

    public convenience init(configuration: Configuration = Configuration()) {
        self.init(configuration: configuration, initialURL: nil)
    }

    @_spi(SwiftOpenUIBackend)
    public init(configuration: Configuration = Configuration(), initialURL: URL?) {
        _ = configuration
        _isEphemeral = false
        if let initialURL { pendingLoad = .request(URLRequest(url: initialURL)) }
    }

    @_spi(SwiftOpenUIBackend)
    public init(_isEphemeral: Bool) { self._isEphemeral = _isEphemeral }

    @discardableResult
    public func load(_ request: URLRequest) -> some AsyncSequence<NavigationEvent, any Error> {
        pendingLoad = .request(request)
        perform(.request(request))
        return eventsForCurrentNavigation()
    }

    @discardableResult
    public func load(_ url: URL?) -> some AsyncSequence<NavigationEvent, any Error> {
        guard let url else {
            return AsyncThrowingStream { $0.finish(throwing: NavigationError.invalidURL) }
        }
        let request = URLRequest(url: url)
        pendingLoad = .request(request)
        perform(.request(request))
        return eventsForCurrentNavigation()
    }

    @discardableResult
    public func load(html: String, baseURL: URL = URL(string: "about:blank")!) -> some AsyncSequence<NavigationEvent, any Error> {
        pendingLoad = .html(html, baseURL)
        perform(.html(html, baseURL))
        return eventsForCurrentNavigation()
    }

    @discardableResult
    public func reload(fromOrigin: Bool) -> some AsyncSequence<NavigationEvent, any Error> {
        _backend?.reload(fromOrigin: fromOrigin)
        return eventsForCurrentNavigation()
    }
    public func stopLoading() { _backend?.stopLoading() }

    private var observers: [UUID: AsyncThrowingStream<NavigationEvent, any Error>.Continuation] = [:]
    private func eventsForCurrentNavigation() -> AsyncThrowingStream<NavigationEvent, any Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            observers[id] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in self?.observers.removeValue(forKey: id) }
            }
        }
    }

    private func perform(_ load: PendingLoad) {
        guard let backend = _backend else { return }
        switch load {
        case .request(let request): backend.load(request)
        case .html(let html, let baseURL): backend.load(html: html, baseURL: baseURL)
        }
    }

    @_spi(SwiftOpenUIBackend)
    public func _navigationEvent(_ event: NavigationEvent, url: URL?, title: String, progress: Double) {
        _updateProperties(url: url, title: title, progress: progress)
        isLoading = event != .finished
        for observer in observers.values { observer.yield(event) }
        if event == .finished {
            for observer in observers.values { observer.finish() }
            observers.removeAll()
        }
    }


    @_spi(SwiftOpenUIBackend)
    public func _updateProperties(url: URL?, title: String, progress: Double) {
        self.url = url
        self.title = title
        estimatedProgress = progress
    }

    @_spi(SwiftOpenUIBackend)
    public func _addUserScript(_ source: String) {
        userScripts.append(source)
        _backend?.addUserScript(source)
    }

    @_spi(SwiftOpenUIBackend)
    public func _evaluateJavaScript(_ source: String, completion: @escaping (Result<String?, Error>) -> Void) {
        guard let backend = _backend else {
            completion(.failure(NavigationError.pageClosed)); return
        }
        backend.evaluateJavaScript(source, completion: completion)
    }

    @_spi(SwiftOpenUIBackend)
    public func _getCookies(completion: @escaping ([(name: String, value: String, domain: String)]) -> Void) {
        _backend?.getCookies(completion: completion) ?? completion([])
    }
}

@_spi(SwiftOpenUIBackend)
@MainActor
public protocol _WebPageBackend: AnyObject {
    func load(_ request: URLRequest)
    func load(html: String, baseURL: URL)
    func setCustomUserAgent(_ userAgent: String?)
    func reload(fromOrigin: Bool)
    func stopLoading()
    func addUserScript(_ source: String)
    func evaluateJavaScript(_ source: String, completion: @escaping (Result<String?, Error>) -> Void)
    func getCookies(completion: @escaping ([(name: String, value: String, domain: String)]) -> Void)
}
