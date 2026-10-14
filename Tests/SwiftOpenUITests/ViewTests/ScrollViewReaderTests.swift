import XCTest
@testable import SwiftOpenUICore

final class ScrollViewReaderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { clearViewIDRegistry() }
    }

    // MARK: - IdView

    @MainActor func testIdViewWrapsContent() {
        let view = Text("Hello").id(42)
        XCTAssertEqual(view.id, 42)
        XCTAssertEqual(view.content.content, "Hello")
    }

    @MainActor func testIdViewStringID() {
        let view = Text("Hello").id("item-1")
        XCTAssertEqual(view.id, "item-1")
    }

    // MARK: - ID Registry

    @MainActor func testRegisterAndLookup() {
        registerViewID(42, element: "test-widget")
        let found = lookupViewID(42) as? String
        XCTAssertEqual(found, "test-widget")
    }

    @MainActor func testLookupMissReturnsNil() {
        let found = lookupViewID(99)
        XCTAssertNil(found)
    }

    @MainActor func testClearRegistryRemovesAll() {
        registerViewID(1, element: "a")
        registerViewID(2, element: "b")
        clearViewIDRegistry()
        XCTAssertNil(lookupViewID(1))
        XCTAssertNil(lookupViewID(2))
    }

    @MainActor func testRegisterOverwritesPrevious() {
        registerViewID(1, element: "old")
        registerViewID(1, element: "new")
        XCTAssertEqual(lookupViewID(1) as? String, "new")
    }

    // MARK: - UnitPoint

    @MainActor func testUnitPointPresets() {
        XCTAssertEqual(UnitPoint.zero, UnitPoint(x: 0, y: 0))
        XCTAssertEqual(UnitPoint.center, UnitPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(UnitPoint.top, UnitPoint(x: 0.5, y: 0))
        XCTAssertEqual(UnitPoint.bottom, UnitPoint(x: 0.5, y: 1))
    }

    // MARK: - ScrollViewProxy

    @MainActor func testScrollViewProxyCallsAction() {
        var scrolledTo: AnyHashable?
        var proxy = ScrollViewProxy()
        proxy.scrollToAction = { id, _ in scrolledTo = id }
        proxy.scrollTo(42)
        XCTAssertEqual(scrolledTo, AnyHashable(42))
    }

    @MainActor func testScrollViewProxyWithAnchor() {
        var receivedAnchor: UnitPoint?
        var proxy = ScrollViewProxy()
        proxy.scrollToAction = { _, anchor in receivedAnchor = anchor }
        proxy.scrollTo("item", anchor: .top)
        XCTAssertEqual(receivedAnchor, .top)
    }

    @MainActor func testScrollViewProxyDefaultAnchorIsNil() {
        var receivedAnchor: UnitPoint? = .center
        var proxy = ScrollViewProxy()
        proxy.scrollToAction = { _, anchor in receivedAnchor = anchor }
        proxy.scrollTo(1)
        XCTAssertNil(receivedAnchor)
    }

    // MARK: - ScrollViewReader

    @MainActor func testScrollViewReaderProvideProxy() {
        var proxyReceived = false
        _ = ScrollViewReader { proxy in
            proxyReceived = true
            return Text("Content")
        }
        // The closure is stored, not called yet — verify it compiles
        XCTAssertFalse(proxyReceived)
    }
}
