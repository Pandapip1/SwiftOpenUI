#if canImport(WebKit) && (os(macOS) || os(iOS) || os(visionOS))
import Foundation
import SwiftUI
import WebKit

/// The SwiftUI WebKit model API, available on older Apple releases through
/// `WKWebView`. Keeping this in SwiftOpenUI lets applications use the same
/// surface as WebKit's newer `WebPage`/`WebView` pair on every supported OS.
@MainActor
public final class WebPage {
    public struct Configuration {
        /// Each configuration gets its own non-persistent store, so a page
        /// shares no cookies, storage or cache with any other page and keeps
        /// nothing after it closes. Persistence is an explicit opt-in: set
        /// `.default()`, or a store deliberately shared between pages.
        public var websiteDataStore: WKWebsiteDataStore = .nonPersistent()
        public var userContentController = WKUserContentController()
        public init() {}
    }

    /// A navigation the page is about to perform.
    public struct NavigationAction {
        public let request: URLRequest
    }

    public enum NavigationActionPolicy: Sendable {
        case allow
        case cancel
    }

    /// Decides whether a navigation may proceed, including server redirects.
    /// Unlike WebKit's own `WebPage.NavigationDeciding`, the decision is
    /// synchronous: every backend has to answer before the load continues.
    @MainActor
    public protocol NavigationDeciding: AnyObject {
        func decidePolicy(for action: NavigationAction) -> NavigationActionPolicy
    }

    fileprivate let webView: WKWebView
    private let navigationDelegate: NavigationDelegate?
    public var url: URL? { webView.url }
    /// The store the page keeps its cookies, storage and cache in.
    public var websiteDataStore: WKWebsiteDataStore { webView.configuration.websiteDataStore }
    public var title: String { webView.title ?? "" }
    public var customUserAgent: String? {
        get { webView.customUserAgent }
        set { webView.customUserAgent = newValue }
    }

    /// `navigationDecider` is retained for the page's lifetime.
    public init(configuration: Configuration = Configuration(),
                navigationDecider: (any NavigationDeciding)? = nil) {
        let native = WKWebViewConfiguration()
        native.websiteDataStore = configuration.websiteDataStore
        native.userContentController = configuration.userContentController
        webView = WKWebView(frame: .zero, configuration: native)
        navigationDelegate = navigationDecider.map(NavigationDelegate.init)
        webView.navigationDelegate = navigationDelegate
    }

    public func load(_ url: URL?) {
        guard let url else { return }
        webView.load(URLRequest(url: url))
    }

    public func load(html: String, baseURL: URL = URL(string: "about:blank")!) {
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    public func stopLoading() { webView.stopLoading() }

    public func callJavaScript(
        _ functionBody: String,
        arguments: [String: Any] = [:]
    ) async throws -> sending Any? {
        let names = arguments.keys.sorted()
        let values = try names.map { key -> String in
            let data = try JSONSerialization.data(withJSONObject: [arguments[key] ?? NSNull()])
            let json = String(decoding: data, as: UTF8.self)
            return String(json.dropFirst().dropLast())
        }
        let source = "(async function(\(names.joined(separator: ","))){\(functionBody)})(\(values.joined(separator: ",")))"
        return try await webView.evaluateJavaScript(source)
    }
}

/// Bridges `WKNavigationDelegate` to the page's decider. WebKit calls the
/// delegate on the main thread, and its decision handler is main-actor.
@MainActor
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private let decider: any WebPage.NavigationDeciding

    init(_ decider: any WebPage.NavigationDeciding) { self.decider = decider }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let action = WebPage.NavigationAction(request: navigationAction.request)
        switch decider.decidePolicy(for: action) {
        case .allow: decisionHandler(.allow)
        case .cancel: decisionHandler(.cancel)
        }
    }
}

/// The web views shown inside one part of the interface, so a picture of
/// that part can include their content. Window captures show a web view's
/// remote-rendered content blank, so whoever captures draws each registered
/// view's own snapshot over it.
@MainActor
public final class WebViewSnapshotRegistry {
    private var entries: [ObjectIdentifier: WeakWebView] = [:]

    public init() {}

    /// The registered web views that still exist.
    public var webViews: [WKWebView] { entries.values.compactMap(\.view) }

    func add(_ webView: WKWebView) { entries[ObjectIdentifier(webView)] = WeakWebView(view: webView) }
    func remove(_ webView: WKWebView) { entries[ObjectIdentifier(webView)] = nil }

    private struct WeakWebView { weak var view: WKWebView? }
}

private struct WebViewSnapshotRegistryKey: EnvironmentKey {
    static let defaultValue: WebViewSnapshotRegistry? = nil
}

public extension EnvironmentValues {
    /// Where `WebView`s below register themselves for snapshots.
    var webViewSnapshotRegistry: WebViewSnapshotRegistry? {
        get { self[WebViewSnapshotRegistryKey.self] }
        set { self[WebViewSnapshotRegistryKey.self] = newValue }
    }
}

/// Keeps a mounted web view registered with its surroundings' registry.
@MainActor
public final class WebViewRegistration {
    private weak var registry: WebViewSnapshotRegistry?

    func update(_ webView: WKWebView, in registry: WebViewSnapshotRegistry?) {
        guard registry !== self.registry else { return }
        self.registry?.remove(webView)
        registry?.add(webView)
        self.registry = registry
    }

    func end(_ webView: WKWebView) {
        registry?.remove(webView)
        registry = nil
    }
}

#if os(macOS)
public struct WebView: NSViewRepresentable {
    public let page: WebPage
    public init(_ page: WebPage) { self.page = page }
    public func makeCoordinator() -> WebViewRegistration { WebViewRegistration() }
    public func makeNSView(context: Context) -> WKWebView {
        context.coordinator.update(page.webView, in: context.environment.webViewSnapshotRegistry)
        return page.webView
    }
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(nsView, in: context.environment.webViewSnapshotRegistry)
    }
    public static func dismantleNSView(_ nsView: WKWebView, coordinator: WebViewRegistration) {
        coordinator.end(nsView)
    }
}
#else
public struct WebView: UIViewRepresentable {
    public let page: WebPage
    public init(_ page: WebPage) { self.page = page }
    public func makeCoordinator() -> WebViewRegistration { WebViewRegistration() }
    public func makeUIView(context: Context) -> WKWebView {
        context.coordinator.update(page.webView, in: context.environment.webViewSnapshotRegistry)
        return page.webView
    }
    public func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.update(uiView, in: context.environment.webViewSnapshotRegistry)
    }
    public static func dismantleUIView(_ uiView: WKWebView, coordinator: WebViewRegistration) {
        coordinator.end(uiView)
    }
}
#endif
#endif
