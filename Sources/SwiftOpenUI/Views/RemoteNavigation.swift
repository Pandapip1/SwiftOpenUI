// Remote-control (tvOS Siri Remote) navigation and presented menus, with one
// API on every backend. Renderers without a focus-driven remote (GTK and the
// other portable renderers) render the plain control and ignore the focus
// modifiers; the SwiftUI backend implements them where the platform needs them.

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

    public var body: some View {
        Slider(value: Binding(get: { value }, set: { onChange($0) }), in: range)
    }
}

/// An invisible, focusable area that brings hidden controls back when the
/// remote is used (tvOS). Nothing elsewhere: pointers and touch reveal them.
public struct RemoteRevealTarget: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View { EmptyView() }
}

/// A menu that reports when it is open, so the caller can keep surrounding
/// chrome visible meanwhile. A popover list on iOS (where a system menu
/// cannot report that); the platform menu elsewhere.
public struct PresentationMenu<Label: View, Content: View>: View {
    private let onPresentationChange: @MainActor (Bool) -> Void
    private let label: () -> Label
    private let content: () -> Content

    public init(onPresentationChange: @escaping @MainActor (Bool) -> Void = { _ in },
                @ViewBuilder content: @escaping () -> Content,
                @ViewBuilder label: @escaping () -> Label) {
        self.onPresentationChange = onPresentationChange
        self.label = label
        self.content = content
    }

    public var body: some View {
        Menu(content: content, label: label)
    }
}

extension View {
    /// Groups controls for remote focus movement (tvOS focus section).
    public func remoteFocusSection() -> Self { self }
    /// Keeps a view out of remote focus (tvOS).
    public func remoteNonFocusable() -> Self { self }
    /// Runs `action` on a remote direction press (tvOS).
    public func onRemoteMove(perform action: @escaping () -> Void) -> Self { self }
    /// A focus scope for `remotePrefersDefaultFocus` (tvOS).
    public func remoteFocusScope() -> Self { self }
    /// Makes this view the default focus within its `remoteFocusScope` (tvOS).
    public func remotePrefersDefaultFocus(_ prefers: Bool) -> Self { self }
}
