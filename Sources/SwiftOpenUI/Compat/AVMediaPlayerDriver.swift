#if canImport(AVFoundation)
import Foundation
import AVFoundation
#if canImport(AVKit)
import AVKit
#endif

/// Apple implementation of SwiftOpenUI's media abstraction.
///
/// AVFoundation owns decoding and stream selection; SwiftOpenUI exposes only
/// the backend-neutral `MediaTrack` values to the application.
@MainActor
public final class AVMediaPlayerDriver: NSObject, MediaPlayerDriver {
    public let avPlayer: AVPlayer
    private var item: AVPlayerItem?
    #if canImport(AVKit)
    private var pip: AVPictureInPictureController?
    #endif

    public init(player: AVPlayer = AVPlayer()) {
        self.avPlayer = player
        super.init()
    }

    public func open(url: URL, autoplay: Bool, startAt: Double) {
        let next = AVPlayerItem(url: url)
        item = next
        avPlayer.replaceCurrentItem(with: next)
        if startAt > 0 { avPlayer.seek(to: CMTime(seconds: startAt, preferredTimescale: 600)) }
        if autoplay { avPlayer.play() }
    }
    public func play() { avPlayer.play() }
    public func pause() { avPlayer.pause() }
    public func seek(to seconds: Double) { avPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
    public func stop() { avPlayer.pause(); avPlayer.replaceCurrentItem(with: nil); item = nil }
    public var currentTime: Double { avPlayer.currentTime().seconds }
    public var duration: Double { item?.duration.seconds ?? 0 }
    public var isPlaying: Bool { avPlayer.rate > 0 }

    public var tracks: [MediaTrack] {
        guard let item else { return [] }
        var result: [MediaTrack] = []
        for kind in [AVMediaCharacteristicVisual, AVMediaCharacteristicAudible, AVMediaCharacteristicLegible] {
            guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: kind) else { continue }
            let mediaKind: MediaTrack.Kind = kind == AVMediaCharacteristicVisual ? .video : kind == AVMediaCharacteristicAudible ? .audio : .subtitles
            result += group.options.enumerated().map { index, option in
                MediaTrack(id: "\(mediaKind.rawValue)-\(index)", kind: mediaKind,
                           language: option.locale?.identifier, label: option.displayName)
            }
        }
        return result
    }

    public func selectTrack(_ track: MediaTrack?) {
        guard let item, let track else { return }
        let characteristic: AVMediaCharacteristic = switch track.kind {
        case .video: AVMediaCharacteristicVisual
        case .audio: AVMediaCharacteristicAudible
        case .subtitles: AVMediaCharacteristicLegible
        }
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic),
              let index = Int(track.id.split(separator: "-").last ?? "-1"), index >= 0,
              index < group.options.count else { return }
        item.select(group.options[index], in: group)
    }

    #if canImport(AVKit)
    public var pictureInPictureSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }
    public func startPictureInPicture() { pip?.startPictureInPicture() }
    public func stopPictureInPicture() { pip?.stopPictureInPicture() }
    #else
    public var pictureInPictureSupported: Bool { false }
    public func startPictureInPicture() {}
    public func stopPictureInPicture() {}
    #endif
}
#endif
