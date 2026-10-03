import XCTest
import SwiftOpenUI
@testable import BackendGTK4
import CGTK
import CGTKBridge

/// A navigation path value is a route, not a label. Falling back to
/// String(describing:) for a destination with no title put the whole debug
/// dump of the pushed value in the header -- one unbreakable line that grew
/// the window to several screens wide.
final class GTK4NavigationTitleTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
    }

    /// Stands in for Hummingbird's `Route.item(ContentItem(...))`: an enum case
    /// wrapping a struct, whose description is long and full of internals.
    private enum Route: Hashable {
        case item(Item)
        struct Item: Hashable {
            var id = "debug-video-1"
            var name = "Debug test pattern (10s, 320x240)"
            var url = "http://127.0.0.1:8742/watch/debug-video-1"
            var author = "Debug Source"
            var description = String(repeating: "long description ", count: 10)
        }
    }

    func testUntitledDestinationDoesNotUseTheValueDescription() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK") }

        let route = Route.item(Route.Item())
        let dumped = String(describing: route)
        // Guard the premise: the description really is long enough to matter.
        XCTAssertGreaterThan(dumped.count, 200, "test route is not representative")

        let stack = widgetFromOpaque(gtkRenderView(
            NavigationStack {
                Text("root")
            }
        ))

        // Whatever labels the header carries, none may be the dumped value.
        let labels = labelTexts(in: stack)
        for label in labels {
            XCTAssertFalse(
                label.contains("Route.Item(") || label.contains("item(Route"),
                "a path value's description leaked into the UI: \(label.prefix(120))")
        }
    }
}


private func widgetTypeName(_ widget: UnsafeMutablePointer<GtkWidget>) -> String {
    String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
}

private func labelTexts(in widget: UnsafeMutablePointer<GtkWidget>) -> [String] {
    var result: [String] = []
    labelTextsWalk(in: widget, result: &result)
    return result
}

private func labelTextsWalk(in widget: UnsafeMutablePointer<GtkWidget>, result: inout [String]) {
    if widgetTypeName(widget) == "GtkLabel" {
        result.append(String(cString: gtk_label_get_text(OpaquePointer(widget))))
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        labelTextsWalk(in: c, result: &result)
        child = gtk_widget_get_next_sibling(c)
    }
}
