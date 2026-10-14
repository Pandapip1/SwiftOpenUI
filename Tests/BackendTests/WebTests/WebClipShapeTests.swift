import XCTest
@testable import SwiftOpenUICore
@testable import BackendWeb

final class WebClipShapeTests: XCTestCase {

    // MARK: - webClipPathCSS helper

    @MainActor

    func testClipPathCircle() {
        let css = webClipPathCSS(Circle())
        XCTAssertEqual(css, "clip-path: circle(50%);")
    }

    @MainActor

    func testClipPathEllipse() {
        let css = webClipPathCSS(Ellipse())
        XCTAssertEqual(css, "clip-path: ellipse(50% 50%);")
    }

    @MainActor

    func testClipPathRoundedRectangle() {
        let css = webClipPathCSS(RoundedRectangle(cornerRadius: 12))
        XCTAssertEqual(css, "clip-path: inset(0 round 12px);")
    }

    @MainActor

    func testClipPathCapsule() {
        let css = webClipPathCSS(Capsule())
        XCTAssertEqual(css, "clip-path: inset(0 round 9999px);")
    }

    @MainActor

    func testClipPathRectangleIsNil() {
        let css = webClipPathCSS(SwiftOpenUICore.Rectangle())
        XCTAssertNil(css, "Rectangle clip uses overflow: hidden, no clip-path needed")
    }

    // MARK: - Modifier storage

    @MainActor

    func testClipShapeStoresShape() {
        let view = Text("Hello").clipShape(Circle())
        XCTAssertEqual(view.content.content, "Hello")
    }

    @MainActor

    func testClipShapeWithRoundedRectangle() {
        let view = Text("Hello").clipShape(RoundedRectangle(cornerRadius: 8))
        XCTAssertEqual(view.shape.cornerRadius, 8)
    }

    @MainActor

    func testClippedWrapsContent() {
        let view = Text("Hello").clipped()
        XCTAssertEqual(view.content.content, "Hello")
    }

    // MARK: - Chaining

    @MainActor

    func testClipShapeWithFrame() {
        let view = Text("Hello")
            .frame(width: 50, height: 50)
            .clipShape(Circle())
        XCTAssertEqual(view.content.width, 50)
    }

    @MainActor

    func testClipShapeWithBackgroundAndClip() {
        let view = Text("Hello")
            .background(.red)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        XCTAssertEqual(view.shape.cornerRadius, 10)
    }
}
