#if canImport(SwiftUI)
import SwiftUI

// Remote-control (tvOS Siri Remote) navigation and presented menus. Same API
// as the portable implementation; the platform differences live here.

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
#endif
