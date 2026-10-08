import XCTest
import SwiftOpenUI

final class SwiftUIBackendTests: XCTestCase {
    func testFacadeExportsNativeSwiftUITypes() {
        XCTAssertEqual(String(reflecting: Text.self), "SwiftUI.Text")
        XCTAssertEqual(String(reflecting: Binding<Int>.self), "SwiftUI.Binding<Swift.Int>")
    }
}
