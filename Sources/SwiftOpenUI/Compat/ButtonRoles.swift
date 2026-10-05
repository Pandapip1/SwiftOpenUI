import Foundation

/// SwiftUI's `ButtonRole`. Roles decide placement and styling in alerts and dialogs.
public struct ButtonRole: Equatable, Sendable {
    fileprivate let raw: Int
    public static let cancel = ButtonRole(raw: 0)
    public static let destructive = ButtonRole(raw: 1)
    public static let close = ButtonRole(raw: 2)
    public static let confirm = ButtonRole(raw: 3)

    var alertRole: AlertButtonRole {
        switch raw {
        case 0, 2: return .cancel
        case 1: return .destructive
        default: return .default
        }
    }
}

/// Views that can describe themselves as a single dialog or menu button. Used to read `Button`s out of the
/// `@ViewBuilder` closures of `.alert { }`, `.confirmationDialog { }` and `.swipeActions { }`.
public protocol ActionConvertible {
    var actionTitle: String? { get }
    var actionRole: ButtonRole? { get }
    var actionClosure: () -> Void { get }
}

extension Button: ActionConvertible {
    /// Native menus need a textual accessible name. Standard Text/Label values
    /// keep their exact title; custom labels retain a stable descriptive name
    /// instead of disappearing from the menu.
    public var actionTitle: String? {
        (label as? Text)?.content
            ?? (label as? SwiftOpenUI.Label).map(\.title)
            ?? actionLabelText(label)
    }
    public var actionRole: ButtonRole? { buttonRole }
    public var actionClosure: () -> Void { action }
}

func actionLabelText<V: View>(_ view: V, depth: Int = 0) -> String? {
    guard depth < 8 else { return nil }
    if let accessible = view as? any _AccessibilityLabelProvider { return accessible._accessibilityLabel }
    if let text = view as? Text { return text.content }
    if let label = view as? SwiftOpenUI.Label { return label.title }
    if let multi = view as? any MultiChildView {
        let labels = multi.children.compactMap { actionLabelText($0, depth: depth + 1) }
        if !labels.isEmpty { return labels.joined(separator: " ") }
    }
    // Common custom labels are lightweight views whose body is Text or Label.
    // Follow that body so native menus retain the same visible/accessibility
    // string instead of exposing an implementation type name.
    if V.Body.self != Never.self, let text = actionLabelText(view.body, depth: depth + 1) { return text }
    // Style/accessibility modifiers commonly keep their source view in a
    // `content` field while exposing Body == Never. Follow that field too.
    for child in Mirror(reflecting: view).children {
        if child.label == "content", let content = child.value as? any View,
           let text = actionLabelText(content, depth: depth + 1) { return text }
    }
    return nil
}

extension Button {
    public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
        self.buttonRole = role
    }

    public init(role: ButtonRole?, @ViewBuilder label: () -> Label, action: @escaping () -> Void) {
        self.init(role: role, action: action, label: label)
    }
}

extension Button where Label == Text {
    public init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.action = action
        self.label = Text(title)
        self.buttonRole = role
    }
}

/// Flattens view-builder output into dialog buttons or menu items.
public enum AlertActions {
    /// Every `Button` (looking through groups, conditionals and `ForEach`) in document order.
    public static func buttons(from view: any View) -> [AlertButton] {
        flatten(view).compactMap { v in
            guard let c = v as? ActionConvertible, let title = c.actionTitle else { return nil }
            return AlertButton(title, role: c.actionRole?.alertRole ?? .default, action: c.actionClosure)
        }
    }

    public static func menuElements(from view: any View) -> [MenuElement] {
        collectMenuElements(view)
    }

    private static func collectMenuElements(_ view: any View) -> [MenuElement] {
        if let menu = view as? any _MenuContentProvider {
            return [.submenu(label: menu._menuTitle, children: collectMenuElements(menu._menuContent))]
        }
        if view is Divider { return [.divider] }
        if let disabled = view as? any _MenuContentWrapper {
            let elements = collectMenuElements(disabled._menuContent)
            guard disabled._menuIsDisabled else { return elements }
            return setMenuEnabled(elements, enabled: false)
        }
        if let multi = view as? any MultiChildView {
            return multi.children.flatMap(collectMenuElements)
        }
        if let c = view as? ActionConvertible, let title = c.actionTitle {
            return [.item(label: title, role: c.actionRole, isEnabled: true, action: c.actionClosure)]
        }
        // Ordinary modifiers around a Button/Menu retain the source view in
        // their content field even when they are not MultiChildView wrappers.
        for child in Mirror(reflecting: view).children where child.label == "content" {
            if let content = child.value as? any View { return collectMenuElements(content) }
        }
        return []
    }

    private static func setMenuEnabled(_ elements: [MenuElement], enabled: Bool) -> [MenuElement] {
        elements.map { element in
            switch element {
            case .item(let label, let role, _, let action):
                return .item(label: label, role: role, isEnabled: enabled, action: enabled ? action : {})
            case .submenu(let label, let children):
                return .submenu(label: label, children: setMenuEnabled(children, enabled: enabled))
            case .divider:
                return .divider
            }
        }
    }

    static func flatten(_ view: any View) -> [any View] {
        if let multi = view as? any MultiChildView { return multi.children.flatMap(flatten) }
        if view is EmptyView { return [] }
        return [view]
    }
}
