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
        public var websiteDataStore: WKWebsiteDataStore = .default()
        public var userContentController = WKUserContentController()
        public init() {}
    }

    fileprivate let webView: WKWebView
    public var url: URL? { webView.url }
    public var title: String { webView.title ?? "" }
    public var customUserAgent: String? {
        get { webView.customUserAgent }
        set { webView.customUserAgent = newValue }
    }

    public init(configuration: Configuration = Configuration()) {
        let native = WKWebViewConfiguration()
        native.websiteDataStore = configuration.websiteDataStore
        native.userContentController = configuration.userContentController
        webView = WKWebView(frame: .zero, configuration: native)
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

#if os(macOS)
public struct WebView: NSViewRepresentable {
    public let page: WebPage
    public init(_ page: WebPage) { self.page = page }
    public func makeNSView(context: Context) -> WKWebView { page.webView }
    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
public struct WebView: UIViewRepresentable {
    public let page: WebPage
    public init(_ page: WebPage) { self.page = page }
    public func makeUIView(context: Context) -> WKWebView { page.webView }
    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
#endif
