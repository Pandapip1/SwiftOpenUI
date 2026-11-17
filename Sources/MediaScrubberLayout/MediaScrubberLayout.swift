import Foundation

// Geometry, text and accessibility for `MediaScrubber`, shared by every
// renderer: the seek bar's behaviour is decided here once, and each backend
// only draws it and feeds it gestures.

/// A pipeline stage, for the lane colours under the capsule.
public enum ScrubberStage: Int, Sendable, Hashable, Comparable, CaseIterable {
    /// Being fetched now.
    case inFlight
    /// The original bytes are local.
    case downloaded
    /// A later stage (transcoding) has produced its output.
    case processed
    /// Final and ready to play.
    case ready

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct ScrubberRange: Sendable, Hashable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double) { self.start = start; self.end = max(start, end) }
}

public struct ScrubberChapter: Sendable, Hashable {
    public var range: ScrubberRange
    public var title: String
    public init(start: Double, end: Double, title: String) { range = ScrubberRange(start: start, end: end); self.title = title }
}

/// One pipeline lane (video or audio): possibly non-contiguous ranges per stage.
public struct ScrubberLane: Sendable, Hashable {
    public var label: String
    public var segments: [Segment]
    public struct Segment: Sendable, Hashable {
        public var range: ScrubberRange
        public var stage: ScrubberStage
        public init(range: ScrubberRange, stage: ScrubberStage) { self.range = range; self.stage = stage }
    }
    public init(label: String, segments: [Segment]) { self.label = label; self.segments = segments }
}

/// A flagged region (e.g. a SponsorBlock category), drawn above the capsule.
public struct ScrubberFlag: Sendable, Hashable {
    public var range: ScrubberRange
    public var category: String
    public var title: String
    public init(start: Double, end: Double, category: String, title: String) {
        range = ScrubberRange(start: start, end: end); self.category = category; self.title = title
    }
}

/// A live stream's recorded window.
public struct ScrubberLive: Sendable, Hashable {
    /// The live edge: the end of the recorded window (recording time, seconds).
    public var edge: Double
    /// When recording time 0 happened, for wall-clock labels.
    public var startedAt: Date?
    /// The stream has ended: the bar becomes an ordinary VOD bar.
    public var hasEnded: Bool
    public init(edge: Double, startedAt: Date? = nil, hasEnded: Bool = false) {
        self.edge = edge; self.startedAt = startedAt; self.hasEnded = hasEnded
    }
}

/// Everything a seek bar shows besides the position.
public struct ScrubberContent: Sendable, Hashable {
    public var duration: Double
    public var chapters: [ScrubberChapter]
    public var lanes: [ScrubberLane]
    public var flags: [ScrubberFlag]
    /// Discontinuities (ad breaks, encoder restarts), in seconds.
    public var discontinuities: [Double]
    public var live: ScrubberLive?

    public init(duration: Double, chapters: [ScrubberChapter] = [], lanes: [ScrubberLane] = [],
                flags: [ScrubberFlag] = [], discontinuities: [Double] = [], live: ScrubberLive? = nil) {
        self.duration = duration; self.chapters = chapters; self.lanes = lanes
        self.flags = flags; self.discontinuities = discontinuities; self.live = live
    }

    /// Live and still growing.
    public var isLive: Bool { live.map { !$0.hasEnded } ?? false }
    /// The seekable end: the live edge, or the duration.
    public var end: Double { live?.edge ?? duration }
}

public struct ScrubberLayout: Sendable {
    public static let capsuleHeight: Double = 8
    public static let laneHeight: Double = 3
    public static let laneGap: Double = 1
    public static let flagHeight: Double = 4
    public static let chapterGap: Double = 3
    /// How close to the live edge still counts as live.
    public static let liveTolerance: Double = 3

    public let content: ScrubberContent
    public let width: Double
    /// The end used for positions. While the user scrubs a live stream the
    /// caller freezes it, so the thumb does not move as the edge advances.
    public let end: Double

    public init(content: ScrubberContent, width: Double, frozenEnd: Double? = nil) {
        self.content = content
        self.width = max(width, 1)
        self.end = max(frozenEnd ?? content.end, 0.001)
    }

    // MARK: geometry

    public func x(for time: Double) -> Double { min(max(time / end, 0), 1) * width }
    public func time(atX x: Double) -> Double { min(max(x / width, 0), 1) * end }

