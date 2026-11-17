/// Whether a menu choice is in effect.
public enum CheckableMenuItemState: Sendable, Equatable {
    case unchecked
    /// The choice in effect.
    case checked
    /// Chosen but not yet confirmed in effect. The checkmark stays on the
    /// current choice; this item shows an indeterminate spinner and cannot be
    /// chosen again until it settles.
    case pending
}

/// A menu choice with a leading column reserved for its checkmark or pending
/// spinner, so every item's label starts in the same column.
///
/// One API on every backend:
/// - SwiftUI (Apple): a `Label` whose icon is the checkmark, an animated
///   progress symbol, or a transparent image of the same size, so the system
///   menu's image column lines the titles up.
/// - GTK4 and other renderers: a fixed-width leading column holding a
///   checkmark image, a `ProgressView`, or nothing.
public struct CheckableMenuItem: View {
    private let title: String
    private let state: CheckableMenuItemState
    private let action: () -> Void

    public init(_ title: String, state: CheckableMenuItemState, action: @escaping () -> Void) {
        self.title = title
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    switch state {
                    case .checked: Image(systemName: "checkmark")
                    case .pending: ProgressView()
                    case .unchecked: Color.clear
                    }
                }
                .frame(width: 18, height: 18)
                Text(title)
                Spacer(minLength: 0)
            }
        }
        .disabled(state == .pending)
    }
}
