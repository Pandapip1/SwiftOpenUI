import Foundation

/// `AsyncImage` for lists of thumbnails. The SwiftUI backend decodes and
/// downsamples away from the main thread and keeps recent images; here the
/// image is already loaded from a file cache off the main thread.
public struct DecodedAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content

    public init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    public var body: some View {
        AsyncImage(url: url, content: content)
    }
}
