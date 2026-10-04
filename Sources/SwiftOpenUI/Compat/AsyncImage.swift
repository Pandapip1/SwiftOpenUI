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

/// Downloads images over HTTP into a bounded persistent cache so backends can display them from a file path.
public enum AsyncImageLoader {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var inflight: [URL: [(Result<String, Error>) -> Void]] = [:]
    nonisolated(unsafe) private static var cached: [URL: String] = [:]

    static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("SwiftOpenUI/AsyncImage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let maximumFiles = 512
    private static let maximumBytes: UInt64 = 256 * 1024 * 1024

    /// Calls `completion` (on an arbitrary thread) with the cached file's path.
    public static func load(_ url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        lock.lock()
        if let path = cached[url], FileManager.default.fileExists(atPath: path) {
            lock.unlock(); completion(.success(path)); return
        }
        cached[url] = nil
        let file = cacheFile(for: url)
        if FileManager.default.fileExists(atPath: file.path) {
            cached[url] = file.path
            lock.unlock()
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            completion(.success(file.path))
            return
        }
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
            do {
                try data.write(to: file, options: .atomic)
                pruneCache()
                finish(url, .success(file.path))
            } catch { finish(url, .failure(error)) }
        }.resume()
        #endif
    }

    static func cacheFile(for url: URL) -> URL {
        // FNV-1a is stable across launches (unlike Swift.Hashable) and the two
        // independent passes make accidental URL collisions vanishingly rare.
        func fnv(_ bytes: some Sequence<UInt8>, seed: UInt64) -> UInt64 {
            bytes.reduce(seed) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }
        let bytes = url.absoluteString.utf8
        let first = fnv(bytes, seed: 14_695_981_039_346_656_037)
        let second = fnv(bytes.reversed(), seed: 10_995_116_282_111)
        let ext = url.pathExtension.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        } && url.pathExtension.count <= 10 ? url.pathExtension : "img"
        return directory.appendingPathComponent(String(format: "%016llx%016llx.%@", first, second, ext))
    }

    private static func pruneCache() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard var files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ).compactMap({ url -> (URL, Date, UInt64)? in
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, UInt64(values.fileSize ?? 0))
        }) else { return }
        files.sort { $0.1 < $1.1 }
        var bytes = files.reduce(UInt64(0)) { $0 + $1.2 }
        while files.count > maximumFiles || bytes > maximumBytes {
            let removed = files.removeFirst()
            try? FileManager.default.removeItem(at: removed.0)
            bytes -= min(bytes, removed.2)
        }
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
