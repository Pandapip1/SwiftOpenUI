#if canImport(SwiftUI) && canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Synchronization

/// `AsyncImage` for lists of thumbnails: the image is fetched with a session
/// of its own (ephemeral: no cookies, credentials or disk cache shared with
/// anything else), then decoded and downsampled away from the main thread,
/// and recently decoded images are kept so scrolling back shows them at once.
/// SwiftUI's own `AsyncImage` hands over images that are only decoded when
/// first drawn, on the main thread, which makes scrolling stutter.
public struct DecodedAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content
    @State private var loaded: DecodedImage?
    @State private var failure: (any Error)?

    public init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    public var body: some View {
        let image = loaded.flatMap { $0.url == url ? $0 : nil } ?? url.flatMap(DecodedImageCache.shared.image(for:))
        content(phase(image))
            .task(id: url) {
                failure = nil
                guard let url, DecodedImageCache.shared.image(for: url) == nil else { return }
                do { loaded = try await DecodedImage.load(url) }
                catch is CancellationError {}
                catch { failure = error }
            }
    }

    private func phase(_ image: DecodedImage?) -> AsyncImagePhase {
        if let image { return .success(Image(decorative: image.cgImage, scale: 1)) }
        if let failure { return .failure(failure) }
        return .empty
    }
}

nonisolated struct DecodedImage: Sendable {
    let url: URL
    let cgImage: CGImage

    /// Thumbnails never need more than this many pixels on their long side.
    private static let maximumPixelSize = 720

    /// Image requests share no state with the app or its web views: no
    /// cookies are sent or kept, no credentials are stored, and the only cache
    /// is this session's own, in memory.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1_024 * 1_024, diskCapacity: 0)
        return URLSession(configuration: configuration)
    }()

    @concurrent
    static func load(_ url: URL) async throws -> DecodedImage {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  // Decode now, here, rather than when first drawn.
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
              ] as CFDictionary)
        else { throw URLError(.cannotDecodeContentData) }
        let decoded = DecodedImage(url: url, cgImage: image)
        DecodedImageCache.shared.insert(decoded)
        return decoded
    }
}

/// Recently decoded images, least recently used dropped first.
nonisolated final class DecodedImageCache: Sendable {
    static let shared = DecodedImageCache()

    /// Decoded bytes kept, at most: around 50 16:9 thumbnails.
    private static let byteBudget = 64 * 1_024 * 1_024
    private let state = Mutex(State())

    private struct State {
        var images: [URL: DecodedImage] = [:]
        var order: [URL] = []
        var bytes = 0
    }

    private static func cost(of image: DecodedImage) -> Int {
        image.cgImage.bytesPerRow * image.cgImage.height
    }

    func image(for url: URL) -> DecodedImage? {
        state.withLock { state in
            guard let image = state.images[url] else { return nil }
            if let index = state.order.lastIndex(of: url), index != state.order.count - 1 {
                state.order.remove(at: index)
                state.order.append(url)
            }
            return image
        }
    }

    func insert(_ image: DecodedImage) {
        state.withLock { state in
            if let replaced = state.images.updateValue(image, forKey: image.url) {
                state.order.removeAll { $0 == image.url }
                state.bytes -= Self.cost(of: replaced)
            }
            state.order.append(image.url)
            state.bytes += Self.cost(of: image)
            while state.bytes > Self.byteBudget, state.order.count > 1 {
                if let evicted = state.images.removeValue(forKey: state.order.removeFirst()) {
                    state.bytes -= Self.cost(of: evicted)
                }
            }
        }
    }
}
#endif
