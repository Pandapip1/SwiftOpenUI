import XCTest
import Foundation
@_spi(SwiftOpenUIBackend) import SwiftOpenUI
@testable import BackendGTK4
import CGTK

final class GTK4MediaPrerequisiteTests: XCTestCase {
    @MainActor
    func testRenderedAVPlayerSeekMovesActivePipeline() async throws {
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK display") }
        guard let fixtureValue = ProcessInfo.processInfo.environment["SWIFTOPENUI_MEDIA_TEST_URL"],
              let fixture = URL(string: fixtureValue) else {
            throw XCTSkip("requires SWIFTOPENUI_MEDIA_TEST_URL")
        }

        let player = AVPlayer(url: fixture)
        _ = gtkRenderView(VideoPlayer(player: player))
        player.pause()

        let deadline = Date().addingTimeInterval(3)
        while player._swiftOpenUIDuration.seconds <= 0, Date() < deadline {
            while g_main_context_iteration(nil, 0) != 0 {}
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThan(player._swiftOpenUIDuration.seconds, 0)

        player.seek(to: CMTime(seconds: 5, preferredTimescale: 600))
        var observed = player.currentTime().seconds
        let seekDeadline = Date().addingTimeInterval(3)
        while abs(observed - 5) > 0.75, Date() < seekDeadline {
            while g_main_context_iteration(nil, 0) != 0 {}
            try await Task.sleep(nanoseconds: 20_000_000)
            observed = player.currentTime().seconds
        }
        XCTAssertEqual(observed, 5, accuracy: 0.75)
    }

    /// Run in a fresh process with empty GST_PLUGIN_{SYSTEM_,}PATH_1_0 and a
    /// disposable GST_REGISTRY_1_0; GStreamer's registry is process-global.
    func testMissingPluginsReportFailureWithoutOpeningMedia() async throws {
        try await MainActor.run {
        guard ProcessInfo.processInfo.environment["SWIFTOPENUI_TEST_MISSING_GST"] == "1" else {
            throw XCTSkip("requires a process with an empty GStreamer plugin registry")
        }
        if gtk_is_initialized() == 0 { _ = gtk_init_check() }
        guard gtk_is_initialized() != 0 else { throw XCTSkip("no GTK display") }
        let error = try XCTUnwrap(gtk_swift_video_prerequisite_error())
        XCTAssertTrue(String(cString: error).contains("playbin3"))
        let player = AVPlayer()
        let failure = expectation(description: "recoverable playback failure")
        player._swiftOpenUIOnFailure = { message in
            XCTAssertTrue(message.contains("playbin3"))
            failure.fulfill()
        }
        let driver = GTKVideoDriver(player: player)
        driver.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: "/missing-video.mp4")))
        driver.play()
        XCTAssertEqual(XCTWaiter().wait(for: [failure], timeout: 1), .completed)
        let rate = driver.rate
        let seconds = driver.currentTime.seconds
        XCTAssertEqual(rate, 0)
        XCTAssertEqual(seconds, 0)
        }
    }
}
