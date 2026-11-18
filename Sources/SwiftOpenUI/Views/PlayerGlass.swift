import Foundation

/// Overlay controls drawn over video (a player's buttons, menus, title and
/// seek bar). One API on every backend; the SwiftUI backend draws Liquid
/// Glass, this renderer keeps its native look: a dark scrim behind each group
/// with white content, and controls drawn as usual.
public struct PlayerControlGroup<Content: View>: View {
    private let spacing: Double
    private let content: Content

    public init(spacing: Double = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(Color.white)
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }
}

public extension View {
    /// One control (a button, a menu) over video. Native look here.
    func playerControlGlass() -> Self { self }

    /// A non-interactive part of the controls (the seek bar, a label). Native look here.
    func playerSurfaceGlass() -> Self { self }

    /// The title over video, on its own dark scrim here.
    func playerTitleGlass() -> some View {
        padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(Color.white)
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }
}

public extension View {
    /// Controls a player hides after a while (`hidden`): out of sight and not
    /// in the way of pointer input, but still reachable by name and by focus
    /// (renderers keep transparent widgets in the accessibility tree). Same
    /// API as the SwiftUI backend.
    func autoHiddenControls(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1).allowsHitTesting(!hidden)
    }
}
