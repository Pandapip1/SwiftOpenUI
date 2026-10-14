import XCTest
@testable import SwiftOpenUICore

final class ClipModifierTests: XCTestCase {

    // MARK: - ClipShapeView

    @MainActor func testClipShapeStoresShape() {
        let view = Text("Hello").clipShape(Circle())
        // Circle has no properties to check, but verify it compiles and wraps
        XCTAssertEqual(view.content.content, "Hello")
    }

    @MainActor func testClipShapeWithRoundedRectangle() {
        let view = Text("Hello").clipShape(RoundedRectangle(cornerRadius: 12))
        XCTAssertEqual(view.shape.cornerRadius, 12)
    }

    @MainActor func testClipShapeWithCapsule() {
        let view = Text("Hello").clipShape(Capsule())
        XCTAssertEqual(view.shape.style, .circular)
    }

    @MainActor func testClipShapeWithEllipse() {
        let view = Text("Hello").clipShape(Ellipse())
        XCTAssertEqual(view.content.content, "Hello")
    }

    @MainActor func testClipShapeWithRectangle() {
        let view = Text("Hello").clipShape(Rectangle())
        XCTAssertEqual(view.content.content, "Hello")
    }

    // MARK: - ClippedView

    @MainActor func testClippedWrapsContent() {
        let view = Text("Hello").clipped()
        XCTAssertEqual(view.content.content, "Hello")
    }

    // MARK: - Chaining

    @MainActor func testClipShapeChainedWithFrame() {
        let view = Text("Hello")
            .frame(width: 100, height: 100)
            .clipShape(Circle())
        XCTAssertEqual(view.content.width, 100)
    }

    @MainActor func testClippedChainedWithPadding() {
        let view = Text("Hello")
            .padding()
            .clipped()
        // Verify it compiles and wraps
        _ = view
    }

    @MainActor func testClipShapeChainedWithFillAndClip() {
        // Common pattern: shape background + clip
        let view = Text("Hello")
            .background(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        XCTAssertEqual(view.shape.cornerRadius, 8)
    }
}
