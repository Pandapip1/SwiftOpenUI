#if canImport(SwiftUI)
import SwiftUI
#if os(tvOS)
import UIKit
#endif
@_exported import MediaScrubberLayout

/// The media seek bar: a thick capsule (played and unplayed) split into
/// chapters, the pipeline lanes peeking out below it (video, then audio, per
/// stage), flagged regions peeking out above it, discontinuity ticks, a time
/// preview while hovering or pressing, and live behaviour (the recorded
/// window, LIVE or "behind live", jump to live). Geometry and text come from
/// `ScrubberLayout`, shared with every backend. Same API as the portable
/// implementation.
public struct MediaScrubber: View {
    /// What the bar controls, read by assistive technology ("Playback position").
    private let label: String
    private let content: ScrubberContent
    private let value: Double
    private let onScrub: (Double) -> Void
    private let onScrubEnded: (Double) -> Void
    private let onJumpToLive: (() -> Void)?
    @State private var dragTime: Double?
    @State private var frozenEnd: Double?
    @State private var hoverTime: Double?
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Namespace private var rotorNamespace

    /// `label` is required: a seek bar without a name is unusable with assistive technology.
    public init(_ label: String, content: ScrubberContent, value: Double,
                onScrub: @escaping (Double) -> Void = { _ in },
                onScrubEnded: @escaping (Double) -> Void,
                onJumpToLive: (() -> Void)? = nil) {
        self.label = label
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
                bar(layout, size: geometry.size)
                    .overlay(alignment: .topLeading) { landmarks(layout) }
            }
            .frame(height: barTop + ScrubberLayout.capsuleHeight + laneSpace)
            labels
            if differentiateWithoutColor, !content.lanes.isEmpty {
                // What the lane heights mean, in words.
                Text(ScrubberLayout(content: content, width: 1).legendText).font(.caption2)
            }
        }
        .accessibilityRotor("Chapters") {
            let layout = ScrubberLayout(content: content, width: 1)
            ForEach(content.chapters.indices, id: \.self) { index in
                AccessibilityRotorEntry(Text(layout.chapterAccessibilityLabel(index)), id: "chapter-\(index)", in: rotorNamespace)
            }
        }
        .accessibilityRotor("Flagged segments") {
            let layout = ScrubberLayout(content: content, width: 1)
            ForEach(content.flags.indices, id: \.self) { index in
                AccessibilityRotorEntry(Text(layout.flagAccessibilityLabel(index)), id: "flag-\(index)", in: rotorNamespace)
            }
        }
    }

    /// Chapters and flagged segments as their own elements over the bar, so
    /// the Chapters and Flagged segments rotors reach them. Activating a
    /// chapter seeks to it, and swiping up or down on one steps chapter by
    /// chapter; activating a flagged segment (a sponsor) skips it.
    private func landmarks(_ layout: ScrubberLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(content.chapters.enumerated()), id: \.offset) { index, chapter in
                let x0 = layout.x(for: chapter.range.start)
                Color.clear
                    .frame(width: max(layout.x(for: chapter.range.end) - x0, 1), height: ScrubberLayout.capsuleHeight)
                    .offset(x: x0, y: barTop)
                    .accessibilityElement()
                    .accessibilityLabel(layout.chapterAccessibilityLabel(index))
                    .accessibilityHint("Plays from this chapter")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onScrubEnded(chapter.range.start) }
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: if let start = layout.nextChapterStart(after: value) { onScrubEnded(start) }
                        case .decrement: if let start = layout.previousChapterStart(before: value) { onScrubEnded(start) }
                        @unknown default: break
                        }
                    }
                    .accessibilityRotorEntry(id: "chapter-\(index)", in: rotorNamespace)
            }
            ForEach(Array(content.flags.enumerated()), id: \.offset) { index, flag in
                let x0 = layout.x(for: flag.range.start)
                Color.clear
                    .frame(width: max(layout.x(for: flag.range.end) - x0, 1), height: ScrubberLayout.flagHeight)
                    .offset(x: x0, y: barTop + ScrubberLayout.flagY)
                    .accessibilityElement()
                    .accessibilityLabel(layout.flagAccessibilityLabel(index))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onScrubEnded(min(layout.end, flag.range.end)) }
                    .accessibilityAction(named: "Skip \(flag.title)") { onScrubEnded(min(layout.end, flag.range.end)) }
                    .accessibilityAction(named: "Play \(flag.title)") { onScrubEnded(flag.range.start) }
                    .accessibilityRotorEntry(id: "flag-\(index)", in: rotorNamespace)
            }
        }
        .allowsHitTesting(false)
    }

    /// The bar's drawing: flags, lanes, the capsule's pieces, ticks, the thumb and the preview.
    private func drawing(_ layout: ScrubberLayout, size: CGSize) -> some View {
        let shown = dragTime ?? value
        return ZStack(alignment: .topLeading) {
            // Behind the capsule: flags above, lanes below.
            ForEach(Array(layout.flagRects.enumerated()), id: \.offset) { _, item in
                Rectangle().fill(Self.color(category: item.flag.category))
                    .frame(width: item.range.upperBound - item.range.lowerBound, height: ScrubberLayout.flagHeight)
                    .offset(x: item.range.lowerBound, y: barTop + ScrubberLayout.flagY)
            }
            ForEach(Array(content.lanes.enumerated()), id: \.offset) { index, lane in
                ForEach(Array(layout.laneRects(lane).enumerated()), id: \.offset) { _, item in
                    // Stages differ by height as well as colour.
                    let height = ScrubberLayout.laneHeight * item.stage.heightFraction
                    Rectangle().fill(Self.color(stage: item.stage))
                        .frame(width: item.range.upperBound - item.range.lowerBound, height: height)
                        .offset(x: item.range.lowerBound,
                                y: barTop + layout.laneY(index) + ScrubberLayout.laneHeight - height)
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
                    .offset(x: min(max(layout.x(for: preview) - 30, 0), max(size.width - 90, 0)), y: -18)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    #if os(tvOS)
    /// The remote: one focusable control over the drawing. Select starts
    /// adjusting, left and right then seek, Select keeps the position and
    /// Back restores it; otherwise the arrows move focus as everywhere else.
    private func bar(_ layout: ScrubberLayout, size: CGSize) -> some View {
        drawing(layout, size: size)
            .accessibilityHidden(true)
            .overlay {
                RemoteSeekControl(
                    label: label, value: value, end: layout.end, step: layout.accessibilityStep,
                    describe: { layout.accessibilityValue($0) },
                    nextChapter: { layout.nextChapterStart(after: $0) },
                    previousChapter: { layout.previousChapterStart(before: $0) },
                    skip: { time in
                        layout.flag(at: time).map { (name: "Skip \($0.title)", to: min(layout.end, $0.range.end)) }
                    },
                    onChange: onScrubEnded
                )
            }
    }
    #else
    private func bar(_ layout: ScrubberLayout, size: CGSize) -> some View {
        accessible(interactive(drawing(layout, size: size), layout: layout), layout: layout)
    }

    /// Pointer and touch input.
    private func interactive(_ view: some View, layout: ScrubberLayout) -> some View {
        view
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
    }

    /// The bar as one adjustable element: label, time-based value, 10 s steps, chapter and skip actions.
    private func accessible(_ view: some View, layout: ScrubberLayout) -> some View {
        view
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(layout.accessibilityValue(value))
        .accessibilityAdjustableAction { direction in
            let step = layout.accessibilityStep
            switch direction {
            case .increment: onScrubEnded(min(layout.end, value + step))
            case .decrement: onScrubEnded(max(0, value - step))
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Next chapter") {
            if let start = layout.nextChapterStart(after: value) { onScrubEnded(start) }
        }
        .accessibilityAction(named: "Previous chapter") {
            if let start = layout.previousChapterStart(before: value) { onScrubEnded(start) }
        }
        .accessibilityActions {
            // Only while a flagged segment plays: "Skip Sponsor".
            if let flag = layout.flag(at: value) {
                Button("Skip \(flag.title)") { onScrubEnded(min(layout.end, flag.range.end)) }
            }
        }
    }
    #endif

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

#if canImport(SwiftUI) && !os(tvOS)
/// Pointer and touch: press or drag anywhere, hover for a preview.
private struct ScrubInteraction: ViewModifier {
    let layout: ScrubberLayout
    let value: Double
    let changed: (Double) -> Void
    let ended: (Double) -> Void
    let hover: (Double?) -> Void

    func body(content: Content) -> some View {
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
    }
}
#endif

#if canImport(SwiftUI) && os(tvOS)

/// The seek bar's remote control (tvOS), drawn over the bar and carrying
/// its accessibility. Select enters adjustment mode, left and right seek
/// while adjusting, Select again keeps the position and releases focus
/// movement, and Back restores where adjustment started.
@MainActor
private struct RemoteSeekControl: UIViewRepresentable {
    let label: String
    let value: Double
    let end: Double
    let step: Double
    let describe: (Double) -> String
    let nextChapter: (Double) -> Double?
    let previousChapter: (Double) -> Double?
    let skip: (Double) -> (name: String, to: Double)?
    let onChange: (Double) -> Void

    func makeUIView(context: Context) -> RemoteSeekControlView { RemoteSeekControlView() }

    func updateUIView(_ control: RemoteSeekControlView, context: Context) { control.update(self) }
}

@MainActor
private final class RemoteSeekControlView: UIControl {
    private var model: RemoteSeekControl?
    private var value: Double = 0
    private var adjustmentStartValue: Double?
    private var isCancellingWithMenu = false
    private var isAdjusting = false { didSet { refresh() } }

    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityIdentifier = "playback-seek-control"
        accessibilityTraits = [.adjustable]
        layer.cornerRadius = 8
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update(_ model: RemoteSeekControl) {
        self.model = model
        value = model.value
        accessibilityLabel = model.label
        var actions: [UIAccessibilityCustomAction] = [
            UIAccessibilityCustomAction(name: "Next chapter") { [weak self] _ in
                guard let self, let start = self.model?.nextChapter(self.value) else { return false }
                self.adjust(to: start)
                return true
            },
            UIAccessibilityCustomAction(name: "Previous chapter") { [weak self] _ in
                guard let self, let start = self.model?.previousChapter(self.value) else { return false }
                self.adjust(to: start)
                return true
            },
        ]
        if let skip = model.skip(value) {
            actions.append(UIAccessibilityCustomAction(name: skip.name) { [weak self] _ in
                self?.adjust(to: skip.to)
                return true
            })
        }
        accessibilityCustomActions = actions
        refresh()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if isAdjusting, presses.contains(where: { $0.type == .menu }) {
            if let adjustmentStartValue { adjust(to: adjustmentStartValue) }
            adjustmentStartValue = nil
            isAdjusting = false
            isCancellingWithMenu = true
            return
        }
        guard isAdjusting, let type = presses.first?.type else {
            super.pressesBegan(presses, with: event)
            return
        }
        switch type {
        case .leftArrow: adjust(by: -(model?.step ?? 10))
        case .rightArrow: adjust(by: model?.step ?? 10)
        default: super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if isCancellingWithMenu, presses.contains(where: { $0.type == .menu }) {
            isCancellingWithMenu = false
            return
        }
        if presses.contains(where: { $0.type == .select }) {
            adjustmentStartValue = isAdjusting ? nil : value
            isAdjusting.toggle()
            return
        }
        super.pressesEnded(presses, with: event)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if !isFocused { isAdjusting = false }
        coordinator.addCoordinatedAnimations { self.refresh() }
    }

    override func accessibilityIncrement() { adjust(by: model?.step ?? 10) }
    override func accessibilityDecrement() { adjust(by: -(model?.step ?? 10)) }

    private func adjust(by delta: Double) { adjust(to: value + delta) }

    private func adjust(to proposed: Double) {
        let target = min(max(proposed, 0), model?.end ?? proposed)
        value = target
        model?.onChange(target)
        refresh()
    }

    private func refresh() {
        backgroundColor = isFocused ? UIColor.white.withAlphaComponent(0.18) : .clear
        layer.borderWidth = isAdjusting ? 3 : 0
        layer.borderColor = tintColor.cgColor
        transform = isFocused ? CGAffineTransform(scaleX: 1.03, y: 1.03) : .identity
        let position = model?.describe(value) ?? ""
        accessibilityValue = isAdjusting ? "\(position), adjusting" : position
    }
}
#endif
