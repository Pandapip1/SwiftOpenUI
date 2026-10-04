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
    let widget: UnsafeMutablePointer<GtkWidget>
    weak var page: WebPage?

    init(page: WebPage) {
        self.page = page
        widget = swift_openui_webkit_new(page._isEphemeral ? 1 : 0)!
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
    func addUserScript(_ source: String) { swift_openui_webkit_add_user_script(webView(), source) }
    func evaluateJavaScript(_ source: String, completion: @escaping (Result<String?, Error>) -> Void) {
        let box = Unmanaged.passRetained(CallbackBox(completion))
        swift_openui_webkit_evaluate(webView(), source, { value, error, context in
            guard let context else { return }
            let callback = Unmanaged<CallbackBox<Result<String?, Error>>>.fromOpaque(context).takeRetainedValue().callback
            if let error { callback(.failure(NSError(domain: "WebKitGTK", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: error)]))) }
            else { callback(.success(value.map(String.init(cString:)))) }
        }, box.toOpaque())
    }
    func getCookies(completion: @escaping ([(name: String, value: String, domain: String)]) -> Void) {
        let state = CookieCallbackState(completion)
        let box = Unmanaged.passRetained(state)
        swift_openui_webkit_get_cookies(webView(), { name, value, domain, done, context in
            guard let context else { return }
            let state = Unmanaged<CookieCallbackState>.fromOpaque(context).takeUnretainedValue()
            if done != 0 {
                Unmanaged<CookieCallbackState>.fromOpaque(context).release()
                state.completion(state.cookies)
            } else if let name, let value, let domain {
                state.cookies.append((String(cString: name), String(cString: value), String(cString: domain)))
            }
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

private final class CallbackBox<T> {
    let callback: (T) -> Void
    init(_ callback: @escaping (T) -> Void) { self.callback = callback }
}

private final class CookieCallbackState {
    var cookies: [(name: String, value: String, domain: String)] = []
    let completion: ([(name: String, value: String, domain: String)]) -> Void
    init(_ completion: @escaping ([(name: String, value: String, domain: String)]) -> Void) { self.completion = completion }
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
