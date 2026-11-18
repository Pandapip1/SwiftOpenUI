#if canImport(SwiftUI)
import Foundation
import AVFoundation


/// A two-minute test clip (H.264 video, a quiet 440 Hz tone) written to the
/// temporary directory, for UI tests of players: no network needed. Same API
/// on every backend.
nonisolated public enum DebugMediaClip {
    private static let rate = 44_100

    /// 16-bit mono PCM at 44.1 kHz.
    private static func toneFormat() throws -> CMAudioFormatDescription {
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { throw CocoaError(.fileWriteUnknown) }
        return format
    }

    /// One second of a 440 Hz tone at low volume.
    private static func appendTone(to input: AVAssetWriterInput, format: CMAudioFormatDescription, second: Int) async throws {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var samples = [Int16](repeating: 0, count: rate)
            for index in samples.indices {
                samples[index] = Int16(800 * sin(2 * Double.pi * 440 * Double(index) / Double(rate)))
            }
            var block: CMBlockBuffer?
            let bytes = samples.count * 2
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                               customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0,
                                               blockBufferOut: &block)
            guard let block else { return }
            samples.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                _ = CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
            }
            var buffer: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: rate,
                presentationTimeStamp: CMTime(value: CMTimeValue(second * rate), timescale: CMTimeScale(rate)),
                packetDescriptions: nil, sampleBufferOut: &buffer)
            if let buffer { input.append(buffer) }
    }

    /// `shade`: every frame that grey level (0 black ... 255 white); nil: frames
    /// cycle through all levels.
    @concurrent
    public static func make(shade: Int? = nil) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("debug-clip-with-audio-\(shade.map(String.init) ?? "cycle").mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180,
        ])
        writer.add(input)
        // A quiet tone, so the clip plays like real media in the background.
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
        ])
        writer.add(audio)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 10
        let tone = try toneFormat()
        for frame in 0..<(120 * Int(fps)) {
            if frame % Int(fps) == 0 { try await appendTone(to: audio, format: tone, second: frame / Int(fps)) }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(shade ?? frame % 255), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        audio.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }
}
#endif
