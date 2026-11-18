import Foundation

/// SwiftUI's accessibility API, for the portable renderers.
///
/// The SwiftUI backend is SwiftUI itself, so these are the same names and
/// shapes an app uses there. Here each one is a wrapper the renderer maps to
/// its platform's accessibility layer:
///
/// - GTK4 (AT-SPI through `GtkAccessible`): label → `PROPERTY_LABEL`, value →
///   `PROPERTY_VALUE_TEXT`, hint → `PROPERTY_DESCRIPTION`, hidden →
///   `STATE_HIDDEN`, `.isSelected` → `STATE_SELECTED`, `.isModal` →
///   `PROPERTY_MODAL`, `.isHeader` → a `HEADING` container, `.isButton` → a
///   `BUTTON` container. Announcements use `gtk_accessible_announce`.
/// - Other renderers pass the content through until they implement them.
///
/// `.accessibilityIdentifier(_:)` names a view for UI tests and has no
/// effect on what assistive technology presents.
extension View {
    public func accessibilityIdentifier(_ identifier: String) -> AccessibilityAttributeView<Self> {
        AccessibilityAttributeView(content: self, attribute: .identifier(identifier))
    }
}

public struct AllowsHitTestingView<Content: View>: View {
    public typealias Body = Never
    public let content: Content
    public let allowsHitTesting: Bool
    public var body: Never { fatalError("AllowsHitTestingView is a primitive view") }
}

extension View {
    public func allowsHitTesting(_ enabled: Bool) -> AllowsHitTestingView<Self> {
        AllowsHitTestingView(content: self, allowsHitTesting: enabled)
    }
}

/// Wrapper produced by `.accessibilityLabel(_:)`. Renders its content
/// unchanged; a backend may attach the label to the content's
/// accessibility element.
///
/// - GTK4: sets `GTK_ACCESSIBLE_PROPERTY_LABEL` on the content's widget
///   so screen readers announce the label instead of the raw contents
///   (e.g. an icon's symbol name).
/// - Win32 / other backends: currently pass through via `body` (parity
///   matrix note) — inert until a backend implements it.
///
/// Reconcile-safe: the label is represented in the GTK4 descriptor tree
/// (kind `.widgetProperty`), so a *changed* label is not silently reused —
/// it forces a full rebuild whose create path re-applies the new label.
public struct AccessibilityLabelView<Content: View>: View {
    public let content: Content
    public let label: String

    public var body: some View { content }
}

protocol _AccessibilityLabelProvider {
    var _accessibilityLabel: String { get }
}

extension AccessibilityLabelView: _AccessibilityLabelProvider {
    var _accessibilityLabel: String { label }
}

// MARK: - Traits

/// What kind of element a view is to assistive technology, and its state.
/// The same option set as SwiftUI's.
public struct AccessibilityTraits: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let isButton = AccessibilityTraits(rawValue: 1 << 0)
    public static let isHeader = AccessibilityTraits(rawValue: 1 << 1)
    public static let isSelected = AccessibilityTraits(rawValue: 1 << 2)
    public static let isLink = AccessibilityTraits(rawValue: 1 << 3)
    public static let isSearchField = AccessibilityTraits(rawValue: 1 << 4)
    public static let isImage = AccessibilityTraits(rawValue: 1 << 5)
    public static let playsSound = AccessibilityTraits(rawValue: 1 << 6)
    public static let isKeyboardKey = AccessibilityTraits(rawValue: 1 << 7)
    public static let isStaticText = AccessibilityTraits(rawValue: 1 << 8)
    public static let isSummaryElement = AccessibilityTraits(rawValue: 1 << 9)
    public static let updatesFrequently = AccessibilityTraits(rawValue: 1 << 10)
    public static let startsMediaSession = AccessibilityTraits(rawValue: 1 << 11)
    public static let allowsDirectInteraction = AccessibilityTraits(rawValue: 1 << 12)
    public static let causesPageTurn = AccessibilityTraits(rawValue: 1 << 13)
    public static let isModal = AccessibilityTraits(rawValue: 1 << 14)
    public static let isToggle = AccessibilityTraits(rawValue: 1 << 15)
}

/// How an element's children are presented (SwiftUI's
/// `AccessibilityChildBehavior`).
public struct AccessibilityChildBehavior: Sendable, Hashable {
    enum Kind: Sendable, Hashable { case ignore, contain, combine }
    let kind: Kind
    /// The children are not presented; the element is described by its own label.
    public static let ignore = AccessibilityChildBehavior(kind: .ignore)
    /// The children are presented within the element, which groups them.
    public static let contain = AccessibilityChildBehavior(kind: .contain)
    /// The children's labels and values are merged into the element's.
    public static let combine = AccessibilityChildBehavior(kind: .combine)
}

// MARK: - Attributes

/// One accessibility attribute a wrapper applies to its content's element.
public enum AccessibilityAttribute: Equatable, Sendable {
    case value(String)
    case hint(String)
    case hidden(Bool)
    case addTraits(AccessibilityTraits)
    case removeTraits(AccessibilityTraits)
    /// Names Voice Control accepts for the element. No portable renderer has
    /// voice control yet; they keep the attribute for parity.
    case inputLabels([String])
    case element(AccessibilityChildBehavior)
    /// The automation name UI tests find the element by. Not presented to
    /// assistive technology.
    case identifier(String)
}

/// Wrapper produced by the accessibility modifiers other than the label.
/// Renders its content unchanged; the renderer applies `attribute` to the
/// content's accessibility element (see the type comment above).
public struct AccessibilityAttributeView<Content: View>: View {
    public let content: Content
    public let attribute: AccessibilityAttribute

