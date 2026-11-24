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
        PopoverMenu(onPresentationChange: onPresentationChange, label: label, content: content)
        #else
        Menu(content: content, label: label)
        #endif
    }
}

#if os(iOS)
/// The iOS popover list, in a type internal to this module. SwiftUI's
/// `popover(isPresented:…)` is emitted into its caller, so SwiftUI exports no
/// symbol for its opaque result type: each calling module carries a hidden
/// copy. A public body that calls it directly is copied into client modules
/// by cross-module optimisation (Release), and the copy referenced a
/// descriptor no module exported: the app failed to link. An internal type's
/// body stays here, with this module's copy.
private struct PopoverMenu<Label: View, Content: View>: View {
    let onPresentationChange: @MainActor (Bool) -> Void
    let label: () -> Label
    let content: () -> Content
    @State private var isPresented = false

    var body: some View {
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
    }
}
#endif

#if os(tvOS)
private struct RemoteDefaultFocusKey: EnvironmentKey {
    static var defaultValue: FocusState<Bool>.Binding? { nil }
}

extension EnvironmentValues {
    /// The enclosing `remoteFocusScope`'s default focus.
    fileprivate var remoteDefaultFocus: FocusState<Bool>.Binding? {
        get { self[RemoteDefaultFocusKey.self] }
        set { self[RemoteDefaultFocusKey.self] = newValue }
    }
}
#endif

private struct RemoteFocusScope: ViewModifier {
    let focusesDefault: Bool
    #if os(tvOS)
    @FocusState private var defaultFocused: Bool
    #endif

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .environment(\.remoteDefaultFocus, $defaultFocused)
            // Focus entering the scope, even by the user, lands on the default
            // while `focusesDefault` holds; otherwise only when it first appears.
            .defaultFocus($defaultFocused, true, priority: focusesDefault ? .userInitiated : .automatic)
            .onChange(of: focusesDefault) { _, focuses in if focuses { defaultFocused = true } }
        #else
        content
        #endif
    }
}

private struct RemotePrefersDefaultFocus: ViewModifier {
    #if os(tvOS)
    @Environment(\.remoteDefaultFocus) private var defaultFocus
    #endif
    let prefers: Bool
    @ViewBuilder func body(content: Content) -> some View {
        #if os(tvOS)
        if prefers, let defaultFocus { content.focused(defaultFocus) } else { content }
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
    /// A focus scope for `remotePrefersDefaultFocus` (tvOS). When
    /// `focusingDefault` is true as it appears, or becomes true, focus moves
    /// to the scope's default.
    func remoteFocusScope(focusingDefault: Bool = false) -> some View {
        modifier(RemoteFocusScope(focusesDefault: focusingDefault))
    }
    /// Makes this view the default focus within its `remoteFocusScope` (tvOS).
    func remotePrefersDefaultFocus(_ prefers: Bool) -> some View { modifier(RemotePrefersDefaultFocus(prefers: prefers)) }
}
#endif
