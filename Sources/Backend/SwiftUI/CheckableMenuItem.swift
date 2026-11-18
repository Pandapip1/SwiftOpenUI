#if canImport(SwiftUI)
import SwiftUI

/// Whether a menu choice is in effect. Mirrors the portable declaration.
public enum CheckableMenuItemState: Sendable, Equatable {
    case unchecked
    /// The choice in effect.
    case checked
    /// Chosen but not yet confirmed in effect: the checkmark stays on the
    /// current choice and this item shows a spinner.
    case pending
}

/// A menu choice with a leading column reserved for its checkmark or pending
/// spinner. Every item carries an icon of the same size (checkmark, animated
/// progress symbol, or a transparent placeholder), so system menus (AppKit's
/// NSMenu, UIKit's UIMenu) and in-app popovers line the titles up in one
/// column. Same API as the portable implementation.
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
            Label {
                Text(title)
            } icon: {
                icon.frame(width: 18, height: 18)
            }
        }
        .disabled(state == .pending)
        // Assistive technology hears which item is chosen and which is switching.
        .accessibilityAddTraits(state == .checked ? .isSelected : [])
        .accessibilityValue(state == .pending ? "Switching…" : "")
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .checked:
            Image(systemName: "checkmark")
        case .pending:
            Image(systemName: "progress.indicator")
                .symbolEffect(.variableColor.iterative, options: .repeating)
        case .unchecked:
            // A transparent image the size of the checkmark: system menus
            // reserve the column only when every item has an image.
            Image(size: CGSize(width: 16, height: 16)) { _ in }
        }
    }
}
#endif
