import XCTest
@testable import SwiftOpenUICore

final class ViewBuilderTests: XCTestCase {

    // MARK: - ViewBuilder basics

    @MainActor func testBuildBlockEmpty() {
        @ViewBuilder func build() -> some View { }
        let view = build()
        XCTAssertTrue(view is EmptyView)
    }

    @MainActor func testBuildBlockSingle() {
        @ViewBuilder func build() -> some View { Text("hello") }
        let view = build()
        XCTAssertTrue(view is Text)
    }

    @MainActor func testBuildBlockTwo() {
        @ViewBuilder func build() -> some View {
            Text("a")
            Text("b")
        }
        let view = build()
        // With buildPartialBlock, multi-child results are ViewList (or TupleView2)
        XCTAssertTrue(view is MultiChildView)
        let children = (view as! MultiChildView).children
        XCTAssertEqual(children.count, 2)
    }

    @MainActor func testBuildBlockThree() {
        @ViewBuilder func build() -> some View {
            Text("a")
            Text("b")
            Text("c")
        }
        let view = build()
        XCTAssertTrue(view is MultiChildView)
        let children = (view as! MultiChildView).children
        XCTAssertEqual(children.count, 3)
    }

    @MainActor func testBuildOptionalPresent() {
        let show = true
        @ViewBuilder func build() -> some View {
            if show { Text("visible") }
        }
        let view = build()
        // Optional<Text> when present
        XCTAssertNotNil(view)
    }

    @MainActor func testBuildEitherTrue() {
        let flag = true
        @ViewBuilder func build() -> some View {
            if flag {
                Text("true")
            } else {
                Text("false")
            }
        }
        let view = build()
        XCTAssertTrue(view is _ConditionalView<Text, Text>)
    }

    // MARK: - MultiChildView

    @MainActor func testTupleViewChildren() {
        let tuple = TupleView(Text("a"), Text("b"))
        XCTAssertEqual(tuple.children.count, 2)
    }

    @MainActor func testGroupFlattensChildren() {
        let group = Group {
            Text("a")
            Text("b")
            Text("c")
        }
        XCTAssertEqual(group.children.count, 3)
    }

    // MARK: - ForEach

    @MainActor func testForEachRange() {
        let forEach = ForEach(0..<5) { i in Text("\(i)") }
        XCTAssertEqual(forEach.children.count, 5)
    }

    struct Item: Identifiable {
        let id: Int
        let name: String
    }

    @MainActor func testForEachIdentifiable() {
        let items = [Item(id: 1, name: "a"), Item(id: 2, name: "b")]
        let forEach = ForEach(items) { item in Text(item.name) }
        XCTAssertEqual(forEach.children.count, 2)
    }

    // MARK: - AnyView

    @MainActor func testAnyViewWraps() {
        let text = Text("hello")
        let any = AnyView(text)
        XCTAssertTrue(any.wrapped is Text)
    }

    // MARK: - Stacks

    @MainActor func testVStackDefaults() {
        let stack = VStack { Text("child") }
        XCTAssertEqual(stack.children.count, 1)
    }

    @MainActor func testHStackDefaults() {
        let stack = HStack { Text("child") }
        XCTAssertEqual(stack.children.count, 1)
    }

    @MainActor func testZStackDefaults() {
        let stack = ZStack { Text("child") }
        XCTAssertEqual(stack.children.count, 1)
    }

    @MainActor func testVStackMultipleChildren() {
        let stack = VStack {
            Text("a")
            Text("b")
            Text("c")
        }
        XCTAssertEqual(stack.children.count, 3)
    }
}
