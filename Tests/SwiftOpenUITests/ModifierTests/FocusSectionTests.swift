import XCTest
@testable import SwiftOpenUI

final class FocusSectionTests: XCTestCase {
    func testFocusSectionPreservesContentOnBackendWithoutFocusEngine() {
        let view = Text("Player controls").focusSection()

        XCTAssertEqual(String(describing: type(of: view)), "Text")
    }
}
