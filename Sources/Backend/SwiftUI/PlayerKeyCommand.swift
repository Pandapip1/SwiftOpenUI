#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// A keyboard command for a player control (space, arrows, letters).
    /// Same API on every backend; tvOS has no keyboard shortcuts (the remote
    /// drives the player there), so it does nothing.
    @ViewBuilder
    func playerKeyCommand(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> some View {
        #if os(tvOS)
        self
        #else
        keyboardShortcut(key, modifiers: modifiers)
        #endif
    }
}
#endif
