import XCTest
import SwiftOpenUI
@testable import BackendGTK4
import CGTK
import CGTKBridge

/// The player is `ZStack { Color.black; ... }.aspectRatio(16/9, .fit)`. Color
/// expands in both directions and `.aspectRatio` does nothing on this backend,
/// so nothing constrains it. Clicking a video turns the whole window black with
/// the decorations pushed off screen, which is what an unbounded expanding
/// rectangle looks like.
final class GTK4PlayerSizingTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
    }

    private func allocated(_ view: some View, window: (Int32, Int32)) throws -> (Int32, Int32) {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK") }
        let widget = widgetFromOpaque(gtkRenderView(view))
        let win = gtk_window_new()!
        gtk_window_set_default_size(windowPointer(win), window.0, window.1)
        gtk_window_set_child(windowPointer(win), widget)
        gtk_widget_set_visible(win, 1)
        for _ in 0..<500 where g_main_context_pending(nil) != 0 {
            _ = g_main_context_iteration(nil, 0)
        }
        // An aspect frame fills what it is given and constrains its child, so the
        // child is what carries the ratio.
        let measured = gtk_widget_get_first_child(widget) ?? widget
        let size = (gtk_widget_get_width(measured), gtk_widget_get_height(measured))
        gtk_window_destroy(windowPointer(win))
        return size
    }

    /// A 16:9 player in a 800x600 window should be about 800x450, not the whole
    /// window and not something unbounded.
    func testPlayerRespectsItsAspectRatio() throws {
        let player = ZStack {
            Color.black
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)

        let (w, h) = try allocated(player, window: (800, 600))
        print("PLAYER allocated \(w)x\(h)")
        let expected = Int32((Double(w) * 9.0 / 16.0).rounded())
        XCTAssertLessThanOrEqual(
            abs(h - expected), 8,
            "player is \(w)x\(h); 16:9 of \(w) is \(expected), so the ratio is not applied")
    }

    /// The same thing stacked above other content: the player must not eat it.
    func testPlayerLeavesRoomForSiblings() throws {
        let page = VStack(spacing: 6) {
            ZStack { Color.black }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
            Text("title below the player")
            Text("description below the player")
        }

        let (_, h) = try allocated(page, window: (800, 600))
        print("PAGE allocated height \(h)")
        XCTAssertLessThanOrEqual(h, 600, "page wants \(h)pt in a 600pt window")
    }

    func testExplicitRatioDoesNotLeakVerticalExpansion() throws {
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK") }
        let player = widgetFromOpaque(gtkRenderView(
            ZStack { Color.black }
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
        ))

        XCTAssertNotEqual(gtk_widget_get_hexpand(player), 0)
        XCTAssertEqual(
            gtk_widget_get_vexpand(player), 0,
            "an explicit aspect ratio must derive height from width instead of consuming arbitrary vertical space"
        )
    }
}
