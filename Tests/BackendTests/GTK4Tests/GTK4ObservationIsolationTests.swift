import XCTest
import Observation
import SwiftOpenUICore
@testable import BackendGTK4
import CGTK
import CGTKBridge

final class GTK4ObservationIsolationTests: XCTestCase {
    @Observable final class Model { var history = 0; var name = "before" }
    final class Counts { var parent = 0; var child = 0 }

    struct Parent: View {
        let model: Model
        let counts: Counts
        var body: some View {
            let _ = { counts.parent += 1 }()
            return VStack {
                NavigationStack {
                    NavigationLink("Open", value: "detail")
                        .navigationDestination(for: String.self) { Text($0) }
                }
                Child(model: model, counts: counts)
            }
        }
    }

    struct Child: View {
        let model: Model
        let counts: Counts
        var body: some View {
            let _ = { counts.child += 1 }()
            return Text("history=\(model.history)")
        }
    }

    struct BoundField: View {
        let model: Model
        var body: some View {
            @Bindable var model = model
            return TextField("Name", text: $model.name)
        }
    }

    func testBindableFieldTracksExternalChanges() throws {
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK display") }
        let model = Model()
        let widget = widgetFromOpaque(gtkRenderView(BoundField(model: model)))
        let window = gtk_window_new()!
        gtk_window_set_child(windowPointer(window), widget)
        gtk_widget_set_visible(window, 1)
        defer { gtk_window_destroy(windowPointer(window)) }
        func fieldText(_ widget: UnsafeMutablePointer<GtkWidget>) -> String? {
            if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == "GtkEntry" {
                return String(cString: gtk_editable_get_text(OpaquePointer(widget)))
            }
            var child = gtk_widget_get_first_child(widget)
            while let current = child {
                if let text = fieldText(current) { return text }
                child = gtk_widget_get_next_sibling(current)
            }
            return nil
        }
        XCTAssertEqual(fieldText(widget), "before")
        model.name = "after"
        for _ in 0..<500 where g_main_context_pending(nil) != 0 {
            _ = g_main_context_iteration(nil, 0)
        }
        XCTAssertEqual(fieldText(widget), "after")
    }

    func testDescendantObservationDoesNotRebuildParent() throws {
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK display") }
        let model = Model()
        let counts = Counts()
        let widget = widgetFromOpaque(gtkRenderView(Parent(model: model, counts: counts)))
        let window = gtk_window_new()!
        gtk_window_set_child(windowPointer(window), widget)
        gtk_widget_set_visible(window, 1)
        defer { gtk_window_destroy(windowPointer(window)) }
        func pump() {
            for _ in 0..<500 where g_main_context_pending(nil) != 0 {
                _ = g_main_context_iteration(nil, 0)
            }
        }
        pump()
        let initialParent = counts.parent
        let initialChild = counts.child
        model.history = 1
        pump()
        XCTAssertGreaterThan(counts.child, initialChild)
        XCTAssertEqual(counts.parent, initialParent,
                       "a descendant history read must not subscribe its ancestors")
        let afterFirst = counts.child
        model.history = 2
        pump()
        XCTAssertGreaterThan(counts.child, afterFirst, "observation must re-register")
        XCTAssertEqual(counts.parent, initialParent)
    }
}
