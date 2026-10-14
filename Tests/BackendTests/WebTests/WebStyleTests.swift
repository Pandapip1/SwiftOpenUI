import XCTest
@testable import SwiftOpenUICore
@testable import BackendWeb

final class WebStyleTests: XCTestCase {

    // MARK: - Style environment defaults

    @MainActor

    func testButtonStyleDefaultIsAutomatic() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.buttonStyle, .automatic)
    }

    @MainActor

    func testToggleStyleDefaultIsAutomatic() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.toggleStyle, .automatic)
    }

    @MainActor

    func testTextFieldStyleDefaultIsAutomatic() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.textFieldStyle, .automatic)
    }

    // MARK: - Style environment propagation

    @MainActor

    func testButtonStylePropagatesThroughEnvironment() {
        var env = EnvironmentValues()
        env.buttonStyle = .borderedProminent
        XCTAssertEqual(env.buttonStyle, .borderedProminent)
    }

    @MainActor

    func testToggleStylePropagatesThroughEnvironment() {
        var env = EnvironmentValues()
        env.toggleStyle = .switch
        XCTAssertEqual(env.toggleStyle, .switch)
    }

    @MainActor

    func testTextFieldStylePropagatesThroughEnvironment() {
        var env = EnvironmentValues()
        env.textFieldStyle = .roundedBorder
        XCTAssertEqual(env.textFieldStyle, .roundedBorder)
    }

    // MARK: - Modifier wrapping

    @MainActor

    func testButtonStyleModifierWraps() {
        let view = Text("Tap").buttonStyle(.plain)
        XCTAssertEqual(view.style, .plain)
    }

    @MainActor

    func testToggleStyleModifierWraps() {
        let view = Text("On").toggleStyle(.switch)
        XCTAssertEqual(view.style, .switch)
    }

    @MainActor

    func testTextFieldStyleModifierWraps() {
        let view = Text("Name").textFieldStyle(.roundedBorder)
        XCTAssertEqual(view.style, .roundedBorder)
    }

    // MARK: - Chaining

    @MainActor

    func testStyleModifiersChain() {
        let view = VStack { Text("Hello") }
            .buttonStyle(.bordered)
            .toggleStyle(.checkbox)
            .textFieldStyle(.plain)
        XCTAssertEqual(view.style, .plain)
        XCTAssertEqual(view.content.style, .checkbox)
        XCTAssertEqual(view.content.content.style, .bordered)
    }
}
