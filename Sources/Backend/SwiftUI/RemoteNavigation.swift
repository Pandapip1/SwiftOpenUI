#if canImport(SwiftUI)
import SwiftUI
#if os(tvOS)
import UIKit
#endif

// Remote-control (tvOS Siri Remote) navigation and presented menus. Same API
// as the portable implementation; the platform differences live here.

/// A seek slider: the native slider, or on tvOS a focusable control that
/// Select puts into adjustment mode and the remote's arrows move.
public struct ScrubSlider: View {
    private let value: Double
    private let range: ClosedRange<Double>
    private let onChange: (Double) -> Void

    public init(value: Double, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) {
        self.value = value
        self.range = range
        self.onChange = onChange
    }

    @ViewBuilder
    public var body: some View {
        #if os(tvOS)
        TVRemoteSlider(value: value, range: range, onChange: onChange)
        #else
        Slider(value: Binding(get: { value }, set: { onChange($0) }), in: range)
        #endif
    }
}

/// An invisible, focusable area that brings hidden controls back when the
/// remote is used (tvOS). Nothing elsewhere: pointers and touch reveal them.
public struct RemoteRevealTarget: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) { self.action = action }

    @ViewBuilder
    public var body: some View {
        #if os(tvOS)
        Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable().focusEffectDisabled().accessibilityLabel("Show playback controls")
            .onTapGesture { action() }.onMoveCommand { _ in action() }
        #else
        EmptyView()
        #endif
    }
}

/// A menu that reports when it is open, so the caller can keep surrounding
/// chrome visible meanwhile. A popover list on iOS (where a system menu
/// cannot report that); the platform menu elsewhere.
public struct PresentationMenu<Label: View, Content: View>: View {
    private let onPresentationChange: @MainActor (Bool) -> Void
    private let label: () -> Label
    private let content: () -> Content
    @State private var isPresented = false

    public init(onPresentationChange: @escaping @MainActor (Bool) -> Void = { _ in },
                @ViewBuilder content: @escaping () -> Content,
                @ViewBuilder label: @escaping () -> Label) {
        self.onPresentationChange = onPresentationChange
        self.label = label
        self.content = content
    }

    @ViewBuilder
    public var body: some View {
        #if os(iOS)
        Button { isPresented = true } label: { label() }
            .popover(isPresented: $isPresented) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) { content() }
                        .buttonStyle(.plain)
                        .padding()
                }
                .onTapGesture { isPresented = false }
                .presentationCompactAdaptation(.popover)
            }
            .onChange(of: isPresented) { _, presented in onPresentationChange(presented) }
            .onDisappear { if isPresented { onPresentationChange(false) } }
        #else
        Menu(content: content, label: label)
        #endif
    }
}

private struct RemoteFocusNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    fileprivate var remoteFocusNamespace: Namespace.ID? {
        get { self[RemoteFocusNamespaceKey.self] }
        set { self[RemoteFocusNamespaceKey.self] = newValue }
    }
}

private struct RemoteFocusScope: ViewModifier {
    @Namespace private var namespace
    func body(content: Content) -> some View {
        #if os(tvOS)
        content.focusScope(namespace).environment(\.remoteFocusNamespace, namespace)
        #else
        content
        #endif
    }
}

private struct RemotePrefersDefaultFocus: ViewModifier {
    @Environment(\.remoteFocusNamespace) private var namespace
    let prefers: Bool
    @ViewBuilder func body(content: Content) -> some View {
        #if os(tvOS)
        if let namespace { content.prefersDefaultFocus(prefers, in: namespace) } else { content }
        #else
        content
        #endif
    }
}

private struct RemoteFocusSection: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if os(tvOS)
        content.focusSection()
        #else
        content
        #endif
    }
}

private struct RemoteNonFocusable: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if os(tvOS)
        content.focusable(false)
        #else
        content
        #endif
    }
}

private struct RemoteMove: ViewModifier {
    let action: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        #if os(tvOS)
        content.onMoveCommand { _ in action() }
        #else
        content
        #endif
    }
}

