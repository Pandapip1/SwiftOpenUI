import Foundation

#if canImport(AVFoundation)
@_exported import AVFoundation
#else
public struct CMTime: Hashable, Sendable {
    public var value: Int64
    public var timescale: Int32
    public init(value: Int64, timescale: Int32) { self.value = value; self.timescale = timescale }
    public init(seconds: Double, preferredTimescale: Int32) {
        value = Int64(seconds * Double(preferredTimescale)); timescale = preferredTimescale
    }
    public var seconds: Double { timescale == 0 ? .nan : Double(value) / Double(timescale) }
    public static let zero = CMTime(value: 0, timescale: 1)
}

public struct CMTimeRange: Hashable, Sendable {
    public var start: CMTime
    public var duration: CMTime
    public init(start: CMTime, duration: CMTime) { self.start = start; self.duration = duration }
}

public struct AVMediaType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let video = AVMediaType(rawValue: "vide")
    public static let audio = AVMediaType(rawValue: "soun")
}

public typealias CMPersistentTrackID = Int32
public let kCMPersistentTrackID_Invalid: CMPersistentTrackID = 0

open class AVAsset: @unchecked Sendable {
    @_spi(SwiftOpenUIBackend) public var _swiftOpenUITracks: [AVAssetTrack] = []
    public init() {}
    open func loadTracks(withMediaType mediaType: AVMediaType) async throws -> [AVAssetTrack] {
        _swiftOpenUITracks.filter { $0.mediaType == mediaType }
    }
}

public final class AVURLAsset: AVAsset, @unchecked Sendable {
    public let url: URL
    @_spi(SwiftOpenUIBackend) public let _swiftOpenUIOptions: [String: Any]?
    public init(url: URL, options: [String: Any]? = nil) {
        self.url = url; _swiftOpenUIOptions = options
        super.init()
        _swiftOpenUITracks = [AVAssetTrack(mediaType: .video, sourceURL: url, sourceOptions: options),
                              AVAssetTrack(mediaType: .audio, sourceURL: url, sourceOptions: options)]
    }
}

public final class AVAssetTrack: @unchecked Sendable {
    public let mediaType: AVMediaType
    @_spi(SwiftOpenUIBackend) public let _swiftOpenUISourceURL: URL
    @_spi(SwiftOpenUIBackend) public let _swiftOpenUISourceOptions: [String: Any]?
    @_spi(SwiftOpenUIBackend) public init(mediaType: AVMediaType, sourceURL: URL,
                                          sourceOptions: [String: Any]? = nil) {
        self.mediaType = mediaType
        _swiftOpenUISourceURL = sourceURL
        _swiftOpenUISourceOptions = sourceOptions
    }
}

public final class AVMutableCompositionTrack: @unchecked Sendable {
    public let mediaType: AVMediaType
    @_spi(SwiftOpenUIBackend) public private(set) var _swiftOpenUISourceTrack: AVAssetTrack?
    fileprivate init(mediaType: AVMediaType) { self.mediaType = mediaType }
    public func insertTimeRange(_ timeRange: CMTimeRange, of track: AVAssetTrack, at startTime: CMTime) throws {
        _ = timeRange; _ = startTime; _swiftOpenUISourceTrack = track
    }
}

public final class AVMutableComposition: AVAsset, @unchecked Sendable {
    private var mutableTracks: [AVMutableCompositionTrack] = []
    public override init() { super.init() }
    public func addMutableTrack(withMediaType mediaType: AVMediaType,
                                preferredTrackID: CMPersistentTrackID) -> AVMutableCompositionTrack? {
        _ = preferredTrackID
        let track = AVMutableCompositionTrack(mediaType: mediaType)
        mutableTracks.append(track)
        return track
    }
    @_spi(SwiftOpenUIBackend) public var _swiftOpenUICompositionTracks: [AVMutableCompositionTrack] { mutableTracks }
}

public final class AVPlayerItem: @unchecked Sendable {
    public let asset: AVAsset
    public init(asset: AVAsset) { self.asset = asset }
    public convenience init(url: URL) { self.init(asset: AVURLAsset(url: url)) }
}

@_spi(SwiftOpenUIBackend)
@MainActor
public protocol _AVPlayerDriver: AnyObject {
    func replaceCurrentItem(with item: AVPlayerItem?)
    func play()
    func pause()
    func seek(to time: CMTime)
    var currentTime: CMTime { get }
    var duration: CMTime { get }
    var rate: Float { get }
    var isPictureInPicturePossible: Bool { get }
    func startPictureInPicture()
    func stopPictureInPicture()
    func setPictureInPictureActiveHandler(_ handler: (@MainActor (Bool) -> Void)?)
}

public extension _AVPlayerDriver {
    func setPictureInPictureActiveHandler(_ handler: (@MainActor (Bool) -> Void)?) {}
}

@MainActor
public final class AVPlayer: @unchecked Sendable {
    public private(set) var currentItem: AVPlayerItem?
    @_spi(SwiftOpenUIBackend) public var _swiftOpenUIDriver: _AVPlayerDriver?
    @_spi(SwiftOpenUIBackend) public var _swiftOpenUIOnEnded: (@Sendable () -> Void)?
    @_spi(SwiftOpenUIBackend) public var _swiftOpenUIOnFailure: (@Sendable (String) -> Void)?
    private var pendingTime: CMTime?
    private var pendingRate: Float = 0

