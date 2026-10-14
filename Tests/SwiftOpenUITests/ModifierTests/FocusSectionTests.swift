import XCTest
@testable import SwiftOpenUICore

final class FocusSectionTests: XCTestCase {
    @MainActor func testFocusSectionPreservesContentOnBackendWithoutFocusEngine() {
        let view = Text("Player controls").focusSection()

        XCTAssertEqual(String(describing: type(of: view)), "Text")
    }
}
