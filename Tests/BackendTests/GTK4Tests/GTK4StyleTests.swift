import XCTest
import SwiftOpenUICore
@testable import BackendGTK4
import CGTK
import CGTKBridge

@MainActor
final class GTK4StyleTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 {
            _ = gtk_init_check()
        }
    }

    // MARK: - Button style modifier rendering

    func testEquivalentInlineStylesReuseOneDisplayProvider() throws {
        try requireGTK()
        let first = gtk_label_new("First")!
        let second = gtk_label_new("Second")!
        let before = gtkSharedCSSRuleCount()

        applyCSSToWidget(first, properties: "min-width: 137.25px;")
        let afterFirst = gtkSharedCSSRuleCount()
        applyCSSToWidget(second, properties: "min-width: 137.25px;")

        XCTAssertEqual(afterFirst, before + 1)
        XCTAssertEqual(gtkSharedCSSRuleCount(), afterFirst,
                       "equivalent widget styles must not install another display-wide provider")

        g_object_ref_sink(gpointer(first))
        g_object_ref_sink(gpointer(second))
        g_object_unref(gpointer(first))
        XCTAssertEqual(gtkSharedCSSRuleCount(), afterFirst,
                       "the shared provider must remain while another widget uses it")
        g_object_unref(gpointer(second))
        XCTAssertEqual(gtkSharedCSSRuleCount(), before,
                       "an unused dynamic style must not leak its display provider")
    }

    func testButtonStyleModifierRendersContent() throws {
        try requireGTK()
        let widget = widgetFromOpaque(gtkRenderView(
            Button("Tap") {}.buttonStyle(.plain)
        ))
        XCTAssertNotNil(widget)
    }

    func testButtonStyleBorderedProminentRendersContent() throws {
        try requireGTK()
        let widget = widgetFromOpaque(gtkRenderView(
            Button("Tap") {}.buttonStyle(.borderedProminent)
        ))
        XCTAssertNotNil(widget)
    }

    func testButtonStyleAutomaticRendersContent() throws {
        try requireGTK()
        let widget = widgetFromOpaque(gtkRenderView(
            Button("Tap") {}.buttonStyle(.automatic)
        ))
        XCTAssertNotNil(widget)
    }

    // MARK: - Toggle style modifier rendering

    func testToggleStyleCheckboxRendersCheckButton() throws {
        try requireGTK()
        let widget = widgetFromOpaque(gtkRenderView(
            Toggle("Option", isOn: .constant(true)).toggleStyle(.checkbox)
        ))
        let typeName = widgetTypeName(widget)
        XCTAssertEqual(typeName, "GtkCheckButton",
                       "Checkbox style should render as GtkCheckButton")
    }

    func testToggleStyleSwitchRendersSwitchWidget() throws {
        try requireGTK()
        let widget = widgetFromOpaque(gtkRenderView(
            Toggle("Option", isOn: .constant(true)).toggleStyle(.switch)
        ))
        // With a label, the switch is wrapped in a horizontal GtkBox
        let typeName = widgetTypeName(widget)
        XCTAssertEqual(typeName, "GtkBox",
                       "Switch style with label should render as GtkBox (label + switch)")
    }

    func testToggleStyleSwitchWithoutLabelRendersSwitchDirectly() throws {
        try requireGTK()
        let widget = widgetFromOpaque(gtkRenderView(
            Toggle(isOn: .constant(false)).toggleStyle(.switch)
        ))
        let typeName = widgetTypeName(widget)
        XCTAssertEqual(typeName, "GtkSwitch",
                       "Switch style without label should render as GtkSwitch")
    }

    func testToggleStyleAutomaticRendersCheckButton() throws {
        try requireGTK()
        let widget = widgetFromOpaque(gtkRenderView(
            Toggle("Option", isOn: .constant(true)).toggleStyle(.automatic)
        ))
        let typeName = widgetTypeName(widget)
        XCTAssertEqual(typeName, "GtkCheckButton",
                       "Automatic toggle style should render as GtkCheckButton on GTK")
    }

    // MARK: - TextField style modifier rendering

    func testTextFieldStyleModifierRendersContent() throws {
        try requireGTK()
        var text = ""
        let widget = widgetFromOpaque(gtkRenderView(
            TextField("Name", text: Binding(get: { text }, set: { text = $0 }))
                .textFieldStyle(.plain)
        ))
        XCTAssertNotNil(widget)
    }

    func testTextFieldStyleRoundedBorderRendersContent() throws {
        try requireGTK()
        var text = ""
        let widget = widgetFromOpaque(gtkRenderView(
            TextField("Name", text: Binding(get: { text }, set: { text = $0 }))
                .textFieldStyle(.roundedBorder)
        ))
        XCTAssertNotNil(widget)
    }

    // MARK: - Style environment propagation

    func testButtonStylePropagatesThroughVStack() throws {
        try requireGTK()
        // Style modifier wraps a VStack containing a button.
        // The button should read the style from the environment.
        let widget = widgetFromOpaque(gtkRenderView(
            VStack {
                Button("Tap") {}
            }.buttonStyle(.borderedProminent)
        ))
        XCTAssertNotNil(widget)
    }

    func testToggleStyleSwitchPropagatesThroughVStack() throws {
        try requireGTK()
        let widget = widgetFromOpaque(gtkRenderView(
            VStack {
                Toggle("Option", isOn: .constant(true))
            }.toggleStyle(.switch)
        ))
        // The toggle inside the VStack should be a switch (label + GtkSwitch in HBox).
        // Find a GtkSwitch descendant to verify the style propagated.
        let sw = findFirstDescendant(ofType: "GtkSwitch", in: widget)
        XCTAssertNotNil(sw, "Toggle with .switch style in VStack should contain a GtkSwitch")
    }
}

// MARK: - Helpers

private func requireGTK(
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard gtk_is_initialized() != 0 else {
        throw XCTSkip("GTK could not initialize in this environment.", file: file, line: line)
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
