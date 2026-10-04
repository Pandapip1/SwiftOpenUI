import XCTest
import SwiftOpenUI
import WebKit
@testable import BackendGTK4
import CGTK
import CGTKBridge

final class GTK4WebViewTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
    }

    func testWebViewLoadsHTMLAndReportsNavigation() async throws {
        try await MainActor.run {
            guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK") }
            var configuration = WebPage.Configuration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.addUserScript(WKUserScript(
                source: "document.title = 'SwiftOpenUI WebKit';",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
            let page = WebPage(configuration: configuration)
            let widget = widgetFromOpaque(gtkRenderView(WebView(page)))
            let window = gtk_window_new()!
            gtk_window_set_child(windowPointer(window), widget)
            gtk_widget_set_visible(window, 1)
            page.load(html: "<html><head><title>Before injection</title></head><body>ready</body></html>")

            let deadline = Date().addingTimeInterval(10)
            while page.title != "SwiftOpenUI WebKit", Date() < deadline {
                _ = g_main_context_iteration(nil, 0)
            }

            XCTAssertEqual(page.title, "SwiftOpenUI WebKit")
            XCTAssertEqual(page.url?.absoluteString, "about:blank")
            XCTAssertFalse(page.isLoading)
            gtk_window_destroy(windowPointer(window))
        }
    }
}
