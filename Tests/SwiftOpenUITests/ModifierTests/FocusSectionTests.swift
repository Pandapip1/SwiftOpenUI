import XCTest
@testable import SwiftOpenUICore

final class FocusSectionTests: XCTestCase {
    func testFocusSectionPreservesContentOnBackendWithoutFocusEngine() {
        let view = Text("Player controls").focusSection()

        XCTAssertEqual(String(describing: type(of: view)), "Text")
    }
}
