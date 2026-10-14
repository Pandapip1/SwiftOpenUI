import XCTest
@testable import SwiftOpenUICore

final class AppearanceModifierTests: XCTestCase {

    // MARK: - HiddenView

    @MainActor func testHiddenWrapsContent() {
        let view = Text("Hello").hidden()
        XCTAssertEqual(view.content.content, "Hello")
    }

    // MARK: - BlurView

    @MainActor func testBlurWrapsContent() {
        let view = Text("Hello").blur(radius: 5)
        XCTAssertEqual(view.content.content, "Hello")
        XCTAssertEqual(view.radius, 5)
    }

    @MainActor func testBlurDefaultOpaque() {
        let view = Text("Hello").blur(radius: 3)
        XCTAssertFalse(view.opaque)
    }

    @MainActor func testBlurOpaqueTrue() {
        let view = Text("Hello").blur(radius: 3, opaque: true)
        XCTAssertTrue(view.opaque)
    }

    @MainActor func testBlurZeroRadius() {
        let view = Text("Hello").blur(radius: 0)
        XCTAssertEqual(view.radius, 0)
    }

    // MARK: - Chaining

    @MainActor func testHiddenChainedWithOtherModifiers() {
        let view = Text("Hello")
            .padding()
            .hidden()
        _ = view // compiles
    }

    @MainActor func testBlurChainedWithFrame() {
        let view = Text("Hello")
            .frame(width: 100, height: 100)
            .blur(radius: 10)
        XCTAssertEqual(view.radius, 10)
    }
}