public extension View {
    /// Groups controls for remote focus movement (tvOS focus section).
    func remoteFocusSection() -> some View { modifier(RemoteFocusSection()) }
    /// Keeps a view out of remote focus (tvOS).
    func remoteNonFocusable() -> some View { modifier(RemoteNonFocusable()) }
    /// Runs `action` on a remote direction press (tvOS).
    func onRemoteMove(perform action: @escaping () -> Void) -> some View { modifier(RemoteMove(action: action)) }
    /// A focus scope for `remotePrefersDefaultFocus` (tvOS).
    func remoteFocusScope() -> some View { modifier(RemoteFocusScope()) }
    /// Makes this view the default focus within its `remoteFocusScope` (tvOS).
    func remotePrefersDefaultFocus(_ prefers: Bool) -> some View { modifier(RemotePrefersDefaultFocus(prefers: prefers)) }
}

#if os(tvOS)
/// A focusable slider for the Siri Remote. Select enters adjustment mode,
/// directional presses seek while selected, and Select again releases focus
/// movement so the user can navigate to the surrounding player controls.
@MainActor
private struct TVRemoteSlider: UIViewRepresentable {
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    func makeUIView(context: Context) -> TVRemoteSliderControl {
        TVRemoteSliderControl()
    }

    func updateUIView(_ control: TVRemoteSliderControl, context: Context) {
        control.update(value: value, range: range, onChange: onChange)
    }
}

@MainActor
private final class TVRemoteSliderControl: UIControl {
    private let progress = UIProgressView(progressViewStyle: .default)
    private var value: Double = 0
    private var range: ClosedRange<Double> = 0...1
    private var onChange: ((Double) -> Void)?
    private var adjustmentStartValue: Double?
    private var isCancellingWithMenu = false
    private var isAdjusting = false { didSet { refreshAppearance() } }

    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityIdentifier = "playback-seek-control"
        accessibilityLabel = "Playback position"
        accessibilityTraits = [.adjustable]
        progress.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progress)
        NSLayoutConstraint.activate([
            progress.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            progress.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            progress.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        layer.cornerRadius = 12
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update(value: Double, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) {
        self.value = value
        self.range = range
        self.onChange = onChange
        let length = range.upperBound - range.lowerBound
        progress.progress = length > 0 ? Float((value - range.lowerBound) / length) : 0
        accessibilityValue = "\(time(value)) of \(time(range.upperBound))\(isAdjusting ? ", adjusting" : "")"
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
        case .leftArrow: adjust(by: -step)
        case .rightArrow: adjust(by: step)
        default: super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if isCancellingWithMenu, presses.contains(where: { $0.type == .menu }) {
            isCancellingWithMenu = false
            return
        }
        if presses.contains(where: { $0.type == .select }) {
            if isAdjusting {
                adjustmentStartValue = nil
                isAdjusting = false
            } else {
                adjustmentStartValue = value
                isAdjusting = true
            }
            return
        }
        super.pressesEnded(presses, with: event)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if !isFocused { isAdjusting = false }
        coordinator.addCoordinatedAnimations { self.refreshAppearance() }
    }

    override func accessibilityIncrement() { adjust(by: step) }
    override func accessibilityDecrement() { adjust(by: -step) }

    private var step: Double { min(30, max(5, (range.upperBound - range.lowerBound) / 100)) }

    private func adjust(by delta: Double) {
        adjust(to: value + delta)
    }

    private func adjust(to proposedValue: Double) {
        let target = min(max(proposedValue, range.lowerBound), range.upperBound)
        value = target
        onChange?(target)
        update(value: target, range: range, onChange: onChange ?? { _ in })
    }

    private func refreshAppearance() {
        progress.progressTintColor = isAdjusting ? tintColor : .white
        backgroundColor = isFocused ? UIColor.white.withAlphaComponent(0.18) : .clear
        transform = isFocused ? CGAffineTransform(scaleX: 1.03, y: 1.03) : .identity
        accessibilityValue = "\(time(value)) of \(time(range.upperBound))\(isAdjusting ? ", adjusting" : "")"
    }

    private func time(_ value: Double) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
#endif
#endif
