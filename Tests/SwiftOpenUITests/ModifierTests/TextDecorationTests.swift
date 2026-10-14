import XCTest
@testable import SwiftOpenUICore

final class TextDecorationTests: XCTestCase {

    // MARK: - Bold

    @MainActor func testBoldWrapsContent() {
        let view = Text("Hello").bold()
        XCTAssertEqual(view.content.content, "Hello")
    }

    // MARK: - Italic

    @MainActor func testItalicWrapsContent() {
        let view = Text("Hello").italic()
        XCTAssertEqual(view.content.content, "Hello")
    }

    // MARK: - FontWeight

    @MainActor func testFontWeightWrapsContent() {
        let view = Text("Hello").fontWeight(.heavy)
        XCTAssertEqual(view.weight, .heavy)
        XCTAssertEqual(view.content.content, "Hello")
    }

    @MainActor func testFontWeightAllValues() {
        let weights: [FontWeight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        for w in weights {
            let view = Text("X").fontWeight(w)
            XCTAssertEqual(view.weight, w)
        }
    }

    // MARK: - Underline

    @MainActor func testUnderlineDefaultActive() {
        let view = Text("Hello").underline()
        XCTAssertTrue(view.isActive)
    }

    @MainActor func testUnderlineExplicitFalse() {
        let view = Text("Hello").underline(false)
        XCTAssertFalse(view.isActive)
    }

    // MARK: - Strikethrough

    @MainActor func testStrikethroughDefaultActive() {
        let view = Text("Hello").strikethrough()
        XCTAssertTrue(view.isActive)
    }

    @MainActor func testStrikethroughExplicitFalse() {
        let view = Text("Hello").strikethrough(false)
        XCTAssertFalse(view.isActive)
    }

    // MARK: - TextCase

    @MainActor func testTextCaseUppercase() {
        let view = Text("Hello").textCase(.uppercase)
        XCTAssertEqual(view.textCase, .uppercase)
    }

    @MainActor func testTextCaseLowercase() {
        let view = Text("Hello").textCase(.lowercase)
        XCTAssertEqual(view.textCase, .lowercase)
    }

    @MainActor func testTextCaseNilReset() {
        let view = Text("Hello").textCase(nil)
        XCTAssertNil(view.textCase)
    }

    // MARK: - Chaining

    @MainActor func testChainBoldItalicUnderline() {
        let view = Text("Hello")
            .bold()
            .italic()
            .underline()
        XCTAssertTrue(view.isActive)
    }

    @MainActor func testChainFontWeightWithStrikethrough() {
        let view = Text("Hello")
            .fontWeight(.semibold)
            .strikethrough()
        XCTAssertTrue(view.isActive)
        XCTAssertEqual(view.content.weight, .semibold)
    }
}
