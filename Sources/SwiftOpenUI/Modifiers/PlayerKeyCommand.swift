import Foundation

public extension View {
    /// A keyboard command for a player control (space, arrows, letters).
    /// Same API on every backend.
    func playerKeyCommand(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> KeyboardShortcutView<Self> {
        keyboardShortcut(key, modifiers: modifiers)
    }
}