    /// The capsule's pieces: one per chapter, with small gaps between them.
    public var capsuleSegments: [ClosedRange<Double>] {
        let boundaries = content.chapters.map(\.range.start).filter { $0 > 0 && $0 < end }.sorted()
        guard !boundaries.isEmpty else { return [0...width] }
        var pieces: [ClosedRange<Double>] = []
        var start = 0.0
        for boundary in boundaries {
            let x = self.x(for: boundary)
            let pieceEnd = max(start, x - Self.chapterGap / 2)
            pieces.append(start...pieceEnd)
            start = min(width, x + Self.chapterGap / 2)
        }
        pieces.append(start...width)
        return pieces.filter { $0.upperBound - $0.lowerBound > 0.5 }
    }

    /// A lane's coloured pieces, in x.
    public func laneRects(_ lane: ScrubberLane) -> [(range: ClosedRange<Double>, stage: ScrubberStage)] {
        lane.segments.compactMap { segment in
            let x0 = x(for: segment.range.start), x1 = x(for: segment.range.end)
            return x1 > x0 ? (x0...x1, segment.stage) : nil
        }
    }

    public var flagRects: [(range: ClosedRange<Double>, flag: ScrubberFlag)] {
        content.flags.compactMap { flag in
            let x0 = x(for: flag.range.start), x1 = x(for: flag.range.end)
            return x1 > x0 ? (x0...max(x1, x0 + 2), flag) : nil
        }
    }

    public var discontinuityXs: [Double] { content.discontinuities.filter { $0 > 0 && $0 < end }.map { x(for: $0) } }

    /// Vertical offsets from the capsule's top: lanes peek out below it,
    /// flags above it, both behind it.
    public func laneY(_ index: Int) -> Double {
        Self.capsuleHeight - 1 + Double(index) * (Self.laneHeight + Self.laneGap)
    }
    public static let flagY: Double = -flagHeight + 1

    // MARK: text

    public func chapter(at time: Double) -> ScrubberChapter? {
        content.chapters.last { $0.range.start <= time && time < max($0.range.end, $0.range.start + 0.001) }
            ?? content.chapters.last { $0.range.start <= time }
    }

    public func isAtLiveEdge(_ time: Double) -> Bool {
        content.isLive && end - time <= Self.liveTolerance
    }

    /// The label at the start of the bar: elapsed time, or for live the
    /// time from the start of the recording (or its wall-clock time).
    public func leadingLabel(_ time: Double) -> String {
        if content.isLive, let startedAt = content.live?.startedAt {
            return Self.clock(startedAt.addingTimeInterval(time))
        }
        return Self.timeText(time)
    }

    /// The label at the end: the duration (VOD), or live status.
    public func trailingLabel(_ time: Double) -> String {
        guard content.isLive else { return Self.timeText(end) }
        return isAtLiveEdge(time) ? "LIVE" : "−\(Self.timeText(end - time)) behind live"
    }

    /// The preview shown while hovering or pressing.
    public func preview(at time: Double) -> String {
        let label = content.isLive ? "−\(Self.timeText(max(end - time, 0)))" : Self.timeText(time)
        guard let chapter = chapter(at: time), !chapter.title.isEmpty else { return label }
        return "\(label) · \(chapter.title)"
    }

    /// What assistive technology reads for the bar.
    public func accessibilityValue(_ time: Double) -> String {
        var parts: [String] = []
        if content.isLive {
            parts.append(isAtLiveEdge(time) ? "Live" : "\(Self.spokenTime(end - time)) behind live")
        } else {
            parts.append("\(Self.spokenTime(time)) of \(Self.spokenTime(end))")
        }
        if let chapter = chapter(at: time), !chapter.title.isEmpty { parts.append("chapter \(chapter.title)") }
        if let flag = content.flags.first(where: { $0.range.start <= time && time < $0.range.end }) {
            parts.append("in \(flag.title)")
        }
        for lane in content.lanes {
            let ready = lane.segments.filter { $0.stage >= .downloaded }.map(\.range)
            guard !ready.isEmpty else { parts.append("\(lane.label) not downloaded yet"); continue }
            let spans = ready.prefix(3).map { "\(Self.spokenTime($0.start)) to \(Self.spokenTime($0.end))" }
            parts.append("\(lane.label) downloaded \(spans.joined(separator: ", "))" + (ready.count > 3 ? " and more" : ""))
        }
        if !content.flags.isEmpty {
            parts.append("\(content.flags.count) flagged segment" + (content.flags.count == 1 ? "" : "s"))
        }
        return parts.joined(separator: ". ")
    }

    /// The step for one adjustable increment.
    public var accessibilityStep: Double { min(30, max(5, end / 100)) }

    public static func timeText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func spokenTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour" + (h == 1 ? "" : "s")) }
        if m > 0 { parts.append("\(m) minute" + (m == 1 ? "" : "s")) }
        if s > 0 || parts.isEmpty { parts.append("\(s) second" + (s == 1 ? "" : "s")) }
        return parts.joined(separator: " ")
    }

    static func clock(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%d:%02d:%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
    }
}
