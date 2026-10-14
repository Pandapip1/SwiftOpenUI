import XCTest
@testable import SwiftOpenUICore

final class OnSubmitTests: XCTestCase {

    // MARK: - OnSubmitView

    @MainActor func testOnSubmitWrapsContent() {
        var submitted = false
        let view = Text("Hello").onSubmit { submitted = true }
        XCTAssertEqual(view.content.content, "Hello")
        XCTAssertEqual(view.triggers, .text)
        XCTAssertFalse(submitted)
    }

    @MainActor func testOnSubmitSearchTrigger() {
        let view = Text("Hello").onSubmit(of: .search) {}
        XCTAssertEqual(view.triggers, .search)
    }

    // MARK: - SubmitAction

    @MainActor func testSubmitActionCallable() {
        var called = false
        let action = SubmitAction { called = true }
        action()
        XCTAssertTrue(called)
    }

    // MARK: - Environment

    @MainActor func testSubmitActionEnvironmentDefault() {
        let env = EnvironmentValues()
        XCTAssertNil(env.submitAction)
    }

    @MainActor func testSubmitActionEnvironmentSet() {
        var env = EnvironmentValues()
        var called = false
        env.submitAction = SubmitAction { called = true }
        env.submitAction?()
        XCTAssertTrue(called)
    }

    // MARK: - Chaining

    @MainActor func testOnSubmitChainedWithTextField() {
        var submitted = false
        let binding = Binding<String>(get: { "" }, set: { _ in })
        let view = TextField("Name", text: binding)
            .onSubmit { submitted = true }
        XCTAssertEqual(view.triggers, .text)
        XCTAssertFalse(submitted)
    }
}
