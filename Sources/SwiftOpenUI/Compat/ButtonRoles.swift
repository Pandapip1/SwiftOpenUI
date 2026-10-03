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
    public var actionTitle: String? { (label as? Text)?.content ?? (label as? SwiftOpenUI.Label).map(\.title) }
    public var actionRole: ButtonRole? { buttonRole }
    public var actionClosure: () -> Void { action }
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
        flatten(view).compactMap { v in
            guard let c = v as? ActionConvertible, let title = c.actionTitle else { return nil }
            return .item(label: title, action: c.actionClosure)
        }
    }

    static func flatten(_ view: any View) -> [any View] {
        if let multi = view as? any MultiChildView { return multi.children.flatMap(flatten) }
        if view is EmptyView { return [] }
        return [view]
    }
}