    public var body: some View { content }
}

extension View {
    /// Sets a label a screen reader uses to describe this view.
    public func accessibilityLabel(_ label: String) -> AccessibilityLabelView<Self> {
        AccessibilityLabelView(content: self, label: label)
    }

    /// The element's current value, as text ("50%", "3 tabs", "Applying…").
    public func accessibilityValue(_ value: String) -> AccessibilityAttributeView<Self> {
        AccessibilityAttributeView(content: self, attribute: .value(value))
    }

    /// What activating the element does, when its label doesn't say.
    public func accessibilityHint(_ hint: String) -> AccessibilityAttributeView<Self> {
        AccessibilityAttributeView(content: self, attribute: .hint(hint))
    }

    /// Removes the view and its children from what assistive technology presents.
    public func accessibilityHidden(_ hidden: Bool) -> AccessibilityAttributeView<Self> {
        AccessibilityAttributeView(content: self, attribute: .hidden(hidden))
    }

    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> AccessibilityAttributeView<Self> {
        AccessibilityAttributeView(content: self, attribute: .addTraits(traits))
    }

    public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> AccessibilityAttributeView<Self> {
        AccessibilityAttributeView(content: self, attribute: .removeTraits(traits))
    }

    /// Names Voice Control accepts for this element, most preferred first.
    public func accessibilityInputLabels(_ labels: [String]) -> AccessibilityAttributeView<Self> {
        AccessibilityAttributeView(content: self, attribute: .inputLabels(labels))
    }

    /// Makes the view one accessibility element, with its children ignored,
    /// contained or combined into it.
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> AccessibilityAttributeView<Self> {
        AccessibilityAttributeView(content: self, attribute: .element(children))
    }
}

// MARK: - Announcements

/// Notifications an app posts to assistive technology (SwiftUI's
/// `AccessibilityNotification`).
public enum AccessibilityNotification {
    /// Speaks `message` without moving focus: the outcome of something that
    /// finished, or a change somewhere the user isn't looking.
    public struct Announcement: Sendable {
        public let message: String
        public init(_ message: String) { self.message = message }

        @MainActor
        public func post() {
            AccessibilityAnnouncements.handler(message)
        }
    }
}

/// Where announcements go. A renderer installs its handler at startup (the
/// GTK4 renderer announces through the active window); until then
/// announcements are dropped.
@MainActor
public enum AccessibilityAnnouncements {
    public static var handler: (String) -> Void = { _ in }
}

// MARK: - Preferences

/// The display setting for contrast (SwiftUI's `ColorSchemeContrast`).
public enum ColorSchemeContrast: Sendable, Hashable {
    case standard
    case increased
}

/// The user's accessibility settings that change how an app draws, and
/// which assistive technologies are running. The renderer fills them in from
/// the platform (GTK4: `gtk-enable-animations`, libadwaita's high contrast,
/// the desktop's screen reader setting); they read as SwiftUI's environment
/// values below.
public struct AccessibilityEnvironment: Sendable, Equatable {
    public var reduceMotion = false
    public var reduceTransparency = false
    public var differentiateWithoutColor = false
    public var invertColors = false
    public var voiceOverEnabled = false
    public var switchControlEnabled = false
    public var contrast: ColorSchemeContrast = .standard
    public init() {}
}

private struct AccessibilityEnvironmentKey: EnvironmentKey {
    static let defaultValue = AccessibilityEnvironment()
}

extension EnvironmentValues {
    /// Every accessibility setting at once; renderers set this.
    public var accessibilityEnvironment: AccessibilityEnvironment {
        get { self[AccessibilityEnvironmentKey.self] }
        set { self[AccessibilityEnvironmentKey.self] = newValue }
    }

    public var accessibilityReduceMotion: Bool { accessibilityEnvironment.reduceMotion }
    public var accessibilityReduceTransparency: Bool { accessibilityEnvironment.reduceTransparency }
    public var accessibilityDifferentiateWithoutColor: Bool { accessibilityEnvironment.differentiateWithoutColor }
    public var accessibilityInvertColors: Bool { accessibilityEnvironment.invertColors }
    public var accessibilityVoiceOverEnabled: Bool { accessibilityEnvironment.voiceOverEnabled }
    public var accessibilitySwitchControlEnabled: Bool { accessibilityEnvironment.switchControlEnabled }
    public var colorSchemeContrast: ColorSchemeContrast { accessibilityEnvironment.contrast }
}

// MARK: - Display

extension View {
    /// Keeps the view's colours when the user inverts colours (photos,
    /// video). No portable renderer inverts colours itself, so the content
    /// is unchanged here.
    public func accessibilityIgnoresInvertColors(_ active: Bool = true) -> Self { self }
}

/// The user's preferred text size (SwiftUI's `DynamicTypeSize`). Portable
/// renderers scale text through the desktop's own text scaling, so they
/// report `.large` unless the renderer sets otherwise.
public enum DynamicTypeSize: Int, Sendable, Hashable, Comparable, CaseIterable {
    case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
    case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5

    /// One of the accessibility sizes, where layouts should stack and show
    /// text in full rather than truncate it.
    public var isAccessibilitySize: Bool { self >= .accessibility1 }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

private struct DynamicTypeSizeKey: EnvironmentKey {
    static let defaultValue: DynamicTypeSize = .large
}

extension EnvironmentValues {
    public var dynamicTypeSize: DynamicTypeSize {
        get { self[DynamicTypeSizeKey.self] }
        set { self[DynamicTypeSizeKey.self] = newValue }
    }
}
