/// Minimal SwiftUI-shaped hierarchical styles and materials.
///
/// SwiftUI's ShapeStyle protocol machinery is large; these are concrete
/// types with color approximations, enough for `.foregroundStyle(.secondary)`
/// and `.background(.regularMaterial, in: shape)` call sites to compile and
/// render acceptably. Backed by flat colors (no blur/vibrancy) — recorded in
/// the parity matrix as approximations.
///
/// The approximations are scheme-dependent. They used to be light-mode
/// constants unconditionally, which made `.primary` pure black and the
/// materials near-white on a dark desktop — black text on a dark GTK
/// background, and glaring white panels. Each style now resolves against the
/// current `colorScheme`.
public struct HierarchicalShapeStyle: Sendable, Equatable {
    public enum Level: Sendable, Equatable { case primary, secondary, tertiary, quaternary }
    public let level: Level

    public static let primary = HierarchicalShapeStyle(level: .primary)
    public static let secondary = HierarchicalShapeStyle(level: .secondary)
    public static let tertiary = HierarchicalShapeStyle(level: .tertiary)
    public static let quaternary = HierarchicalShapeStyle(level: .quaternary)

    /// Flat-color approximation of the hierarchical style, for an explicit scheme.
    public func approximatedColor(for scheme: ColorScheme) -> Color {
        switch (level, scheme) {
        case (.primary, .light):    return Color(red: 0.00, green: 0.00, blue: 0.00)
        case (.secondary, .light):  return Color(red: 0.45, green: 0.45, blue: 0.47)
        case (.tertiary, .light):   return Color(red: 0.60, green: 0.60, blue: 0.62)
        case (.quaternary, .light): return Color(red: 0.92, green: 0.92, blue: 0.94)
        case (.primary, .dark):     return Color(red: 1.00, green: 1.00, blue: 1.00)
        case (.secondary, .dark):   return Color(red: 0.64, green: 0.64, blue: 0.66)
        case (.tertiary, .dark):    return Color(red: 0.45, green: 0.45, blue: 0.47)
        case (.quaternary, .dark):  return Color(red: 0.26, green: 0.26, blue: 0.28)
        }
    }

    /// Flat-color approximation resolved against the current color scheme.
    ///
    /// Read at view-body build time, which runs inside a render pass, so the
    /// render-time environment is the one in effect. Outside a render pass this
    /// falls back to `ColorSchemeKey.defaultValue`.
    public var approximatedColor: Color {
        approximatedColor(for: getCurrentEnvironment().colorScheme)
    }
}

public struct Material: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case regular, thin, thick }
    public let kind: Kind

    public static let regularMaterial = Material(kind: .regular)
    public static let thinMaterial = Material(kind: .thin)
    public static let thickMaterial = Material(kind: .thick)

    /// Flat-color approximation (no translucency/blur), for an explicit scheme.
    public func approximatedColor(for scheme: ColorScheme) -> Color {
        switch (kind, scheme) {
        case (.regular, .light): return Color(red: 0.97, green: 0.97, blue: 0.98)
        case (.thin, .light):    return Color(red: 0.98, green: 0.98, blue: 0.99)
        case (.thick, .light):   return Color(red: 0.94, green: 0.94, blue: 0.95)
        case (.regular, .dark):  return Color(red: 0.16, green: 0.16, blue: 0.17)
        case (.thin, .dark):     return Color(red: 0.20, green: 0.20, blue: 0.21)
        case (.thick, .dark):    return Color(red: 0.11, green: 0.11, blue: 0.12)
        }
    }

    /// Flat-color approximation resolved against the current color scheme.
    public var approximatedColor: Color {
        approximatedColor(for: getCurrentEnvironment().colorScheme)
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
