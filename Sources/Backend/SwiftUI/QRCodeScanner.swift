#if canImport(SwiftUI)
import SwiftUI
#if (os(iOS) || os(macOS)) && canImport(AVFoundation)
import AVFoundation
import CoreImage
import Vision
#endif

/// Whether this device can scan QR codes with a camera.
public enum QRCodeScanning {
    /// Whether there is a camera to scan with. Looking up capture devices can
    /// block for a noticeable time, so it never runs on the main thread.
    public static func isAvailable() async -> Bool {
        #if (os(iOS) || os(macOS)) && canImport(AVFoundation)
        await Task.detached(priority: .userInitiated) {
            AVCaptureDevice.default(for: .video) != nil
        }.value
        #else
        false
        #endif
    }
}

/// A live camera view that reports the first QR code it reads. Same API on
/// every backend; where there is no camera to scan with, `onUnavailable` is
/// called and the view says so. The caller is responsible for camera
/// permission: show this only once access is granted.
public struct QRCodeScannerView: View {
    private let onCode: (String) -> Void
    private let onUnavailable: () -> Void

    public init(onCode: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
        self.onCode = onCode
        self.onUnavailable = onUnavailable
    }

    public var body: some View {
        #if (os(iOS) || os(macOS)) && canImport(AVFoundation)
        CameraQRCodeScanner(onCode: onCode, onUnavailable: onUnavailable)
        #else
        Text("This device can’t scan QR codes.")
            .foregroundStyle(.secondary)
            .task { onUnavailable() }
        #endif
    }
}

#if (os(iOS) || os(macOS)) && canImport(AVFoundation)
/// Shows the camera's frames and reads QR codes from them. The camera itself
/// belongs to a `QRCaptureSession` actor, so nothing about it is shared with
/// the main thread: the view receives finished frames (`CGImage`, Sendable)
/// and decoded codes (`String`) through an async stream.
private struct CameraQRCodeScanner: View {
    let onCode: (String) -> Void
    let onUnavailable: () -> Void
    @State private var frame: CGImage?

    var body: some View {
        ZStack {
            Color.black
            if let frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .clipped()
        .accessibilityLabel("Camera")
        .task {
            let capture = QRCaptureSession()
            guard let events = await capture.start() else {
                onUnavailable()
                return
            }
            // Ends when the view goes away: the task is cancelled, and the
            // camera stops.
            await withTaskCancellationHandler {
                for await event in events {
                    switch event {
                    case .frame(let image): frame = image
                    case .code(let code):
                        onCode(code)
                        await capture.stop()
                        return
                    }
                }
            } onCancel: {
                Task { await capture.stop() }
            }
        }
    }
}

/// What the capture session reports to its view.
private enum QRCaptureEvent: Sendable {
    case frame(CGImage)
    case code(String)
}

/// The camera, on a queue of its own. Opening a camera, configuring the
/// session and starting or stopping it can each block for a second or more,
/// so the actor runs on its own serial queue (its executor), never the main
/// thread. The session, its output and the frames stay with the actor and its
/// frame receiver; only Sendable results leave them.
private actor QRCaptureSession {
    private let queue = DispatchSerialQueue(label: "swiftopenui.qr-capture", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private var receiver: QRFrameReceiver?

    /// Starts the camera, returning its events, or `nil` if this device's
    /// camera can't be opened.
    func start() -> AsyncStream<QRCaptureEvent>? {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return nil
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        session.addOutput(output)
        let (events, continuation) = AsyncStream.makeStream(of: QRCaptureEvent.self,
                                                            bufferingPolicy: .bufferingNewest(1))
        let receiver = QRFrameReceiver(output: output, device: device, events: continuation)
        self.receiver = receiver
        output.setSampleBufferDelegate(receiver, queue: queue)
        session.commitConfiguration()
        session.startRunning()
        return events
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
        output.setSampleBufferDelegate(nil, queue: nil)
        receiver?.finish()
        receiver = nil
    }
}

/// Receives the camera's frames, one at a time on the session's queue: shows
/// each, and every few frames reads it for a QR code. It belongs to the
/// session (not Sendable); what it reports are Sendable values.
private nonisolated final class QRFrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let output: AVCaptureVideoDataOutput
    private let events: AsyncStream<QRCaptureEvent>.Continuation
    private let context = CIContext()
    private let rotation: AVCaptureDevice.RotationCoordinator
    private var frameCount = 0
    private var isFinished = false

    init(output: AVCaptureVideoDataOutput, device: AVCaptureDevice,
         events: AsyncStream<QRCaptureEvent>.Continuation) {
        self.output = output
        self.events = events
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    }

    func finish() {
        isFinished = true
        events.finish()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !isFinished, let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        frameCount += 1
        // Keep the picture upright as the device turns.
        if frameCount % 15 == 1 {
            let angle = rotation.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
        if frameCount % 3 == 0, let code = Self.readQRCode(in: pixels) {
            events.yield(.code(code))
            return
        }
        let image = CIImage(cvPixelBuffer: pixels)
        if let frame = context.createCGImage(image, from: image.extent) {
            events.yield(.frame(frame))
        }
    }

    private static func readQRCode(in pixels: CVPixelBuffer) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cvPixelBuffer: pixels).perform([request])
        return request.results?.lazy.compactMap(\.payloadStringValue).first
    }
}
#endif
#endif
