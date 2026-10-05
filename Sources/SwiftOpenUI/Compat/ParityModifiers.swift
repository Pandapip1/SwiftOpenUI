import Foundation

// SwiftUI-shaped modifiers and members that desktop backends accept so SwiftUI source compiles unchanged.
// Where a concept has no desktop equivalent (navigation bar title style, sheet detents, software keyboards,
// pull to refresh) the call is accepted and ignored; each is listed in docs/api/implementation-tracker as Partial.

// MARK: - Font

extension Font {
    private var parts: (size: Double, weight: FontWeight, design: FontDesign) {
        switch self {
        case .custom(let size, let weight, let design): return (size, weight, design)
        default: return (pointSize, .regular, .default)
        }
    }

    /// `.font(.headline.bold())`
    public func bold() -> Font {
        let p = parts
        return .custom(size: p.size, weight: .bold, design: p.design)
    }

    /// `.font(.body.monospaced())`
    public func monospaced() -> Font {
        let p = parts
        return .custom(size: p.size, weight: p.weight, design: .monospaced)
    }

    /// Digits already have fixed width in the fonts the backends use, so this returns the font unchanged.
    public func monospacedDigit() -> Font { self }

    /// Italic is not part of `Font`'s model; returns the font unchanged (use `.italic()` on a view for backends that support it).
    public func italic() -> Font { self }
}

// MARK: - Toolbar placements

extension ToolbarItemPlacement {
    /// Desktop header bars have a leading and a trailing side; iOS placements are mapped onto those.
    public static var topBarLeading: ToolbarItemPlacement { .leading }
    public static var topBarTrailing: ToolbarItemPlacement { .trailing }
    public static var navigation: ToolbarItemPlacement { .leading }
    public static var cancellationAction: ToolbarItemPlacement { .leading }
    public static var confirmationAction: ToolbarItemPlacement { .primaryAction }
    public static var destructiveAction: ToolbarItemPlacement { .trailing }
    public static var automatic: ToolbarItemPlacement { .primaryAction }
    public static var bottomBar: ToolbarItemPlacement { .primaryAction }
    public static var principal: ToolbarItemPlacement { .leading }
    public static var status: ToolbarItemPlacement { .leading }
}

// MARK: - Navigation, lists, presentation

public struct NavigationBarItem {
    public enum TitleDisplayMode: Sendable { case automatic, inline, large }
}

public struct PresentationDetent: Hashable, Sendable {
    private let name: String
    public static let medium = PresentationDetent(name: "medium")
    public static let large = PresentationDetent(name: "large")
    public static func height(_ points: Double) -> PresentationDetent { PresentationDetent(name: "height:\(points)") }
    public static func fraction(_ fraction: Double) -> PresentationDetent { PresentationDetent(name: "fraction:\(fraction)") }
}

public struct AnyTransition: Sendable {
    public static let identity = AnyTransition()
    public static let opacity = AnyTransition()
    public static let slide = AnyTransition()
    public static func move(edge: Edge) -> AnyTransition { AnyTransition() }
    public static func scale(scale: Double = 0, anchor: Alignment = .center) -> AnyTransition { AnyTransition() }
    public static var scale: AnyTransition { AnyTransition() }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition { AnyTransition() }
    public func combined(with other: AnyTransition) -> AnyTransition { self }
}

public enum TextInputAutocapitalization: Sendable {
    case never, words, sentences, characters
}

/// Software-keyboard hint. Accepted for source compatibility; desktop keyboards have no variants.
public enum UIKeyboardType: Sendable {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad
    case emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

extension View {
    public func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> Self { self }

    public func listRowSeparator(_ visibility: Visibility, edges: Edge.Set = .all) -> Self { self }
    public func listRowInsets(_ insets: EdgeInsets?) -> Self { self }
    public func listRowBackground<V: View>(_ background: V?) -> Self { self }

    public func presentationDetents(_ detents: Set<PresentationDetent>) -> Self { self }
    public func presentationDragIndicator(_ visibility: Visibility) -> Self { self }

    public func transition(_ t: AnyTransition) -> Self { self }

    public func textInputAutocapitalization(_ style: TextInputAutocapitalization?) -> Self { self }
    public func autocorrectionDisabled(_ disable: Bool = true) -> Self { self }
    public func keyboardType(_ type: UIKeyboardType) -> Self { self }

    /// Accent color for controls. Backends use the system accent, so this is accepted and ignored.
    public func tint(_ color: Color?) -> Self { self }

    /// Pull to refresh does not exist with a mouse. Accepted and ignored; offer an explicit Refresh button instead.
    public func refreshable(action: @escaping @Sendable () async -> Void) -> Self { self }

    /// Swipe actions have no desktop gesture, so the actions are offered in the row's context menu (right click).
    public func swipeActions<Actions: View>(
        edge: HorizontalEdge = .trailing,
        allowsFullSwipe: Bool = true,
        @ViewBuilder content: () -> Actions
    ) -> some View {
        _ContextMenuView(content: self, menuContent: content())
    }
}


extension Material {
    public static let ultraThinMaterial = Material(kind: .thin)
    public static let ultraThickMaterial = Material(kind: .thick)
    public static let bar = Material(kind: .regular)
}

extension View {
    /// `.background(.red, in: shape)`
    public func background<S: Shape>(_ color: Color, in shape: S) -> BackgroundView<Self, FilledShape<S>> {
        background(shape.fill(color))
    }
}
