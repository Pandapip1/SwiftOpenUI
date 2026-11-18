import Foundation

/// A two-minute test clip for UI tests of players. Same API on every
/// backend; this renderer cannot write one yet and throws.
nonisolated public enum DebugMediaClip {
    public struct Unsupported: Error {}

    public static func make(shade: Int? = nil) async throws -> URL {
        throw Unsupported()
    }
}
