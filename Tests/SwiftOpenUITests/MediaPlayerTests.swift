import Foundation
import XCTest
@_spi(SwiftOpenUIBackend) @testable import SwiftOpenUICore

final class AVPlayerCompatibilityTests: XCTestCase {
    func testAssetLoadsMediaSelectionGroupsAsynchronously() async throws {
        let asset = AVURLAsset(url: URL(string: "https://example.com/video.mp4")!)
        let option = AVMediaSelectionOption(
            mediaType: .audio,
            displayName: "English",
            locale: Locale(identifier: "en"),
            index: 0,
            characteristic: .audible
        )
        let group = AVMediaSelectionGroup(
            options: [option],
            allowsEmptySelection: false,
            characteristic: .audible
        )
        asset._swiftOpenUISetMediaSelectionGroups([.audible: group])

        let characteristics = try await asset.load(.availableMediaCharacteristicsWithMediaSelectionOptions)
        let loadedGroup = try await asset.loadMediaSelectionGroup(for: .audible)

        XCTAssertEqual(characteristics, [.audible])
        XCTAssertTrue(loadedGroup === group)
    }

    func testAsyncPropertySupportsGenericLoadingOnAssetSubclasses() async throws {
        let asset = AVURLAsset(url: URL(string: "https://example.com/video.mp4")!)
        let group = AVMediaSelectionGroup(options: [], allowsEmptySelection: false, characteristic: .audible)
        asset._swiftOpenUISetMediaSelectionGroups([.audible: group])

        let characteristics = try await loadCharacteristics(from: asset)

        XCTAssertEqual(characteristics, [.audible])
    }

    private func loadCharacteristics<Asset: AVAsset>(
        from asset: Asset
    ) async throws -> [AVMediaCharacteristic] {
        let property: AVAsyncProperty<Asset, [AVMediaCharacteristic]> =
            .availableMediaCharacteristicsWithMediaSelectionOptions
        return try await asset.load(property)
    }

    @MainActor
    private final class Driver: _AVPlayerDriver {
        var installedItem: AVPlayerItem?
        var rate: Float = 0
        var currentTime = CMTime.zero
        var duration = CMTime(seconds: 30, preferredTimescale: 600)
        var pictureInPictureActive = false

        func replaceCurrentItem(with item: AVPlayerItem?) { installedItem = item }
        func play() { rate = 1 }
        func pause() { rate = 0 }
        func setRate(_ value: Float) { rate = value }
        func seek(to time: CMTime) { currentTime = time }
        var isPictureInPicturePossible: Bool { true }
        func startPictureInPicture() { pictureInPictureActive = true }
        func stopPictureInPicture() { pictureInPictureActive = false }
    }

    func testCompositionItemQueuedBeforeDriverPreservesBothSources() async throws {
        try await MainActor.run {
        let video = URL(string: "https://example.com/video.mp4")!
        let audio = URL(string: "https://example.com/audio.m4a")!
        let composition = AVMutableComposition()
        let videoTrack = AVAssetTrack(mediaType: .video, sourceURL: video)
        let audioTrack = AVAssetTrack(mediaType: .audio, sourceURL: audio)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 30, preferredTimescale: 600)),
                             of: videoTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 30, preferredTimescale: 600)),
                             of: audioTrack, at: .zero)
        let player = AVPlayer(playerItem: AVPlayerItem(asset: composition))
        player.seek(to: CMTime(seconds: 12.5, preferredTimescale: 600))
        player.play()

        let driver = Driver()
        player._swiftOpenUIAttachDriver(driver)

        let installedAsset = driver.installedItem?.asset
        let rate = driver.rate
        let seconds = driver.currentTime.seconds
        XCTAssertTrue(installedAsset === composition)
        XCTAssertEqual(rate, 1)
        XCTAssertEqual(seconds, 12.5)
        XCTAssertEqual(player._swiftOpenUIDuration.seconds, 30)

        player.defaultRate = 1.5
        player.play()
        XCTAssertEqual(driver.rate, 1.5)
        player.playImmediately(atRate: 0.75)
        XCTAssertEqual(player.rate, 0.75)

        let pip = AVPictureInPictureController(contentSource: .init(playerLayer: AVPlayerLayer(player: player)))
        XCTAssertTrue(pip.isPictureInPicturePossible)
        pip.startPictureInPicture()
        XCTAssertTrue(pip.isPictureInPictureActive)
        XCTAssertTrue(driver.pictureInPictureActive)
        pip.stopPictureInPicture()
        XCTAssertFalse(driver.pictureInPictureActive)
        }
    }
}
