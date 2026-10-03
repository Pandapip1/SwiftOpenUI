import XCTest
import SwiftOpenUI
@testable import BackendGTK4
import SwiftOpenUISymbols
import CGTK

/// Codepoints are read out of the bundled font rather than kept in a table, so
/// these check the reader actually resolves what the SF map promises.
final class GTK4SymbolCodepointResolutionTests: XCTestCase {
    func testEveryMappedNameResolvesInTheFont() {
        var unresolved: [String] = []
        for (sfName, material) in SFSymbolCompatibility.map
        where MaterialSymbolsCodepoints.codepoint(for: material) == nil {
            unresolved.append("\(sfName) → \(material)")
        }
        XCTAssertTrue(
            unresolved.isEmpty,
            "no ligature in the bundled font for: \(unresolved.sorted().joined(separator: ", "))")
    }

    func testPlaceholderResolves() {
        XCTAssertNotNil(
            MaterialSymbolsCodepoints.codepoint(for: SFSymbolCompatibility.missingSymbolPlaceholderName),
            "the missing-icon placeholder must itself be drawable")
    }

    /// Everything resolves into the Private Use Area, which is where the icon
    /// glyphs live; a result outside it would mean the reader matched a letter.
    func testResolvedCodepointsAreInThePrivateUseArea() {
        for (_, material) in SFSymbolCompatibility.map {
            guard let codepoint = MaterialSymbolsCodepoints.codepoint(for: material) else { continue }
            XCTAssertTrue(
                (0xE000...0xF8FF).contains(codepoint),
                "\(material) resolved to U+\(String(codepoint, radix: 16, uppercase: true)), outside the PUA")
        }
    }

    /// Distinct names that are genuinely distinct icons must not collapse onto
    /// one glyph, which would mean the ligature walk matched the wrong entry.
    func testDistinctIconsResolveDistinctly() {
        let a = MaterialSymbolsCodepoints.codepoint(for: "home")
        let b = MaterialSymbolsCodepoints.codepoint(for: "settings")
        let c = MaterialSymbolsCodepoints.codepoint(for: "search")
        XCTAssertNotNil(a); XCTAssertNotNil(b); XCTAssertNotNil(c)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(b, c)
        XCTAssertNotEqual(a, c)
    }


    func testUnknownNameResolvesToNothing() {
        XCTAssertNil(MaterialSymbolsCodepoints.codepoint(for: "definitely_not_an_icon_name"))
    }
}
