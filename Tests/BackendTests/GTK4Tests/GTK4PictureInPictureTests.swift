import XCTest
import Foundation
@_spi(SwiftOpenUIBackend) import SwiftOpenUICore
@testable import BackendGTK4
import CGTK

final class GTK4PictureInPictureTests: XCTestCase {
    func testControllerMovesVideoIntoFloatingWindowAndBack() async throws {
        try await MainActor.run {
            if gtk_is_initialized() == 0 { _ = gtk_init_check() }
            guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK display") }

            let player = AVPlayer(url: URL(fileURLWithPath: "/missing-video.mp4"))
            _ = VideoPlayer(player: player).gtkCreateWidget()
            let controller = try XCTUnwrap(
                AVPictureInPictureController(playerLayer: AVPlayerLayer(player: player))
            )
            let windows = gtk_window_get_toplevels()
            let before = g_list_model_get_n_items(windows)

            XCTAssertTrue(controller.isPictureInPicturePossible)
            controller.startPictureInPicture()
            XCTAssertTrue(controller.isPictureInPictureActive)
            XCTAssertEqual(g_list_model_get_n_items(windows), before + 1)

            let floating = g_list_model_get_item(windows, before)!
            let floatingWindow = UnsafeMutableRawPointer(floating).assumingMemoryBound(to: GtkWindow.self)
            XCTAssertEqual(gtk_window_get_decorated(floatingWindow), 0)
            let windowHandle = try XCTUnwrap(gtk_window_get_child(floatingWindow))
            let content = try XCTUnwrap(gtk_window_handle_get_child(OpaquePointer(windowHandle)))
            let video = try XCTUnwrap(gtk_widget_get_first_child(content))
            let controls = try XCTUnwrap(gtk_widget_get_next_sibling(video))
            let backward = try XCTUnwrap(gtk_widget_get_first_child(controls))
            let playPause = try XCTUnwrap(gtk_widget_get_next_sibling(backward))
            let forward = try XCTUnwrap(gtk_widget_get_next_sibling(playPause))
            let time = try XCTUnwrap(gtk_widget_get_next_sibling(forward))
            let close = try XCTUnwrap(gtk_widget_get_next_sibling(time))
            XCTAssertEqual(String(cString: gtk_button_get_label(
                UnsafeMutableRawPointer(backward).assumingMemoryBound(to: GtkButton.self)
            )), "−10")
            XCTAssertEqual(String(cString: gtk_button_get_label(
                UnsafeMutableRawPointer(playPause).assumingMemoryBound(to: GtkButton.self)
            )), "Play")
            XCTAssertEqual(String(cString: gtk_button_get_label(
                UnsafeMutableRawPointer(forward).assumingMemoryBound(to: GtkButton.self)
            )), "+10")
            XCTAssertEqual(String(cString: gtk_button_get_label(
                UnsafeMutableRawPointer(close).assumingMemoryBound(to: GtkButton.self)
            )), "×")
            gtk_window_close(floatingWindow)
            g_object_unref(floating)
            XCTAssertFalse(controller.isPictureInPictureActive)
            XCTAssertEqual(g_list_model_get_n_items(windows), before)
        }
    }
}
