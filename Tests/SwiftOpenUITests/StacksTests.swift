import Foundation
import XCTest
@testable import SwiftOpenUICore

final class StacksTests: XCTestCase {
    @MainActor func testStackSpacingDefaultsToNilLikeSwiftUI() {
        XCTAssertNil(VStack { Text("value") }.spacing)
        XCTAssertNil(HStack { Text("value") }.spacing)
    }

    @MainActor func testStackSpacingPreservesZero() {
        XCTAssertEqual(VStack(spacing: 0) { Text("value") }.spacing, 0)
        XCTAssertEqual(HStack(spacing: 0) { Text("value") }.spacing, 0)
    }

    @MainActor func testStackSpacingPreservesFractionalValues() {
        let spacing: CGFloat = 2.5
        XCTAssertEqual(VStack(spacing: spacing) { Text("value") }.spacing, spacing)
        XCTAssertEqual(HStack(spacing: spacing) { Text("value") }.spacing, spacing)
    }
}
