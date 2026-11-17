#if canImport(SwiftUI)
import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// Re-encodes a local media file with the system's hardware HEVC encoder, to
/// save space. Same API as the portable implementation.
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

    /// The system offers HEVC export (hardware encoders on Apple silicon and
    /// recent iOS devices).
    public static var isAvailable: Bool {
        AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality)
    }

    /// Background work is welcome now: not in Low Power Mode, not hot, and on
    /// iOS charging.
    @MainActor
    public static var conditionsAllowBackgroundWork: Bool {
        let process = ProcessInfo.processInfo
        guard !process.isLowPowerModeEnabled, process.thermalState.rawValue <= ProcessInfo.ThermalState.fair.rawValue else {
            return false
        }
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return [.charging, .full].contains(UIDevice.current.batteryState)
        #else
        return true
        #endif
    }

    /// Re-encodes `source` (a complete local file) to HEVC at `destination`.
    /// Runs off the main actor.
    @concurrent
    public static func transcodeToHEVC(source: URL, destination: URL) async throws {
        guard isAvailable else { throw Failure.unavailable }
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw Failure.unavailable
        }
        try? FileManager.default.removeItem(at: destination)
        do {
            try await session.export(to: destination, as: .mp4)
        } catch {
            throw Failure.failed(error.localizedDescription)
        }
    }
}
#endif
