#if canImport(SwiftUI)
import SwiftUI
@_exported import MediaScrubberLayout

/// The media seek bar: a thick capsule (played and unplayed) split into
/// chapters, the pipeline lanes peeking out below it (video, then audio, per
/// stage), flagged regions peeking out above it, discontinuity ticks, a time
/// preview while hovering or pressing, and live behaviour (the recorded
/// window, LIVE or "behind live", jump to live). Geometry and text come from
/// `ScrubberLayout`, shared with every backend. Same API as the portable
/// implementation.
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

    public var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let layout = ScrubberLayout(content: content, width: geometry.size.width, frozenEnd: frozenEnd)
                let shown = dragTime ?? value
                ZStack(alignment: .topLeading) {
                    // Behind the capsule: flags above, lanes below.
                    ForEach(Array(layout.flagRects.enumerated()), id: \.offset) { _, item in
                        Rectangle().fill(Self.color(category: item.flag.category))
                            .frame(width: item.range.upperBound - item.range.lowerBound, height: ScrubberLayout.flagHeight)
                            .offset(x: item.range.lowerBound, y: barTop + ScrubberLayout.flagY)
                    }
                    ForEach(Array(content.lanes.enumerated()), id: \.offset) { index, lane in
                        ForEach(Array(layout.laneRects(lane).enumerated()), id: \.offset) { _, item in
                            Rectangle().fill(Self.color(stage: item.stage))
                                .frame(width: item.range.upperBound - item.range.lowerBound, height: ScrubberLayout.laneHeight)
                                .offset(x: item.range.lowerBound, y: barTop + layout.laneY(index))
                        }
                    }
                    // The capsule, one piece per chapter.
                    ForEach(Array(layout.capsuleSegments.enumerated()), id: \.offset) { _, piece in
                        let played = min(max(layout.x(for: shown) - piece.lowerBound, 0), piece.upperBound - piece.lowerBound)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.3))
                            Rectangle().fill(Color.white).frame(width: played)
                        }
                        .frame(width: piece.upperBound - piece.lowerBound, height: ScrubberLayout.capsuleHeight)
                        .clipShape(Capsule())
                        .offset(x: piece.lowerBound, y: barTop)
                    }
                    ForEach(Array(layout.discontinuityXs.enumerated()), id: \.offset) { _, x in
                        Rectangle().fill(Color.yellow).frame(width: 2, height: ScrubberLayout.capsuleHeight + 4)
                            .offset(x: x - 1, y: barTop - 2)
                    }
                    Circle().fill(Color.white)
                        .frame(width: dragTime == nil ? 12 : 16, height: dragTime == nil ? 12 : 16)
                        .offset(x: layout.x(for: shown) - (dragTime == nil ? 6 : 8),
                                y: barTop + ScrubberLayout.capsuleHeight / 2 - (dragTime == nil ? 6 : 8))
                    if let preview = dragTime ?? hoverTime {
                        Text(layout.preview(at: preview))
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                            .fixedSize()
                            .offset(x: min(max(layout.x(for: preview) - 30, 0), max(geometry.size.width - 90, 0)), y: -18)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .modifier(ScrubInteraction(
                    layout: layout, value: value,
                    changed: { time in
                        // A live edge that advances mid-scrub must not move the thumb.
                        if frozenEnd == nil { frozenEnd = content.end }
                        dragTime = time
                        onScrub(time)
                    },
                    ended: { time in
                        dragTime = nil
                        frozenEnd = nil
                        onScrubEnded(time)
                    },
                    hover: { hoverTime = $0 }
                ))
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue(layout.accessibilityValue(value))
                .accessibilityAdjustableAction { direction in
                    let step = layout.accessibilityStep
                    switch direction {
                    case .increment: onScrubEnded(min(layout.end, value + step))
                    case .decrement: onScrubEnded(max(0, value - step))
                    @unknown default: break
                    }
                }
            }
            .frame(height: barTop + ScrubberLayout.capsuleHeight + laneSpace)
            labels
        }
    }

    private var barTop: Double { ScrubberLayout.flagHeight + 2 }
    private var laneSpace: Double {
        Double(content.lanes.count) * (ScrubberLayout.laneHeight + ScrubberLayout.laneGap) + 2
    }

    private var labels: some View {
        let layout = ScrubberLayout(content: content, width: 1, frozenEnd: frozenEnd)
        let shown = dragTime ?? value
        return HStack {
            Text(layout.leadingLabel(shown)).monospacedDigit()
            Spacer()
            if content.isLive, let onJumpToLive {
                Button(action: onJumpToLive) {
                    HStack(spacing: 4) {
                        Circle().fill(layout.isAtLiveEdge(shown) ? Color.red : Color.gray).frame(width: 7, height: 7)
                        Text(layout.trailingLabel(shown)).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
                .disabled(layout.isAtLiveEdge(shown))
                .accessibilityLabel(layout.isAtLiveEdge(shown) ? "Live" : "Jump to live")
            } else {
                Text(layout.trailingLabel(shown)).monospacedDigit()
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
        let palette: [Color] = [.yellow, .orange, .pink, .teal, .red, .mint]
        let index = category.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count
        return palette[index]
    }
}
#endif

#if canImport(SwiftUI)
/// Pointer and touch: press or drag anywhere, hover for a preview. tvOS: the
/// focused bar steps with the remote's left and right presses.
private struct ScrubInteraction: ViewModifier {
    let layout: ScrubberLayout
    let value: Double
    let changed: (Double) -> Void
    let ended: (Double) -> Void
    let hover: (Double?) -> Void

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .focusable()
            .onMoveCommand { direction in
                switch direction {
                case .left: ended(max(0, value - layout.accessibilityStep))
                case .right: ended(min(layout.end, value + layout.accessibilityStep))
                default: break
                }
            }
        #else
        content
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { changed(layout.time(atX: $0.location.x)) }
                .onEnded { ended(layout.time(atX: $0.location.x)) })
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hover(layout.time(atX: location.x))
                case .ended: hover(nil)
                }
            }
        #endif
    }
}
#endif
