#if canImport(SwiftUI)
import Foundation
#if canImport(MediaAccessibility)
import MediaAccessibility
#endif

/// The user's system-wide media accessibility preferences. Same API on every
/// backend.
nonisolated public enum MediaAccessibilityPreferences {
    /// The user asked for audio descriptions (Accessibility › Audio
    /// Descriptions): choose described audio tracks automatically.
    public static var prefersAudioDescriptions: Bool {
        #if canImport(MediaAccessibility)
        let characteristics = MAAudibleMediaCopyPreferredCharacteristics().takeRetainedValue() as? [String] ?? []
        return characteristics.contains("public.accessibility.describes-video")
        #else
        false
        #endif
    }
}
#endif
