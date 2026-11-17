import Foundation

/// Re-encodes a local media file with the platform's hardware encoder, to
/// save space. One API on every backend: the SwiftUI backend uses the
/// system's hardware HEVC encoder; the portable renderers have no hardware
/// encoder integration yet and report `isAvailable == false`.
public enum MediaTranscoder {
    public enum Failure: Error, Equatable, LocalizedError {
        case unavailable
        case failed(String)
        public var errorDescription: String? {
            switch self {
            case .unavailable: "This device has no hardware video encoder Hummingbird can use."
            case .failed(let reason): "Re-encoding failed: \(reason)"
            }
        }
    }

    /// A hardware encoder is available.
    nonisolated public static var isAvailable: Bool { false }

    /// Background work is welcome now. Desktop renderers have no power or
    /// thermal signal to honour here, so it always is.
    @MainActor
    public static var conditionsAllowBackgroundWork: Bool { true }

    /// Re-encodes `source` (a complete local file) to HEVC at `destination`.
    /// Runs off the main actor.
    nonisolated public static func transcodeToHEVC(source: URL, destination: URL) async throws {
        throw Failure.unavailable
    }
}
