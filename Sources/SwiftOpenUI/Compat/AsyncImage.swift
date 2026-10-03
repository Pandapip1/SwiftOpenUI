import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The state of an `AsyncImage` load.
public enum AsyncImagePhase {
    case empty
    case success(Image)
    case failure(Error)

    public var image: Image? { if case .success(let i) = self { return i } else { return nil } }
    public var error: Error? { if case .failure(let e) = self { return e } else { return nil } }
}

/// Downloads images over HTTP into a per-process cache directory so backends can display them from a file path.
public enum AsyncImageLoader {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var inflight: [URL: [(Result<String, Error>) -> Void]] = [:]
    nonisolated(unsafe) private static var cached: [URL: String] = [:]

    static let directory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftopenui-images-\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Calls `completion` (on an arbitrary thread) with the cached file's path.
    public static func load(_ url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        lock.lock()
        if let path = cached[url] { lock.unlock(); completion(.success(path)); return }
        if inflight[url] != nil { inflight[url]?.append(completion); lock.unlock(); return }
        inflight[url] = [completion]
        lock.unlock()

        if url.isFileURL { finish(url, .success(url.path)); return }
        #if os(WASI)
        finish(url, .failure(URLError(.unsupportedURL)))
        #else
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error { finish(url, .failure(error)); return }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                finish(url, .failure(URLError(.badServerResponse))); return
            }
            guard let data, !data.isEmpty else { finish(url, .failure(URLError(.zeroByteResource))); return }
            let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
            let file = directory.appendingPathComponent(UUID().uuidString + "." + ext)
            do { try data.write(to: file); finish(url, .success(file.path)) } catch { finish(url, .failure(error)) }
        }.resume()
        #endif
    }

    private static func finish(_ url: URL, _ result: Result<String, Error>) {
        lock.lock()
        if case .success(let path) = result { cached[url] = path }
        let waiting = inflight.removeValue(forKey: url) ?? []
        lock.unlock()
        waiting.forEach { $0(result) }
    }
}

/// SwiftUI's `AsyncImage`, loading with `URLSession` and showing from a cached file.
public struct AsyncImage<Content: View>: View {
    let url: URL?
    let content: (AsyncImagePhase) -> Content
    @State private var phase: AsyncImagePhase = .empty
    @State private var loadedURL: URL?

    public init(url: URL?, scale: Double = 1, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    public var body: some View {
        let target = url
        let storage = _phase.storage
        let loaded = _loadedURL.storage
        return content(phase).onAppear {
            guard let target, loaded.value != target else { return }
            loaded.setValue(target)
            AsyncImageLoader.load(target) { result in
                switch result {
                case .success(let path): storage.setValue(.success(Image(filePath: path).resizable()))
                case .failure(let error): storage.setValue(.failure(error))
                }
            }
        }
    }
}

extension AsyncImage {
    public init<I: View, P: View>(url: URL?, scale: Double = 1,
                                  @ViewBuilder content: @escaping (Image) -> I,
                                  @ViewBuilder placeholder: @escaping () -> P) where Content == _ConditionalView<I, P> {
        self.init(url: url, scale: scale) { phase in
            if let image = phase.image { content(image) } else { placeholder() }
        }
    }
}
