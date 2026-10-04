import XCTest
import Foundation
@_spi(SwiftOpenUIBackend) import SwiftOpenUI
@testable import BackendGTK4
import CGTK

final class GTK4MediaPrerequisiteTests: XCTestCase {
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
