import XCTest
@_spi(SwiftOpenUIBackend) @testable import SwiftOpenUICore

final class ContextMenuTests: XCTestCase {
    private struct CustomButtonLabel: View {
        var body: some View { Text("Custom") }
    }

    func testContextMenuWrapsContent() {
        let view = Text("Hello").contextMenu { Button("Copy") {} }
        let _: any View = view
    }

    func testContextMenuMultipleButtons() {
        let view = Text("Hello").contextMenu {
            Button("Copy") {}
            Button("Delete", role: .destructive) {}
        }
        let _: any View = view
    }

    func testContextMenuUsesButtonAction() {
        var fired = false
        let view = Text("Hello").contextMenu {
            Button("Remove", role: .destructive) { fired = true }
        }
        let _: any View = view
        let menuElements = AlertActions.menuElements(from: Button("Remove", role: .destructive) { fired = true })
        if case .item(let label, _, _, let action) = menuElements[0] {
            XCTAssertEqual(label, "Remove")
            action()
            XCTAssertTrue(fired)
        } else {
            XCTFail("Expected button item")
        }
    }

    func testContextMenuKeepsCustomButtonLabelsAccessible() {
        let elements = AlertActions.menuElements(from: Button(action: {}, label: { CustomButtonLabel() }))
        if case .item(let label, _, _, _) = elements[0] {
            XCTAssertEqual(label, "Custom")
        } else { XCTFail("Expected custom-label button item") }
    }

    func testContextMenuPreservesButtonThroughDisabledWrapper() {
        let elements = AlertActions.menuElements(from: Button("Copy") {}.disabled(true))
        if case .item(let label, _, _, let action) = elements[0] {
            XCTAssertEqual(label, "Copy")
            action() // disabled actions remain represented but are inert
        } else { XCTFail("Expected disabled button item") }
    }

    func testContextMenuDisablesNestedMenuItemsRecursively() {
        let elements = AlertActions.menuElements(from: Menu("More") {
            Button("Nested") {}
            Menu("Deep") { Button("Deep item") {} }
        }.disabled(true))
        if case .submenu(let label, let children) = elements[0] {
            XCTAssertEqual(label, "More")
            if case .item(_, _, let enabled, _) = children[0] { XCTAssertFalse(enabled) }
            if case .submenu(_, let deep) = children[1], case .item(_, _, let enabled, _) = deep[0] {
                XCTAssertFalse(enabled)
            } else { XCTFail("Expected disabled nested submenu") }
        } else { XCTFail("Expected submenu") }
    }

    func testContextMenuExtractsModifiedButtonAndMenuLabels() {
        let button = Button(action: {}, label: { Text("Styled").font(.headline) })
        let buttonElements = AlertActions.menuElements(from: button)
        if case .item(let label, _, _, _) = buttonElements[0] { XCTAssertEqual(label, "Styled") }
        else { XCTFail("Expected modified button label") }
        let menuElements = AlertActions.menuElements(from: Menu(content: { Button("Item") {} }, label: { Text("Styled Menu").font(.headline) }))
        if case .submenu(let label, _) = menuElements[0] { XCTAssertEqual(label, "Styled Menu") }
        else { XCTFail("Expected modified menu label") }
    }

    func testContextMenuExtractsCompositeAndAccessibilityLabels() {
        let composite = Button(action: {}, label: { HStack { Text("Open"); Text("Now") } })
        if case .item(let label, _, _, _) = AlertActions.menuElements(from: composite)[0] {
            XCTAssertEqual(label, "Open Now")
        } else { XCTFail("Expected composite button label") }
        let accessible = Button(action: {}, label: { Text("Icon").accessibilityLabel("Play") })
        if case .item(let label, _, _, _) = AlertActions.menuElements(from: accessible)[0] {
            XCTAssertEqual(label, "Play")
        } else { XCTFail("Expected accessibility label") }
    }

    func testContextMenuExtractsMenusDividersGroupsConditionalsAndForEach() {
        let includeConditional = true
        let menuContent = Group {
            Button("Copy") {}
            Divider()
            if includeConditional { Button("Conditional") {} }
            Menu("More") {
                Button("Nested", role: .destructive) {}
            }
            ForEach(0..<2) { Button("Item \($0)") {} }
        }
        let view = _ContextMenuView(content: Text("row"), menuContent: menuContent)
        let elements = view.menuElements
        XCTAssertEqual(elements.count, 6)
        if case .divider = elements[1] {} else { XCTFail("Expected divider") }
        if case .submenu(let title, let children) = elements[3] {
            XCTAssertEqual(title, "More")
            XCTAssertEqual(children.count, 1)
            if case .item(let label, let role, let enabled, _) = children[0] {
                XCTAssertEqual(label, "Nested")
                XCTAssertEqual(role, .destructive)
                XCTAssertTrue(enabled)
            } else { XCTFail("Expected nested button") }
        } else { XCTFail("Expected submenu") }
        if case .item(let label, _, _, _) = elements[4] { XCTAssertEqual(label, "Item 0") }
        else { XCTFail("Expected ForEach button") }
    }

    func testContextMenuSupportsConditionalButtons() {
        let includeCopy = true
        let view = Text("Hello").contextMenu {
            if includeCopy { Button("Copy") {} }
            Button("Delete") {}
        }
        let _: any View = view
    }

    func testContextMenuItemLabels() {
        let menuElements = AlertActions.menuElements(from: TupleView((Button("Cut") {}, Button("Copy") {}, Button("Paste") {})))
        if case .item(let label, _, _, _) = menuElements[0] {
            XCTAssertEqual(label, "Cut")
        } else { XCTFail("Expected item") }
        if case .item(let label, _, _, _) = menuElements[2] {
            XCTAssertEqual(label, "Paste")
        } else { XCTFail("Expected item") }
    }

    func testContextMenuChainedWithOtherModifiers() {
        let view = Text("Hello").padding().contextMenu { Button("Copy") {} }
        let _: any View = view
    }
}
