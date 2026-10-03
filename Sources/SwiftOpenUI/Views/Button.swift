/// A control that initiates an action.
public struct Button<Label: View>: View {
    public typealias Body = Never

    public let action: () -> Void
    public let label: Label
    /// Set by `Button(role:)`; read by alerts, dialogs and the GTK renderer for destructive styling.
    public var buttonRole: ButtonRole? = nil

    public var body: Never { fatalError("Button is a primitive view") }
}

extension Button where Label == Text {
    public init(_ title: String, action: @escaping () -> Void) {
        self.action = action
        self.label = Text(title)
    }
}

extension Button {
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }
}
