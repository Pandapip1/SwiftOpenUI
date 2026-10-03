import XCTest
import SwiftOpenUI
@testable import BackendGTK4
import CGTK
import CGTKBridge

/// A List draws its rows on a card. The card must hug its rows: a GtkListBox
/// fills whatever its viewport allocates, so inside a scrolled window stretched
/// to the window it covered the entire viewport, and a single-row list looked
/// enormous until an unrelated rebuild happened to shrink it.
final class GTK4ListCardSizingTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
    }

    func testCardHugsItsRowsInATallWindow() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK") }

        let list = widgetFromOpaque(gtkRenderView(List { Text("only row") }))

        // A window far taller than one row, so a stretching card is unmistakable.
        let window = gtk_window_new()!
        gtk_window_set_default_size(windowPointer(window), 600, 800)
        gtk_window_set_child(windowPointer(window), list)
        gtk_widget_set_visible(window, 1)
        for _ in 0..<500 where g_main_context_pending(nil) != 0 {
            _ = g_main_context_iteration(nil, 0)
        }

        guard let listBox = findFirstDescendant(ofType: "GtkListBox", in: window) else {
            gtk_window_destroy(windowPointer(window))
            throw XCTSkip("no GtkListBox realised in this environment")
        }
        let cardHeight = gtk_widget_get_height(listBox)
        gtk_window_destroy(windowPointer(window))

        // One row is tens of points; the window is 800. Anything near the window
        // height means the card stretched instead of hugging.
        XCTAssertGreaterThan(cardHeight, 0, "card was never allocated")
        XCTAssertLessThan(
            cardHeight, 200,
            "the list card is \(cardHeight)pt tall for one row — it stretched to the viewport")
    }
}

private func widgetTypeName(_ widget: UnsafeMutablePointer<GtkWidget>) -> String {
    String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
}

private func findFirstDescendant(ofType typeName: String, in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
    guard gtk_swift_is_widget(widget) != 0 else { return nil }
    if widgetTypeName(widget) == typeName { return widget }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        if let found = findFirstDescendant(ofType: typeName, in: c) { return found }
        child = gtk_widget_get_next_sibling(c)
    }
    return nil
}
