import Foundation
import XCTest
@testable import SwiftOpenUI

final class MediaPlayerTests: XCTestCase {
    private final class Driver: MediaPlayerDriver {
        var installedItem: MediaPlayerItem?
        var autoplay = false
        var startAt = 0.0

        func open(url: URL, autoplay: Bool, startAt: Double) {}
        func replaceCurrentItem(with item: MediaPlayerItem?) {
            installedItem = item
        }
        func play() { autoplay = true }
        func pause() {}
        func seek(to seconds: Double) { startAt = seconds }
        func stop() {}
        var currentTime: Double { 0 }
        var duration: Double { 0 }
        var isPlaying: Bool { false }
    }

    func testCompositionItemQueuedBeforeDriverPreservesBothSources() throws {
        let video = URL(string: "https://example.com/video.mp4")!
        let audio = URL(string: "https://example.com/audio.m4a")!
        let player = MediaPlayer()
        player.replaceCurrentItem(with: MediaPlayerItem(asset: MediaAsset(videoURL: video, audioURL: audio)))
        player.seek(to: 12.5)
        player.play()

        let driver = Driver()
        player.driver = driver

        XCTAssertEqual(driver.installedItem?.asset.videoURL, video)
        XCTAssertEqual(driver.installedItem?.asset.audioURL, audio)
        XCTAssertTrue(driver.autoplay)
        XCTAssertEqual(driver.startAt, 12.5)
    }
}
