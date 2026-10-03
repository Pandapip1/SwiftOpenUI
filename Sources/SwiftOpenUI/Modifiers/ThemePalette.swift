/// Colors sampled from the host platform's theme.
///
/// The shape-style and material approximations are otherwise fixed constants,
/// which look wrong next to a themed desktop: a GTK theme picks its own
/// background, foreground and accent, and a flat guess next to it reads as a
/// mismatched slab. A backend that can see its theme publishes one of these and
/// the approximations derive from it instead.
///
/// Backends that have no theme to report leave it `nil`, and the fixed
/// per-`ColorScheme` constants are used.
public struct ThemePalette: Sendable, Equatable {
    /// The theme's primary text color.
    public var foreground: Color
    /// The window background the content sits on.
    public var windowBackground: Color
    /// The background of a raised surface (a card, a popover, a sidebar row).
    public var cardBackground: Color
    /// The theme's accent color.
    public var accent: Color

    public init(foreground: Color, windowBackground: Color, cardBackground: Color, accent: Color) {
        self.foreground = foreground
        self.windowBackground = windowBackground
        self.cardBackground = cardBackground
        self.accent = accent
    }

}

/// Theme palette key. `nil` means "no themed palette available".
public struct ThemePaletteKey: EnvironmentKey {
    public static let defaultValue: ThemePalette? = nil
}

extension EnvironmentValues {
    public var themePalette: ThemePalette? {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}
