import Foundation

/// The user's system-wide media accessibility preferences. Same API on every
/// backend; this platform has no such setting yet.
nonisolated public enum MediaAccessibilityPreferences {
    public static var prefersAudioDescriptions: Bool { false }
}
