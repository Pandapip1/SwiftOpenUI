#if canImport(SwiftUI)
import SwiftUI

/// Overlay controls drawn over video (a player's buttons, menus, title and
/// seek bar). One API on every backend; each renders it its own way:
///
/// - Apple platforms (26 and later): Liquid Glass. Each control is its own
///   glass element and a group merges adjacent ones (`GlassEffectContainer`);
///   there is no scrim behind the group. Glass keeps its content legible over
///   bright and dark video alike, so the content keeps the system's adaptive
///   foreground. tvOS keeps its focus effects: controls are not made
///   interactive glass there, the group sits on glass instead.
/// - Apple platforms before 26: a material behind each group.
/// - Reduce Transparency or Increase Contrast: an opaque background with a
///   border instead of glass or material (`glassBackground(in:interactive:)`),
///   so the video behind never lowers the controls' contrast.
/// - Other renderers: the renderer's native look (a dark scrim behind the group).
public struct PlayerControlGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    private var opaque: Bool { reduceTransparency || contrast == .increased }

    public var body: some View {
        if opaque {
            // Each control carries its own opaque background (playerControlGlass).
            content
        } else if #available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            #if os(tvOS)
            content.padding(.horizontal, 12).padding(.vertical, 9)
                .glassBackground(in: RoundedRectangle(cornerRadius: 16))
            #else
            GlassEffectContainer(spacing: spacing) { content }
            #endif
        } else {
            content.padding(.horizontal, 12).padding(.vertical, 9)
                .glassBackground(in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

public extension View {
    /// One control (a button, a menu) over video: its own glass element.
    func playerControlGlass() -> some View {
        modifier(PlayerControlGlassModifier(interactive: true))
    }

    /// A non-interactive part of the controls (the seek bar, a label) on glass.
    func playerSurfaceGlass() -> some View {
        modifier(PlayerControlGlassModifier(interactive: false))
    }

    /// The title over video, on its own glass.
    func playerTitleGlass() -> some View {
        modifier(PlayerControlGlassModifier(interactive: false))
    }
}

private struct PlayerControlGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let interactive: Bool

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            // Opaque with a border (glassBackground's accessible form), on every OS version.
            content
                .padding(.horizontal, interactive ? 10 : 12)
                .padding(.vertical, 8)
                .glassBackground(in: Capsule(), interactive: interactive)
        } else if #available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            #if os(tvOS)
            content
            #else
            content
                .padding(.horizontal, interactive ? 10 : 12)
                .padding(.vertical, 8)
                .glassBackground(in: Capsule(), interactive: interactive)
            #endif
        } else {
            content
        }
    }
}
#endif
