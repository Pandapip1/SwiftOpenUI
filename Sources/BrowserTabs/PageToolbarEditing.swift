import SwiftOpenUI

public extension View {
    /// An Edit button in the page's own toolbar for a list whose rows can be
    /// reordered and deleted, where lists do that in an edit mode (iOS and
    /// iPadOS). Elsewhere rows offer those actions directly (swipe or context
    /// menu, drag to reorder), so nothing is added.
    @ViewBuilder
    func editableCollectionToolbar(id: String) -> some View {
        #if os(iOS)
        browserPageToolbarItem(id: id, placement: .trailing) { EditButton() }
        #else
        self
        #endif
    }
}
