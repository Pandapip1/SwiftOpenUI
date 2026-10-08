import XCTest
@testable import SwiftOpenUICore

final class InterfaceSizeClassTests: XCTestCase {
    func testDesktopDefaultsAndExplicitSizeClasses() {
        var environment = EnvironmentValues()
        XCTAssertNil(environment.horizontalSizeClass)
        XCTAssertNil(environment.verticalSizeClass)

        environment.horizontalSizeClass = .compact
        environment.verticalSizeClass = .regular
        XCTAssertEqual(environment.horizontalSizeClass, .compact)
        XCTAssertEqual(environment.verticalSizeClass, .regular)
    }
}
