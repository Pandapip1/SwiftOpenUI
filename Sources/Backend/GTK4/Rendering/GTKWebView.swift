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
        widget = webkit_web_view_new()!
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