    nonisolated public init() {}
    nonisolated public convenience init(url: URL) { self.init(playerItem: AVPlayerItem(url: url)) }
    nonisolated public init(playerItem item: AVPlayerItem?) { currentItem = item }
    public func replaceCurrentItem(with item: AVPlayerItem?) {
        currentItem = item; pendingTime = nil; _swiftOpenUIDriver?.replaceCurrentItem(with: item)
    }
    public func play() { pendingRate = 1; _swiftOpenUIDriver?.play() }
    public func pause() { pendingRate = 0; _swiftOpenUIDriver?.pause() }
    public func seek(to time: CMTime) { pendingTime = time; _swiftOpenUIDriver?.seek(to: time) }
    public func currentTime() -> CMTime { _swiftOpenUIDriver?.currentTime ?? pendingTime ?? .zero }
    public var rate: Float { _swiftOpenUIDriver?.rate ?? pendingRate }
    @_spi(SwiftOpenUIBackend) public var _swiftOpenUIDuration: CMTime {
        _swiftOpenUIDriver?.duration ?? .zero
    }
    @_spi(SwiftOpenUIBackend) public func _swiftOpenUIAttachDriver(_ driver: _AVPlayerDriver) {
        _swiftOpenUIDriver = driver
        driver.replaceCurrentItem(with: currentItem)
        if let pendingTime { driver.seek(to: pendingTime) }
        if pendingRate > 0 { driver.play() } else { driver.pause() }
    }
}

public final class AVPlayerLayer: @unchecked Sendable {
    public var player: AVPlayer?
    public init(player: AVPlayer? = nil) { self.player = player }
}

@MainActor
public protocol AVPictureInPictureControllerDelegate: AnyObject {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController)
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController)
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController)
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController)
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    )
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    )
}

public extension AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {}
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) { completionHandler(false) }
}

@MainActor
public final class AVPictureInPictureController: @unchecked Sendable {
    nonisolated(unsafe) private static var backendSupportsPictureInPicture = false
    public final class ContentSource: @unchecked Sendable {
        public let playerLayer: AVPlayerLayer?
        public init(playerLayer: AVPlayerLayer) { self.playerLayer = playerLayer }
    }
    public var contentSource: ContentSource?
    public weak var delegate: (any AVPictureInPictureControllerDelegate)?
    public private(set) var isPictureInPictureActive = false
    public var isPictureInPicturePossible: Bool {
        contentSource?.playerLayer?.player?._swiftOpenUIDriver?.isPictureInPicturePossible ?? false
    }
    public var canStartPictureInPictureAutomaticallyFromInline = false
    public var requiresLinearPlayback = false
    public static func isPictureInPictureSupported() -> Bool {
        backendSupportsPictureInPicture
    }
    @_spi(SwiftOpenUIBackend)
    public static func _swiftOpenUISetPictureInPictureSupported(_ supported: Bool) {
        backendSupportsPictureInPicture = supported
    }
    public init(contentSource: ContentSource) {
        self.contentSource = contentSource
        contentSource.playerLayer?.player?._swiftOpenUIDriver?.setPictureInPictureActiveHandler { [weak self] active in
            guard let self, self.isPictureInPictureActive != active else { return }
            if active {
                self.isPictureInPictureActive = true
                self.delegate?.pictureInPictureControllerDidStartPictureInPicture(self)
            } else {
                self.delegate?.pictureInPictureControllerWillStopPictureInPicture(self)
                self.isPictureInPictureActive = false
                self.delegate?.pictureInPictureControllerDidStopPictureInPicture(self)
            }
        }
    }
    public convenience init?(playerLayer: AVPlayerLayer) {
        guard Self.isPictureInPictureSupported() else { return nil }
        self.init(contentSource: ContentSource(playerLayer: playerLayer))
    }
    public func startPictureInPicture() {
        guard isPictureInPicturePossible, let driver = contentSource?.playerLayer?.player?._swiftOpenUIDriver else { return }
        delegate?.pictureInPictureControllerWillStartPictureInPicture(self)
        driver.startPictureInPicture()
        isPictureInPictureActive = true
        delegate?.pictureInPictureControllerDidStartPictureInPicture(self)
    }
    public func stopPictureInPicture() {
        guard isPictureInPictureActive else { return }
        delegate?.pictureInPictureControllerWillStopPictureInPicture(self)
        contentSource?.playerLayer?.player?._swiftOpenUIDriver?.stopPictureInPicture()
        isPictureInPictureActive = false
        delegate?.pictureInPictureControllerDidStopPictureInPicture(self)
    }
}
#endif

@MainActor @preconcurrency
public struct VideoPlayer<VideoOverlay: View>: View, PrimitiveView {
    public typealias Body = Never
    @_spi(SwiftOpenUIBackend) public let player: AVPlayer?
    @_spi(SwiftOpenUIBackend) public let videoOverlay: VideoOverlay
    public init(player: AVPlayer?, @ViewBuilder videoOverlay: () -> VideoOverlay) {
        self.player = player
        self.videoOverlay = videoOverlay()
    }
    public var body: Never { fatalError("VideoPlayer is a primitive view") }
}

public extension VideoPlayer where VideoOverlay == EmptyView {
    init(player: AVPlayer?) { self.init(player: player) { EmptyView() } }
}
