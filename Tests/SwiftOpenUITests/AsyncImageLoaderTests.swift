import XCTest
@testable import SwiftOpenUICore

final class AsyncImageLoaderTests: XCTestCase {
    func testPersistentFileIsReusedWithoutNetwork() throws {
        let remote = try XCTUnwrap(URL(string: "https://unreachable.invalid/thumb.png"))
        let file = AsyncImageLoader.cacheFile(for: remote)
        try Data("cached-image".utf8).write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }

        let loaded = expectation(description: "cache hit")
        AsyncImageLoader.load(remote) { result in
            XCTAssertEqual(try? result.get(), file.path)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 1)
    }

    func testCacheFileIsStableAndPreservesSafeExtension() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/a/thumbnail.webp?size=large"))
        XCTAssertEqual(AsyncImageLoader.cacheFile(for: url), AsyncImageLoader.cacheFile(for: url))
        XCTAssertEqual(AsyncImageLoader.cacheFile(for: url).pathExtension, "webp")
    }
}
