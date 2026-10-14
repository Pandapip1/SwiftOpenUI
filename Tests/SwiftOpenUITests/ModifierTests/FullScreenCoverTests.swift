import XCTest
@testable import SwiftOpenUICore

final class FullScreenCoverTests: XCTestCase {

    @MainActor func testFullScreenCoverWrapsContent() {
        var presented = false
        let view = Text("Main").fullScreenCover(isPresented: .init(
            get: { presented }, set: { presented = $0 }
        )) {
            Text("Cover")
        }
        XCTAssertEqual(view.content.content, "Main")
        XCTAssertFalse(view.isPresented.wrappedValue)
    }

    @MainActor func testFullScreenCoverStoresBinding() {
        var presented = true
        let view = Text("Main").fullScreenCover(isPresented: .init(
            get: { presented }, set: { presented = $0 }
        )) {
            Text("Cover")
        }
        XCTAssertTrue(view.isPresented.wrappedValue)
    }

    @MainActor func testFullScreenCoverOnDismiss() {
        var dismissed = false
        var presented = false
        let view = Text("Main").fullScreenCover(
            isPresented: .init(get: { presented }, set: { presented = $0 }),
            onDismiss: { dismissed = true }
        ) {
            Text("Cover")
        }
        XCTAssertNotNil(view.onDismiss)
        view.onDismiss?()
        XCTAssertTrue(dismissed)
    }

    @MainActor func testFullScreenCoverChainedWithFrame() {
        var presented = false
        let view = Text("Main")
            .frame(width: 300, height: 200)
            .fullScreenCover(isPresented: .init(
                get: { presented }, set: { presented = $0 }
            )) {
                Text("Cover")
            }
        XCTAssertEqual(view.content.width, 300)
    }
}
