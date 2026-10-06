/// Hosts arbitrary content inside the window's own title bar / header bar,
/// for the toplevel window specifically — not a secondary window, sheet or
/// popup. Neither SwiftUI nor SwiftOpenUI has a built-in primitive for this
/// (apps that need it, like Safari putting its tab strip there, build it
/// against each platform's native window chrome), so this is a small,
/// deliberately narrow one: one title-bar-hosted view per window content
/// tree, resolved by whichever window-rendering backend hosts it.
public struct WindowTitleBarModifier<Content: View, TitleBar: View>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let titleBar: TitleBar
    public var body: Never { fatalError() }
}

extension View {
    /// Marks `titleBar` as this content's window title bar. The backend
    /// that renders the toplevel window (`WindowGroup`/`Window`) looks for
    /// this the same way it already looks for a `NavigationStack`'s header
    /// bar — outermost claim wins, so apply this once, near the root of
    /// what a window scene renders.
    public func windowTitleBar<T: View>(@ViewBuilder _ titleBar: () -> T) -> WindowTitleBarModifier<Self, T> {
        WindowTitleBarModifier(content: self, titleBar: titleBar())
    }
}
