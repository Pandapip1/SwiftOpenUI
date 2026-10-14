import XCTest
@testable import SwiftOpenUICore
import Foundation

final class LayoutModifierTests: XCTestCase {

    // MARK: - PositionView

    @MainActor func testPositionWrapsContent() {
        let view = Text("Hello").position(x: 50, y: 100)
        XCTAssertEqual(view.x, 50)
        XCTAssertEqual(view.y, 100)
        XCTAssertEqual(view.content.content, "Hello")
    }

    @MainActor func testPositionDefaults() {
        let view = Text("Hello").position()
        XCTAssertEqual(view.x, 0)
        XCTAssertEqual(view.y, 0)
    }

    @MainActor func testPositionWithCGPoint() {
        let view = Text("Hello").position(CGPoint(x: 30, y: 40))
        XCTAssertEqual(view.x, 30)
        XCTAssertEqual(view.y, 40)
    }

    // MARK: - LayoutPriorityView

    @MainActor func testLayoutPriorityWrapsContent() {
        let view = Text("Hello").layoutPriority(1)
        XCTAssertEqual(view.priority, 1)
        XCTAssertEqual(view.content.content, "Hello")
    }

    @MainActor func testLayoutPriorityZero() {
        let view = Text("Hello").layoutPriority(0)
        XCTAssertEqual(view.priority, 0)
    }

    @MainActor func testLayoutPriorityNegative() {
        let view = Text("Hello").layoutPriority(-1)
        XCTAssertEqual(view.priority, -1)
    }

    // MARK: - FixedSizeView

    @MainActor func testFixedSizeDefaults() {
        let view = Text("Hello").fixedSize()
        XCTAssertTrue(view.horizontal)
        XCTAssertTrue(view.vertical)
    }

    @MainActor func testFixedSizeHorizontalOnly() {
        let view = Text("Hello").fixedSize(horizontal: true, vertical: false)
        XCTAssertTrue(view.horizontal)
        XCTAssertFalse(view.vertical)
    }

    @MainActor func testFixedSizeVerticalOnly() {
        let view = Text("Hello").fixedSize(horizontal: false, vertical: true)
        XCTAssertFalse(view.horizontal)
        XCTAssertTrue(view.vertical)
    }

    // MARK: - Chaining

    @MainActor func testPositionWithFrame() {
        let view = Text("Hello")
            .frame(width: 100, height: 50)
            .position(x: 200, y: 300)
        XCTAssertEqual(view.x, 200)
        XCTAssertEqual(view.y, 300)
    }

    @MainActor func testLayoutPriorityWithOtherModifiers() {
        let view = Text("Hello")
            .padding()
            .layoutPriority(2)
        XCTAssertEqual(view.priority, 2)
    }
}
