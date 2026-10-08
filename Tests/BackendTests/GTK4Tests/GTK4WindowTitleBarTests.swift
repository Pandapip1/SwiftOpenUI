import XCTest
import SwiftOpenUI
@testable import BackendGTK4
import CGTK
import CGTKBridge

final class GTK4WindowTitleBarTests: XCTestCase {
    /// This mirrors the pinned Home tab: a browser-style titlebar owns the
    /// window chrome while each bottom tab owns a NavigationStack. Selecting
    /// a deferred bottom tab after the tree is attached used to bypass the
    /// outer-titlebar guard and replace the browser strip.
    struct Root: View {
        var body: some View {
            TabView {
                Tab("Home", id: "home") {
                    NavigationStack { Text("Home content").navigationTitle("Home") }
                }
                Tab("Library", id: "library") {
                    NavigationStack { Text("Library content").navigationTitle("Library") }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Browser tabs") }
            }
        }
    }

    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
    }

    func testSelectingNestedNavigationTabKeepsOuterTitlebar() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK display") }
        let root = widgetFromOpaque(gtkRenderView(Root()))
        let window = gtk_window_new()!
        let windowPointer = UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self)
        gtk_window_set_child(windowPointer, root)
        let initialTitlebar = try XCTUnwrap(gtkFindTitlebar(in: root))
        gtk_window_set_titlebar(windowPointer, initialTitlebar)
        gtk_widget_set_visible(window, 1)
        defer { gtk_window_destroy(windowPointer) }
        pump()

        XCTAssertTrue(labelTexts(in: initialTitlebar).contains("Browser tabs"))
        let header = try XCTUnwrap(findFirstWidget(ofType: "GtkHeaderBar", in: initialTitlebar))
        let principal = try XCTUnwrap(findLabel("Browser tabs", in: initialTitlebar))
        XCTAssertFalse(isDescendant(principal, of: header),
                       "principal toolbar content belongs in a separate CSD row below the header")
        let principalRow = try XCTUnwrap(gtk_widget_get_parent(principal))
        XCTAssertEqual(gtk_widget_get_parent(header), gtk_widget_get_parent(principalRow),
                       "header and principal rows should share the titlebar's vertical container")
        XCTAssertTrue(gtk_widget_has_css_class(initialTitlebar, "titlebar") != 0,
                      "the composite window titlebar should inherit native CSD styling")
        XCTAssertTrue(gtk_widget_has_css_class(principalRow, "toolbar") != 0,
                      "the principal row should use the native toolbar surface")
        XCTAssertNotEqual(gtk_widget_get_hexpand(principalRow), 0)
        XCTAssertEqual(gtk_widget_get_halign(principalRow), GTK_ALIGN_FILL)
        let tabs = try XCTUnwrap(findStack(visibleChildNamed: "home", in: root))
        gtk_swift_stack_set_visible_child_name(tabs, "library")
        pump()

        let visibleTitlebar = try XCTUnwrap(gtk_window_get_titlebar(windowPointer))
        XCTAssertTrue(labelTexts(in: visibleTitlebar).contains("Browser tabs"),
                      "the Home navigation header must not replace the browser tab strip")
        XCTAssertTrue(labelTexts(in: root).contains("Library content"))

        // Reuse that same NavigationStack after its outer chrome disappears.
        // Its header moves from the nested row to the real window titlebar,
        // where normal GTK window controls must be restored.
        let nestedHeader = try XCTUnwrap(findHeader(titled: "Library", in: visibleTitlebar))
        XCTAssertEqual(gtk_header_bar_get_show_title_buttons(OpaquePointer(nestedHeader)), 0)
        let nestedSlot = try XCTUnwrap(gtk_widget_get_parent(nestedHeader))
        let nestedSlotObject = UnsafeMutableRawPointer(nestedSlot).assumingMemoryBound(to: GObject.self)
        XCTAssertNotNil(g_object_get_data(nestedSlotObject, "gtk-swift-is-nested-titlebar-slot"))
        let slotHost = try XCTUnwrap(findNestedTitlebarSlotHost(in: root))
        let slotHostObject = UnsafeMutableRawPointer(slotHost).assumingMemoryBound(to: GObject.self)
        g_object_set_data(slotHostObject, "gtk-swift-nested-titlebar-slot", nil)
        // Re-evaluate from the toolbar's content root, as a rebuilt outer
        // view does after its root toolbar is removed.
        gtkSetVisibleWindowTitlebar(slotHost, nestedHeader)
        pump()
        XCTAssertEqual(gtk_window_get_titlebar(windowPointer), nestedHeader)
        XCTAssertNotEqual(gtk_widget_get_parent(nestedHeader), nestedSlot,
                          "the promoted header must no longer be parented by its old nested titlebar slot")
        XCTAssertNotEqual(gtk_header_bar_get_show_title_buttons(OpaquePointer(nestedHeader)), 0,
                          "a cached header promoted from a nested titlebar slot must restore its window buttons")
    }

    private func pump() {
        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            while g_main_context_pending(nil) != 0 { _ = g_main_context_iteration(nil, 0) }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    private func labelTexts(in widget: UnsafeMutablePointer<GtkWidget>) -> [String] {
        var labels: [String] = []
        func walk(_ node: UnsafeMutablePointer<GtkWidget>) {
            if String(cString: g_type_name(gtk_swift_get_widget_type(node))) == "GtkLabel" {
                labels.append(String(cString: gtk_label_get_text(OpaquePointer(node))))
            }
            var child = gtk_widget_get_first_child(node)
            while let current = child {
                walk(current)
                child = gtk_widget_get_next_sibling(current)
            }
        }
        walk(widget)
        return labels
    }

    private func findStack(visibleChildNamed name: String, in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
        if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == "GtkStack",
           let visible = gtk_swift_stack_get_visible_child_name(widget), String(cString: visible) == name {
            return widget
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let found = findStack(visibleChildNamed: name, in: current) { return found }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    private func findNestedTitlebarSlotHost(in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
        let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if g_object_get_data(object, "gtk-swift-nested-titlebar-slot") != nil { return widget }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let found = findNestedTitlebarSlotHost(in: current) { return found }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    private func findHeader(titled title: String, in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
        if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == "GtkHeaderBar",
           labelTexts(in: widget).contains(title) {
            return widget
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let found = findHeader(titled: title, in: current) { return found }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    private func findFirstWidget(ofType type: String, in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
        if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == type { return widget }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let found = findFirstWidget(ofType: type, in: current) { return found }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    private func findLabel(_ text: String, in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
        if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == "GtkLabel",
           String(cString: gtk_label_get_text(OpaquePointer(widget))) == text { return widget }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let found = findLabel(text, in: current) { return found }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    private func isDescendant(_ widget: UnsafeMutablePointer<GtkWidget>, of ancestor: UnsafeMutablePointer<GtkWidget>) -> Bool {
        var parent = gtk_widget_get_parent(widget)
        while let current = parent {
            if current == ancestor { return true }
            parent = gtk_widget_get_parent(current)
        }
        return false
    }
}
