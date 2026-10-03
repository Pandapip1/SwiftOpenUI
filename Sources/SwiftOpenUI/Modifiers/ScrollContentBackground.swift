/// Whether a scrollable view draws its own background.
///
/// Matches SwiftUI's `scrollContentBackground(_:)`. The default is
/// `.automatic`, meaning the platform draws whatever background it normally
/// would — on GTK that is the theme's view background. `.hidden` suppresses it
/// so whatever is behind the scroll view shows through, which is how an app
/// asks for its content to sit directly on the window background.
public struct ScrollContentBackgroundKey: EnvironmentKey {
    public static let defaultValue: Visibility = .automatic
}

extension EnvironmentValues {
    public var scrollContentBackground: Visibility {
        get { self[ScrollContentBackgroundKey.self] }
        set { self[ScrollContentBackgroundKey.self] = newValue }
    }
}

extension View {
    /// Sets whether scrollable views in this subtree draw their background.
    ///
    /// ```swift
    /// List { ... }
    ///     .scrollContentBackground(.hidden)
    /// ```
    public func scrollContentBackground(_ visibility: Visibility) -> EnvironmentModifierView<Self, Visibility> {
        environment(\.scrollContentBackground, visibility)
    }
}
