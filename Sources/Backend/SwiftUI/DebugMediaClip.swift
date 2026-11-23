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

    /// A 440 Hz tone at low volume: `count` samples from sample `start`.
    private static func appendTone(to input: AVAssetWriterInput, format: CMAudioFormatDescription,
                                   start: Int, count: Int) async throws {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var samples = [Int16](repeating: 0, count: count)
            for index in samples.indices {
                samples[index] = Int16(800 * sin(2 * Double.pi * 440 * Double(start + index) / Double(rate)))
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
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
                presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(rate)),
                packetDescriptions: nil, sampleBufferOut: &buffer)
            if let buffer { input.append(buffer) }
    }

    /// `shade`: every frame that grey level (0 black ... 255 white); nil: frames
    /// cycle through all levels.
    @concurrent
    public static func make(shade: Int? = nil) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("debug-clip-v2-\(shade.map(String.init) ?? "cycle").mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        // Written under another name and moved into place when complete: an app
        // stopped mid-write (UI tests terminate it) leaves no broken clip behind.
        let partial = url.deletingPathExtension().appendingPathExtension("partial-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: partial, fileType: .mp4)
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
            // Audio and video advance together, a frame's worth at a time: the
            // writer interleaves them and waits for whichever is behind.
            let perFrame = rate / Int(fps)
            try await appendTone(to: audio, format: tone, start: frame * perFrame, count: perFrame)
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
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: partial)
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        // Another launch may have finished the same clip meanwhile: either copy is complete.
        if (try? FileManager.default.moveItem(at: partial, to: url)) == nil { try? FileManager.default.removeItem(at: partial) }
        return url
    }
}
#endif
