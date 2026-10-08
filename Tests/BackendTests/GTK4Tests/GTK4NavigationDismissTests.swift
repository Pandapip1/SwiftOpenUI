import XCTest
import Observation
import SwiftOpenUICore
@testable import BackendGTK4
import CGTK
import CGTKBridge

final class GTK4NavigationDismissTests: XCTestCase {
    @Observable
    final class TitleState {
        var revision = 0
    }

    final class Probe {
        var dismiss = DismissAction()
        let state = TitleState()
    }

    struct Destination: View {
        let probe: Probe
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            let action = dismiss
            let _ = probe.dismiss = action
            // The destination may own an inner navigation stack. Its root
            // must retain the outer presentation's dismissal action.
            return NavigationStack { Text("Destination \(probe.state.revision)") }
        }
    }

    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
    }

    func testDestinationLinkDismissesItsEntryAndIgnoresStaleCallbacks() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK display") }
        let probe = Probe()
        let widget = widgetFromOpaque(gtkRenderView(NavigationStack {
            NavigationLink("Open") { Destination(probe: probe) }
        }))
        let window = gtk_window_new()!
        gtk_window_set_child(windowPointer(window), widget)
        gtk_widget_set_visible(window, 1)
        defer { gtk_window_destroy(windowPointer(window)) }
        let context = try XCTUnwrap(findContext(in: widget))
        let link = try XCTUnwrap(findButton("Open", in: widget))

        _ = gtk_widget_activate(link)
        pump()
        XCTAssertEqual(context.entries.count, 2)
        let firstDismiss = probe.dismiss
        firstDismiss()
        // The departing host may rebuild before its slide transition ends.
        // Its new nested titlebar must not replace the restored root chrome.
        probe.state.revision += 1
        pump()
        XCTAssertEqual(context.entries.count, 1)
        XCTAssertEqual(gtk_stack_get_visible_child(context.stack), context.entries.first?.widget)
        XCTAssertEqual(gtk_window_get_titlebar(windowPointer(window)),
                       UnsafeMutableRawPointer(context.headerBar).assumingMemoryBound(to: GtkWidget.self),
                       "popping nested navigation must restore the previous window titlebar")

        _ = gtk_widget_activate(link)
        pump()
        XCTAssertEqual(context.entries.count, 2)
        firstDismiss()
        XCTAssertEqual(context.entries.count, 2, "a callback from a dismissed destination must not pop its successor")
        probe.dismiss()
        pump()
        XCTAssertEqual(context.entries.count, 1)
    }

    func testValueDestinationDismissesAndRestoresPreviousView() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK display") }
        let probe = Probe()
        let widget = widgetFromOpaque(gtkRenderView(NavigationStack {
            Text("Root")
                .navigationDestination(for: String.self) { _ in Destination(probe: probe) }
        }))
        let window = gtk_window_new()!
        gtk_window_set_child(windowPointer(window), widget)
        gtk_widget_set_visible(window, 1)
        defer { gtk_window_destroy(windowPointer(window)) }
        let context = try XCTUnwrap(findContext(in: widget))
        context.pushValue("detail")
        pump()
        XCTAssertEqual(context.entries.count, 2)
        probe.dismiss()
        pump()
        XCTAssertEqual(context.entries.count, 1)
        XCTAssertEqual(gtk_stack_get_visible_child(context.stack), context.entries.first?.widget)
    }

    func testDismissAfterWindowDestructionDoesNotAccessTheOldStack() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK display") }
        let probe = Probe()
        let widget = widgetFromOpaque(gtkRenderView(NavigationStack {
            Text("Root")
                .navigationDestination(for: String.self) { _ in Destination(probe: probe) }
        }))
        let window = gtk_window_new()!
        gtk_window_set_child(windowPointer(window), widget)
        gtk_widget_set_visible(window, 1)
        let context = try XCTUnwrap(findContext(in: widget))
        context.pushValue("detail")
        pump()
        let dismiss = probe.dismiss
        gtk_window_destroy(windowPointer(window))
        pump()
        dismiss()
        XCTAssertEqual(context.entries.count, 2, "destroyed stack must ignore retained async dismiss actions")
    }

    func testDestinationRegistryDoesNotRetainDestroyedStackContext() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK display") }
        let widget = widgetFromOpaque(gtkRenderView(NavigationStack {
            Text("Root")
                .navigationDestination(for: String.self) { value in Text(value) }
        }))
        let window = gtk_window_new()!
        gtk_window_set_child(windowPointer(window), widget)
        gtk_widget_set_visible(window, 1)
        weak var context = try XCTUnwrap(findContext(in: widget))
        let registry = try XCTUnwrap(context?.destinationRegistry)

        gtk_window_destroy(windowPointer(window))
        pump()

        XCTAssertNil(context, "destination factories must not retain their owning navigation context")
        XCTAssertNil(registry.resolve("detail"), "saved registries cannot render into a destroyed stack")
    }

    private func pump() {
        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            while g_main_context_pending(nil) != 0 { _ = g_main_context_iteration(nil, 0) }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    private func findContext(in widget: UnsafeMutablePointer<GtkWidget>) -> GTKNavigationContext? {
        let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if let data = g_object_get_data(object, "nav-context") {
            return Unmanaged<GTKNavigationContext>.fromOpaque(data).takeUnretainedValue()
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let context = findContext(in: current) { return context }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    private func findButton(_ title: String, in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
        if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == "GtkButton",
           let label = gtk_button_get_label(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkButton.self)),
           String(cString: label) == title { return widget }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let button = findButton(title, in: current) { return button }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }
}
