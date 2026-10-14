import XCTest
@testable import SwiftOpenUICore

final class ControlStyleTests: XCTestCase {

    // MARK: - ButtonStyleType

    @MainActor func testButtonStyleTypeEquatable() {
        XCTAssertEqual(ButtonStyleType.automatic, ButtonStyleType.automatic)
        XCTAssertEqual(ButtonStyleType.plain, ButtonStyleType.plain)
        XCTAssertNotEqual(ButtonStyleType.plain, ButtonStyleType.bordered)
        XCTAssertNotEqual(ButtonStyleType.bordered, ButtonStyleType.borderedProminent)
    }

    @MainActor func testButtonStyleEnvironmentDefault() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.buttonStyle, .automatic)
    }

    @MainActor func testButtonStyleEnvironmentSet() {
        var env = EnvironmentValues()
        env.buttonStyle = .borderedProminent
        XCTAssertEqual(env.buttonStyle, .borderedProminent)
    }

    @MainActor func testButtonStyleModifierWraps() {
        let view = Text("Tap").buttonStyle(.plain)
        XCTAssertEqual(view.style, .plain)
        XCTAssertEqual(view.content.content, "Tap")
    }

    // MARK: - ToggleStyleType

    @MainActor func testToggleStyleTypeEquatable() {
        XCTAssertEqual(ToggleStyleType.automatic, ToggleStyleType.automatic)
        XCTAssertEqual(ToggleStyleType.checkbox, ToggleStyleType.checkbox)
        XCTAssertNotEqual(ToggleStyleType.checkbox, ToggleStyleType.switch)
    }

    @MainActor func testToggleStyleEnvironmentDefault() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.toggleStyle, .automatic)
    }

    @MainActor func testToggleStyleEnvironmentSet() {
        var env = EnvironmentValues()
        env.toggleStyle = .switch
        XCTAssertEqual(env.toggleStyle, .switch)
    }

    @MainActor func testToggleStyleModifierWraps() {
        let view = Text("On").toggleStyle(.switch)
        XCTAssertEqual(view.style, .switch)
    }

    // MARK: - TextFieldStyleType

    @MainActor func testTextFieldStyleTypeEquatable() {
        XCTAssertEqual(TextFieldStyleType.automatic, TextFieldStyleType.automatic)
        XCTAssertEqual(TextFieldStyleType.plain, TextFieldStyleType.plain)
        XCTAssertNotEqual(TextFieldStyleType.plain, TextFieldStyleType.roundedBorder)
    }

    @MainActor func testTextFieldStyleEnvironmentDefault() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.textFieldStyle, .automatic)
    }

    @MainActor func testTextFieldStyleEnvironmentSet() {
        var env = EnvironmentValues()
        env.textFieldStyle = .roundedBorder
        XCTAssertEqual(env.textFieldStyle, .roundedBorder)
    }

    @MainActor func testTextFieldStyleModifierWraps() {
        let view = Text("Name").textFieldStyle(.plain)
        XCTAssertEqual(view.style, .plain)
    }

    // MARK: - Style propagation

    @MainActor func testButtonStylePropagatesThroughEnvironment() {
        var env = EnvironmentValues()
        env.buttonStyle = .bordered
        let modified = env.setting(\.buttonStyle, to: .plain)
        XCTAssertEqual(modified.buttonStyle, .plain)
        // Original unchanged
        XCTAssertEqual(env.buttonStyle, .bordered)
    }

    // MARK: - Chaining

    @MainActor func testStyleModifiersChain() {
        let view = VStack {
            Text("Hello")
        }
        .buttonStyle(.bordered)
        .toggleStyle(.switch)
        .textFieldStyle(.roundedBorder)

        XCTAssertEqual(view.style, .roundedBorder)
        XCTAssertEqual(view.content.style, .switch)
        XCTAssertEqual(view.content.content.style, .bordered)
    }
}
