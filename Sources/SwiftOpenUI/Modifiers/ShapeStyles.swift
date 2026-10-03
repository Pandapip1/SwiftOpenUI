/// Minimal SwiftUI-shaped hierarchical styles and materials.
///
/// SwiftUI's ShapeStyle protocol machinery is large; these are concrete
/// types with color approximations, enough for `.foregroundStyle(.secondary)`
/// and `.background(.regularMaterial, in: shape)` call sites to compile and
/// render acceptably. Backed by flat colors (no blur/vibrancy) — recorded in
/// the parity matrix as approximations.
public struct HierarchicalShapeStyle: Sendable, Equatable {
    public enum Level: Sendable, Equatable { case primary, secondary, tertiary, quaternary }
    public let level: Level

    public static let primary = HierarchicalShapeStyle(level: .primary)
    public static let secondary = HierarchicalShapeStyle(level: .secondary)
    public static let tertiary = HierarchicalShapeStyle(level: .tertiary)
    public static let quaternary = HierarchicalShapeStyle(level: .quaternary)

    /// The opacity this tier applies to the label color, matching UIKit's
    /// label / secondaryLabel / tertiaryLabel / quaternaryLabel.
    public var opacity: Double {
        switch level {
        case .primary:    return 1.00
        case .secondary:  return 0.60
        case .tertiary:   return 0.30
        case .quaternary: return 0.18
        }
    }

    /// Flat-color approximation for an explicit scheme, used when no backend
    /// has published a theme palette.
    ///
    /// SwiftUI fades the *label* color rather than mixing toward a particular
    /// background, so the result composites correctly whether it lands on the
    /// window, a card or a list. Mixing toward one chosen background would be
    /// wrong everywhere else.
    public func approximatedColor(for scheme: ColorScheme) -> Color {
        let label: Color = scheme == .dark
            ? Color(red: 1, green: 1, blue: 1)
            : Color(red: 0, green: 0, blue: 0)
        return label.opacity(opacity)
    }

    /// Resolved against the host theme when a backend publishes one, and
    /// against the per-scheme label color otherwise.
    ///
    /// Read at view-body build time, which runs inside a render pass, so the
    /// render-time environment is the one in effect.
    public var approximatedColor: Color {
        let env = getCurrentEnvironment()
        guard let palette = env.themePalette else {
            return approximatedColor(for: env.colorScheme)
        }
        return palette.foreground.opacity(opacity)
    }
}

public struct Material: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case regular, thin, thick }
    public let kind: Kind

    public static let regularMaterial = Material(kind: .regular)
    public static let thinMaterial = Material(kind: .thin)
    public static let thickMaterial = Material(kind: .thick)

    /// How opaque this material is. SwiftUI's materials run from ultraThin to
    /// ultraThick by how much of the backdrop they let through; without blur,
    /// opacity over the real backdrop is the closest honest approximation.
    public var opacity: Double {
        switch kind {
        case .thin:    return 0.65
        case .regular: return 0.85
        case .thick:   return 1.00
        }
    }

    /// Flat-color approximation for an explicit scheme, used when no backend
    /// has published a theme palette.
    public func approximatedColor(for scheme: ColorScheme) -> Color {
        let base: Color = scheme == .dark
            ? Color(red: 0.16, green: 0.16, blue: 0.17)
            : Color(red: 0.97, green: 0.97, blue: 0.98)
        return base.opacity(opacity)
    }

    /// Resolved against the host theme when a backend publishes one.
    ///
    /// Materials stand in for raised, translucent surfaces, and the theme's
    /// card background is the surface it defines for exactly that.
    public var approximatedColor: Color {
        let env = getCurrentEnvironment()
        guard let palette = env.themePalette else {
            return approximatedColor(for: env.colorScheme)
        }
        return palette.cardBackground.opacity(opacity)
    }
}

extension View {
    /// `.background(.regularMaterial, in: shape)` — approximated as a flat
    /// shape fill behind the content.
    public func background<S: Shape>(_ material: Material, in shape: S) -> BackgroundView<Self, FilledShape<S>> {
        background(shape.fill(material.approximatedColor))
    }

    /// `.background(.quaternary, in: shape)` — approximated as a flat
    /// shape fill behind the content.
    public func background<S: Shape>(_ style: HierarchicalShapeStyle, in shape: S) -> BackgroundView<Self, FilledShape<S>> {
        background(shape.fill(style.approximatedColor))
    }
}
