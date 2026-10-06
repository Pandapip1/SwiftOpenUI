import XCTest
import Observation
import SwiftOpenUI
@testable import BackendGTK4
import CGTK
import CGTKBridge

/// Playing a video pops back to Home after about a second. The player's ticker
/// writes watch history once playback passes 1s, mutating an observable the
/// tree reads. If a rebuild from that loses view state, the navigation path
/// goes with it.
final class GTK4NavigationStatePersistenceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
    }

    @Observable
    final class Library {
        var writes = 0
    }

    /// Reads the observable (so it rebuilds with it) and holds @State of its own.
    /// Sets its own state once on appear, then only reads the observable.
    struct Screen: View {
        let library: Library
        @State private var pushes = 0

        var body: some View {
            VStack {
                Text("writes=\(library.writes)")
                Text("pushes=\(pushes)")
            }
            .onAppear { pushes = 7 }
        }
    }


    /// Pushes on appear, then only reads the observable — the shape of a video
    /// detail view open while the ticker writes history.
    struct NavScreen: View {
        let library: Library
        @State private var path = NavigationPath()

        var body: some View {
            NavigationStack(path: $path) {
                Text("root writes=\(library.writes)")
                    .navigationDestination(for: String.self) { value in
                        Text("pushed \(value)")
                    }
                    .onAppear { path.append("detail") }
            }
        }
    }


    /// The ancestor reads the observable; a child owns the navigation state.
    /// This is the app's shape: the root tree reads the library, while the
    /// screen holding the NavigationStack path is nested inside it.
    struct AncestorReads: View {
        let library: Library

        var body: some View {
            VStack {
                Text("writes=\(library.writes)")
                NestedNav()
            }
        }
    }

    struct NestedNav: View {
        @State private var path = NavigationPath()

        var body: some View {
            NavigationStack(path: $path) {
                Text("root")
                    .navigationDestination(for: String.self) { value in
                        Text("pushed \(value)")
                    }
                    .onAppear { path.append("detail") }
            }
        }
    }

    /// The actual shape of the bug: a plain `NavigationStack { }` with no
    /// `path:` binding at all — what `NavigationLink(value:)` is normally
    /// used with, and what Library's own `NavigationStack` uses. The push
    /// happens imperatively (a click), not by anything observing a bound
    /// path, so replaying `pathBinding.wrappedValue` on reconstruction
    /// (the path-bound case's fallback) isn't available to save it.
    struct LinkPushAncestorReads: View {
        let library: Library

        var body: some View {
            VStack {
                Text("writes=\(library.writes)")
                LinkPushNav()
            }
        }
    }

    struct LinkPushNav: View {
        var body: some View {
            NavigationStack {
                NavigationLink("Open", value: "detail")
                    .navigationDestination(for: String.self) { value in
                        Text("pushed \(value)")
                    }
            }
        }
    }

    func testNavigationLinkPushSurvivesAnAncestorRebuildWithNoPathBinding() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK") }

        let library = Library()
        let widget = widgetFromOpaque(gtkRenderView(LinkPushAncestorReads(library: library)))
        let window = gtk_window_new()!
        gtk_window_set_default_size(windowPointer(window), 600, 400)
        gtk_window_set_child(windowPointer(window), widget)
        gtk_widget_set_visible(window, 1)
        // A bounds-and-exit-when-idle pump isn't enough here: the button
        // needs a real frame-clock tick to finish realizing/mapping before
        // `gtk_widget_activate` (via `clickButton`) will actually fire its
        // "clicked" handler, same as the dismiss tests' own `pump()`.
        func pump() {
            let deadline = Date().addingTimeInterval(0.4)
            while Date() < deadline {
                while g_main_context_pending(nil) != 0 { _ = g_main_context_iteration(nil, 0) }
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        pump()

        clickButton(titled: "Open", in: widget)
        pump()
        XCTAssertTrue(labelTexts(in: widget).contains { $0.hasPrefix("pushed") },
                      "precondition: the pushed view should be on screen, got \(labelTexts(in: widget))")

        // Library's own root body reads `playbackQueue.items.count` for its
        // "Queue (N)" row directly — an ancestor of the NavigationStack, not
        // the NavigationStack itself, and nothing to do with navigation.
        library.writes += 1
        pump()

        let after = labelTexts(in: widget)
        gtk_window_destroy(windowPointer(window))
        XCTAssertTrue(after.contains { $0.hasPrefix("pushed") },
                      "an ancestor rebuild popped a NavigationLink push with no path binding: \(after)")
    }

    func testNavigationSurvivesAnAncestorRebuild() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK") }

        let library = Library()
        let widget = widgetFromOpaque(gtkRenderView(AncestorReads(library: library)))
        let window = gtk_window_new()!
        gtk_window_set_default_size(windowPointer(window), 600, 400)
        gtk_window_set_child(windowPointer(window), widget)
        gtk_widget_set_visible(window, 1)
        func pump() { for _ in 0..<400 where g_main_context_pending(nil) != 0 { _ = g_main_context_iteration(nil, 0) } }
        pump()

        XCTAssertTrue(labelTexts(in: widget).contains { $0.hasPrefix("pushed") },
                      "precondition: pushed view should be on screen, got \(labelTexts(in: widget))")

        // The ticker's history write, read by the ancestor.
        library.writes += 1
        pump()

        let after = labelTexts(in: widget)
        gtk_window_destroy(windowPointer(window))
        XCTAssertTrue(after.contains { $0.hasPrefix("pushed") },
                      "an ancestor rebuild popped the navigation stack: \(after)")
    }
    func testNavigationSurvivesARebuildFromAnUnrelatedObservable() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK") }

        let library = Library()
        let widget = widgetFromOpaque(gtkRenderView(NavScreen(library: library)))
        let window = gtk_window_new()!
        gtk_window_set_default_size(windowPointer(window), 600, 400)
        gtk_window_set_child(windowPointer(window), widget)
        gtk_widget_set_visible(window, 1)
        func pump() { for _ in 0..<400 where g_main_context_pending(nil) != 0 { _ = g_main_context_iteration(nil, 0) } }
        pump()

        XCTAssertTrue(labelTexts(in: widget).contains { $0.hasPrefix("pushed") },
                      "precondition: the pushed view should be on screen, got \(labelTexts(in: widget))")

        library.writes += 1
        pump()

        let after = labelTexts(in: widget)
        gtk_window_destroy(windowPointer(window))
        XCTAssertTrue(after.contains { $0.hasPrefix("pushed") },
                      "an unrelated observable change popped the navigation stack: \(after)")
    }
    func testViewStateSurvivesARebuildFromAnUnrelatedObservable() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK") }

        let library = Library()
        let widget = widgetFromOpaque(gtkRenderView(Screen(library: library)))
        let window = gtk_window_new()!
        gtk_window_set_default_size(windowPointer(window), 600, 400)
        gtk_window_set_child(windowPointer(window), widget)
        gtk_widget_set_visible(window, 1)
        func pump() { for _ in 0..<300 where g_main_context_pending(nil) != 0 { _ = g_main_context_iteration(nil, 0) } }
        pump()

        pump()
        XCTAssertTrue(labelTexts(in: widget).contains("pushes=7"),
                      "precondition: onAppear should set the state, got \(labelTexts(in: widget))")

        // The history write: touches nothing this view's own state depends on.
        library.writes += 1
        pump()

        let after = labelTexts(in: widget)
        gtk_window_destroy(windowPointer(window))
        XCTAssertTrue(after.contains("writes=1"), "the rebuild should show the new value: \(after)")
        XCTAssertTrue(after.contains("pushes=7"),
                      "view state was reset by an unrelated observable change: \(after)")
    }
}

private func widgetTypeName(_ w: UnsafeMutablePointer<GtkWidget>) -> String {
    String(cString: g_type_name(gtk_swift_get_widget_type(w)))
}

private func clickButton(titled title: String, in widget: UnsafeMutablePointer<GtkWidget>) {
    if widgetTypeName(widget) == "GtkButton",
       let label = gtk_button_get_label(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkButton.self)),
       String(cString: label) == title {
        gtk_widget_activate(widget)
        return
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        clickButton(titled: title, in: c)
        child = gtk_widget_get_next_sibling(c)
    }
}

private func labelTexts(in widget: UnsafeMutablePointer<GtkWidget>) -> [String] {
    var result: [String] = []
    walk(widget, &result)
    return result
}

private func walk(_ widget: UnsafeMutablePointer<GtkWidget>, _ result: inout [String]) {
    if widgetTypeName(widget) == "GtkLabel" {
        result.append(String(cString: gtk_label_get_text(OpaquePointer(widget))))
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        walk(c, &result)
        child = gtk_widget_get_next_sibling(c)
    }
}
