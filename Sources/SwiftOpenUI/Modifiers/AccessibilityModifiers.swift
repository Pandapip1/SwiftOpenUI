/// Accessibility modifiers accepted for SwiftUI API parity.
///
/// `.accessibilityIdentifier(_:)` names a view for UI-test automation.
/// It has no visual effect. On GTK4/Win32 it currently passes through
/// (parity matrix note); a future pass can map it to the platform
/// automation id (GtkAccessible name / UI Automation AutomationId).
extension View {
    public func accessibilityIdentifier(_ identifier: String) -> Self { self }
    public func accessibilityHidden(_ hidden: Bool) -> Self { self }
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

extension View {
    /// Sets a label a screen reader uses to describe this view.
    public func accessibilityLabel(_ label: String) -> AccessibilityLabelView<Self> {
        AccessibilityLabelView(content: self, label: label)
    }
}
