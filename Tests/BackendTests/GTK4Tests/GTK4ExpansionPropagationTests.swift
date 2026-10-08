import XCTest
import SwiftOpenUICore
@testable import BackendGTK4
import CGTK
import CGTKBridge

/// A scrollable view's wish to fill its window has to survive every container
/// between it and the window. It did not: the renderer decided whether a parent
/// should expand by reading each child's *explicit* hexpand/vexpand flag, which
/// a container that expands only because a descendant does reports as 0. Any
/// view host in the chain therefore truncated it, and content sat at its natural
/// height with the rest of the window empty below.
final class GTK4ExpansionPropagationTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 {
            _ = gtk_init_check()
        }
    }

    /// A List expands vertically, and says so explicitly.
    func testListExpandsVertically() throws {
        try requireGTK()
        let list = widgetFromOpaque(gtkRenderView(List { Text("row") }))
        XCTAssertTrue(
            gtk_widget_compute_expand(list, GTK_ORIENTATION_VERTICAL) != 0,
            "a List should want to fill the space it is given")
    }

    /// The wish survives a stack wrapped around it.
    func testExpansionSurvivesAStack() throws {
        try requireGTK()
        let stacked = widgetFromOpaque(gtkRenderView(
            VStack {
                Text("header")
                List { Text("row") }
            }
        ))
        XCTAssertTrue(
            gtk_widget_compute_expand(stacked, GTK_ORIENTATION_VERTICAL) != 0,
            "a VStack containing a List should expand with it")
    }


    /// Which layer, if any, drops the expansion. Mirrors the app's real
    /// structure: TabView { NavigationStack { Group { List } } }.
    /// And survives a view host, which is the case that was broken: `MyView`
    /// renders through gtkRenderStatefulView, so its body sits inside a
    /// GTKViewHost container.
    func testExpansionSurvivesAViewHost() throws {
        try requireGTK()
        struct Hosted: View {
            var body: some View {
                VStack {
                    Text("header")
                    List { Text("row") }
                }
            }
        }
        let hosted = widgetFromOpaque(gtkRenderView(Hosted()))
        XCTAssertTrue(
            gtk_widget_compute_expand(hosted, GTK_ORIENTATION_VERTICAL) != 0,
            "a hosted view containing a List should expand with it")
    }

    /// Overlay is a layout-transparent modifier: expansion requested anywhere
    /// in its base subtree must remain visible to every parent above it.
    func testExpansionSurvivesNestedOverlays() throws {
        try requireGTK()
        let overlaid = widgetFromOpaque(gtkRenderView(
            VStack {
                Text("header")
                List { Text("row") }
            }
            .overlay { Text("first") }
            .overlay(alignment: .top) { Text("second") }
        ))
        XCTAssertTrue(
            gtk_widget_compute_expand(overlaid, GTK_ORIENTATION_VERTICAL) != 0,
            "nested overlays must preserve their base view's expansion")
    }

    func testEmptyBackgroundIsLayoutTransparent() throws {
        try requireGTK()
        let background = widgetFromOpaque(gtkRenderView(
            List { Text("row") }.background { EmptyView() }
        ))
        XCTAssertTrue(
            gtk_widget_compute_expand(background, GTK_ORIENTATION_VERTICAL) != 0,
            "an empty background must not discard its content's expansion")
    }
}

private func requireGTK(
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard gtk_is_initialized() != 0 else {
        throw XCTSkip("GTK could not initialize in this environment.", file: file, line: line)
    }
}
