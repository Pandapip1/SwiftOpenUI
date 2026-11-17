@_exported import MediaScrubberLayout

/// The media seek bar: a thick capsule (played and unplayed) split into
/// chapters, the pipeline lanes peeking out below it (video, then audio, per
/// stage), flagged regions peeking out above it, discontinuity ticks, a time
/// preview while hovering or pressing, and live behaviour (the recorded
/// window, LIVE or "behind live", jump to live). Geometry and text come from
/// `ScrubberLayout`, shared with every backend; the SwiftUI backend has the
/// same API.
public struct MediaScrubber: View {
    private let content: ScrubberContent
    private let value: Double
    private let onScrub: (Double) -> Void
    private let onScrubEnded: (Double) -> Void
    private let onJumpToLive: (() -> Void)?
    @State private var dragTime: Double?
    @State private var frozenEnd: Double?
    @State private var hoverTime: Double?

    public init(content: ScrubberContent, value: Double,
                onScrub: @escaping (Double) -> Void = { _ in },
                onScrubEnded: @escaping (Double) -> Void,
                onJumpToLive: (() -> Void)? = nil) {
        self.content = content
        self.value = value
        self.onScrub = onScrub
        self.onScrubEnded = onScrubEnded
        self.onJumpToLive = onJumpToLive
    }

    private var barTop: Double { ScrubberLayout.flagHeight + 2 }
    private var height: Double {
        barTop + ScrubberLayout.capsuleHeight
            + Double(content.lanes.count) * (ScrubberLayout.laneHeight + ScrubberLayout.laneGap) + 2
    }

    public var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                bar(width: geometry.size.width)
            }
            .frame(height: height)
            labels
        }
    }

    private func bar(width: Double) -> some View {
        let layout = ScrubberLayout(content: content, width: width, frozenEnd: frozenEnd)
        let shown = dragTime ?? value
        let flags = layout.flagRects
        let pieces = layout.capsuleSegments
        let ticks = layout.discontinuityXs
        let laneRects = content.lanes.enumerated().flatMap { index, lane in
            layout.laneRects(lane).map { (index: index, range: $0.range, stage: $0.stage) }
        }
        return ZStack(alignment: .topLeading) {
            ForEach(0..<flags.count) { i in
                Rectangle().fill(Self.color(category: flags[i].flag.category))
                    .frame(width: flags[i].range.upperBound - flags[i].range.lowerBound, height: ScrubberLayout.flagHeight)
                    .offset(x: flags[i].range.lowerBound, y: barTop + ScrubberLayout.flagY)
            }
            ForEach(0..<laneRects.count) { i in
                Rectangle().fill(Self.color(stage: laneRects[i].stage))
                    .frame(width: laneRects[i].range.upperBound - laneRects[i].range.lowerBound, height: ScrubberLayout.laneHeight)
                    .offset(x: laneRects[i].range.lowerBound, y: barTop + layout.laneY(laneRects[i].index))
            }
            ForEach(0..<pieces.count) { i in
                let piece = pieces[i]
                let played = min(max(layout.x(for: shown) - piece.lowerBound, 0), piece.upperBound - piece.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.3))
                    Rectangle().fill(Color.white).frame(width: played, height: ScrubberLayout.capsuleHeight)
                }
                .frame(width: piece.upperBound - piece.lowerBound, height: ScrubberLayout.capsuleHeight)
                .clipShape(Capsule())
                .offset(x: piece.lowerBound, y: barTop)
            }
            ForEach(0..<ticks.count) { i in
                Rectangle().fill(Color.yellow).frame(width: 2, height: ScrubberLayout.capsuleHeight + 4)
                    .offset(x: ticks[i] - 1, y: barTop - 2)
            }
            Circle().fill(Color.white)
                .frame(width: 12, height: 12)
                .offset(x: layout.x(for: shown) - 6, y: barTop + ScrubberLayout.capsuleHeight / 2 - 6)
            if let preview = dragTime ?? hoverTime {
                Text(layout.preview(at: preview))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .background(Color.black.opacity(0.75))
                    .offset(x: min(max(layout.x(for: preview) - 30, 0), max(width - 90, 0)), y: -18)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onDrag(minimumDistance: 0, onChanged: { drag in
            // A live edge that advances mid-scrub must not move the thumb.
            if frozenEnd == nil { frozenEnd = content.end }
            let time = layout.time(atX: drag.location.x)
            dragTime = time
            onScrub(time)
        }, onEnded: { drag in
            let time = layout.time(atX: drag.location.x)
            dragTime = nil
            frozenEnd = nil
            onScrubEnded(time)
        })
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hoverTime = layout.time(atX: Double(location.x))
            case .ended: hoverTime = nil
            }
        }
        .accessibilityLabel("Playback position")
        .accessibilityValue(layout.accessibilityValue(value))
    }

    private var labels: some View {
        let layout = ScrubberLayout(content: content, width: 1, frozenEnd: frozenEnd)
        let shown = dragTime ?? value
        let atEdge = layout.isAtLiveEdge(shown)
        return HStack {
            Text(layout.leadingLabel(shown))
            Spacer()
            if content.isLive, let onJumpToLive {
                Button(atEdge ? "● LIVE" : "○ \(layout.trailingLabel(shown))", action: onJumpToLive)
                    .disabled(atEdge)
                    .accessibilityLabel(atEdge ? "Live" : "Jump to live")
            } else {
                Text(layout.trailingLabel(shown))
            }
        }
        .font(.caption)
    }

    static func color(stage: ScrubberStage) -> Color {
        switch stage {
        case .inFlight: Color.white.opacity(0.35)
        case .downloaded: Color.blue
        case .processed: Color.purple
        case .ready: Color.green
        }
    }

    static func color(category: String) -> Color {
        let palette: [Color] = [.yellow, .orange, .pink, .teal, .red, .green]
        let index = category.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count
        return palette[index]
    }
}
