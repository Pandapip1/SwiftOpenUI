import XCTest
import Observation
import SwiftOpenUICore
@testable import BackendGTK4
import CGTK
import CGTKBridge

/// Pagination in a List is driven by `.onAppear` on the last row. If that
/// re-fires every time the list rebuilds, appending a page triggers the next
/// one and the feed fetches forever on its own — which is what Home does.
final class GTK4OnAppearRepeatTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
    }

    final class Counter {
        nonisolated(unsafe) static var fires = 0
        nonisolated(unsafe) static var cap = 25
    }

    struct Paginating: View {
        @State private var items: [Int] = [1, 2, 3]

        var body: some View {
            List {
                ForEach(items, id: \.self) { item in
                    Text("row \(item)")
                        .onAppear {
                            guard item == items.last else { return }
                            Counter.fires += 1
                            // Stand-in for loadMore appending a page. Capped so a
                            // runaway ends the test instead of hanging it.
                            if items.count < Counter.cap { items.append(items.count + 1) }
                        }
                }
            }
        }
    }


    @Observable
    final class Feed {
        var items: [Int] = [1, 2, 3]
        var isLoading = false
        func loadMore() async {
            guard !isLoading else { return }
            isLoading = true
            // The real loadMore awaits network work before appending.
            await Task.yield()
            if items.count < Counter.cap { items.append(items.count + 1) }
            isLoading = false
        }
    }

    struct PaginatingObservable: View {
        let feed: Feed

        var body: some View {
            List {
                ForEach(feed.items, id: \.self) { item in
                    Text("row \(item)")
                        .onAppear {
                            guard item == feed.items.last else { return }
                            Counter.fires += 1
                            Task { await feed.loadMore() }
                        }
                }
            }
        }
    }

    /// Closer to Home: an @Observable feed, and an async loadMore, which is
    /// what the app actually does.
    func testObservableFeedDoesNotPaginateForever() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK") }
        Counter.fires = 0

        let feed = Feed()
        let view = widgetFromOpaque(gtkRenderView(PaginatingObservable(feed: feed)))
        let window = gtk_window_new()!
        gtk_window_set_default_size(windowPointer(window), 600, 800)
        gtk_window_set_child(windowPointer(window), view)
        gtk_widget_set_visible(window, 1)
        for _ in 0..<4000 where g_main_context_pending(nil) != 0 {
            _ = g_main_context_iteration(nil, 0)
        }
        gtk_window_destroy(windowPointer(window))

        print("ONAPPEAR-OBSERVABLE fires=\(Counter.fires) items=\(feed.items.count)")
        XCTAssertLessThanOrEqual(
            Counter.fires, 2,
            "last-row onAppear fired \(Counter.fires) times, feed grew to \(feed.items.count)")
    }
    func testLastRowOnAppearDoesNotDriveEndlessPagination() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK") }
        Counter.fires = 0

        let view = widgetFromOpaque(gtkRenderView(Paginating()))
        let window = gtk_window_new()!
        gtk_window_set_default_size(windowPointer(window), 600, 800)
        gtk_window_set_child(windowPointer(window), view)
        gtk_widget_set_visible(window, 1)
        for _ in 0..<2000 where g_main_context_pending(nil) != 0 {
            _ = g_main_context_iteration(nil, 0)
        }
        gtk_window_destroy(windowPointer(window))

        print("ONAPPEAR fires=\(Counter.fires)")
        XCTAssertLessThanOrEqual(
            Counter.fires, 2,
            "last-row onAppear fired \(Counter.fires) times — each append retriggers it")
    }
}
