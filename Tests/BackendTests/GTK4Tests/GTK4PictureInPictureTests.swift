import XCTest
import Foundation
@_spi(SwiftOpenUIBackend) import SwiftOpenUI
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

            controller.stopPictureInPicture()
            XCTAssertFalse(controller.isPictureInPictureActive)
            XCTAssertEqual(g_list_model_get_n_items(windows), before)
        }
    }
}
