import Foundation

/// Whether this device can scan QR codes with a camera. Same API as the
/// SwiftUI backend's; this backend has no camera scanning.
public enum QRCodeScanning {
    public static func isAvailable() async -> Bool { false }
}

/// A live camera view that reports the first QR code it reads. Same API as
/// the SwiftUI backend's; this backend has no camera scanning, so it says so
/// and calls `onUnavailable`.
public struct QRCodeScannerView: View {
    private let onUnavailable: () -> Void

    public init(onCode: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
        self.onUnavailable = onUnavailable
    }

    public var body: some View {
        Text("This device can’t scan QR codes.")
            .onAppear(onUnavailable)
    }
}
