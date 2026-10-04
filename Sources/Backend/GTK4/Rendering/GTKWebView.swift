import CGTK
import CWebKitGTK
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftOpenUI
@_spi(SwiftOpenUIBackend) import WebKit

@MainActor
private final class GTKWebPageBackend: _WebPageBackend {
    private(set) var widget: UnsafeMutablePointer<GtkWidget>!
    weak var page: WebPage?

    init(page: WebPage) {
        self.page = page
    }

    func configure(persistentDataStore: Bool, userScripts: [WKUserScript]) {
        guard widget == nil else { return }
        widget = swift_openui_webkit_new(persistentDataStore ? 1 : 0)!
        let webView = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: WebKitWebView.self)
        gtk_widget_set_hexpand(widget, 1)
        gtk_widget_set_vexpand(widget, 1)
        swift_openui_webkit_on_load_changed(webView, { view, event, context in
            guard let context else { return }
            let backend = Unmanaged<GTKWebPageBackend>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { backend.changed(view: view, event: event) }
        }, Unmanaged.passUnretained(self).toOpaque())
        let propertyChanged: SwiftOpenUIWebKitPropertyChanged = { view, _, context in
            guard let context else { return }
            let backend = Unmanaged<GTKWebPageBackend>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { backend.updateProperties(view: view) }
        }
        swift_openui_webkit_on_title_changed(webView, propertyChanged, Unmanaged.passUnretained(self).toOpaque())
        swift_openui_webkit_on_progress_changed(webView, propertyChanged, Unmanaged.passUnretained(self).toOpaque())
        for script in userScripts {
            let time: WebKitUserScriptInjectionTime = script.injectionTime == .atDocumentStart
                ? WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START : WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END
            swift_openui_webkit_add_user_script(webView, script.source, time, script.isForMainFrameOnly ? 1 : 0)
        }
    }

    func getAllCookies(_ completion: @escaping ([HTTPCookie]) -> Void) {
        readCookies(completion)
    }

    func load(_ request: URLRequest) {
        guard let url = request.url else { return }
        webkit_web_view_load_uri(webView(), url.absoluteString)
    }
    func load(html: String, baseURL: URL) { webkit_web_view_load_html(webView(), html, baseURL.absoluteString) }
    func setCustomUserAgent(_ userAgent: String?) {
        if let settings = webkit_web_view_get_settings(webView()) { webkit_settings_set_user_agent(settings, userAgent) }
    }
    func reload(fromOrigin: Bool) {
        if fromOrigin { webkit_web_view_reload_bypass_cache(webView()) }
        else { webkit_web_view_reload(webView()) }
    }
    func stopLoading() { webkit_web_view_stop_loading(webView()) }
    func evaluateJavaScript(_ source: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            let box = Unmanaged.passRetained(JavaScriptCallback(continuation))
            swift_openui_webkit_evaluate(webView(), source, { json, error, context in
                guard let context else { return }
                let continuation = Unmanaged<JavaScriptCallback>.fromOpaque(context).takeRetainedValue().continuation
                if let error {
                    continuation.resume(throwing: NSError(domain: "WebKit", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: String(cString: error)]))
                } else if let json, let data = String(cString: json).data(using: .utf8) {
                    continuation.resume(returning: try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
                } else { continuation.resume(returning: nil) }
            }, box.toOpaque())
        }
    }

    private func readCookies(_ completion: @escaping ([HTTPCookie]) -> Void) {
        let state = CookieState(completion)
        let box = Unmanaged.passRetained(state)
        swift_openui_webkit_get_cookies(webView(), { name, value, domain, done, context in
            guard let context else { return }
            let state = Unmanaged<CookieState>.fromOpaque(context).takeUnretainedValue()
            if done != 0 {
                Unmanaged<CookieState>.fromOpaque(context).release()
                state.completion(state.cookies)
            } else if let name, let value, let domain,
                      let cookie = HTTPCookie(properties: [
                        .name: String(cString: name), .value: String(cString: value),
                        .domain: String(cString: domain), .path: "/"
                      ]) { state.cookies.append(cookie) }
        }, box.toOpaque())
    }

    private func changed(view: UnsafeMutablePointer<WebKitWebView>?, event: WebKitLoadEvent) {
        guard let view else { return }
        let mapped: WebPage.NavigationEvent
        switch event {
        case WEBKIT_LOAD_STARTED: mapped = .startedProvisionalNavigation
        case WEBKIT_LOAD_REDIRECTED: mapped = .receivedServerRedirect
        case WEBKIT_LOAD_COMMITTED: mapped = .committed
        default: mapped = .finished
        }
        let url = webkit_web_view_get_uri(view).flatMap { URL(string: String(cString: $0)) }
        let title = webkit_web_view_get_title(view).map(String.init(cString:)) ?? ""
        page?._navigationEvent(mapped, url: url, title: title,
                               progress: webkit_web_view_get_estimated_load_progress(view))
    }

    private func updateProperties(view: UnsafeMutablePointer<WebKitWebView>?) {
        guard let view else { return }
        let url = webkit_web_view_get_uri(view).flatMap { URL(string: String(cString: $0)) }
        let title = webkit_web_view_get_title(view).map(String.init(cString:)) ?? ""
        page?._updateProperties(url: url, title: title,
                                progress: webkit_web_view_get_estimated_load_progress(view))
    }

    private func webView() -> UnsafeMutablePointer<WebKitWebView> {
        UnsafeMutableRawPointer(widget).assumingMemoryBound(to: WebKitWebView.self)
    }
}

private final class JavaScriptCallback {
    let continuation: CheckedContinuation<Any?, Error>
    init(_ continuation: CheckedContinuation<Any?, Error>) { self.continuation = continuation }
}

private final class CookieState {
    var cookies: [HTTPCookie] = []
    let completion: ([HTTPCookie]) -> Void
    init(_ completion: @escaping ([HTTPCookie]) -> Void) { self.completion = completion }
}

extension WebView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        MainActor.assumeIsolated {
            let backend = (page._backend as? GTKWebPageBackend) ?? GTKWebPageBackend(page: page)
            if page._backend == nil { page._backend = backend }
            if gtk_widget_get_parent(backend.widget) != nil { gtk_widget_unparent(backend.widget) }
            return OpaquePointer(backend.widget)
        }
    }
}
