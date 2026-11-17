import XCTest
@testable import SwiftOpenUICore

/// The OARS filter → age limit used for malcontent's parental controls.
final class OARSTests: XCTestCase {
    func testNoFilterNoLimit() {
        XCTAssertNil(OARS.contentAgeLimit(filter: [:]))
        XCTAssertNil(OARS.contentAgeLimit(filter: ["violence-realistic": "intense", "sex-themes": "intense"]))
    }

    func testEachCategoryLimitsBelowItsNextLevel() {
        // Mild realistic violence is allowed; moderate is for 9 and up.
        XCTAssertEqual(OARS.contentAgeLimit(filter: ["violence-realistic": "mild"]), 8)
        // No sexual violence at all: it starts at 18.
        XCTAssertEqual(OARS.contentAgeLimit(filter: ["violence-sexual": "none"]), 17)
        XCTAssertEqual(OARS.contentAgeLimit(filter: ["money-gambling": "moderate"]), 17)
    }

    func testStrictestCategoryWins() {
        XCTAssertEqual(OARS.contentAgeLimit(filter: [
            "violence-sexual": "none", "language-profanity": "mild", "drugs-alcohol": "intense",
        ]), 10)
    }

    func testLimitNeverGoesBelowZero() {
        // Mild "social-info" is already appropriate at 0.
        XCTAssertEqual(OARS.contentAgeLimit(filter: ["social-info": "none"]), 0)
    }

    func testUnknownCategoryOrLevelIsStrict() {
        XCTAssertEqual(OARS.contentAgeLimit(filter: ["future-category": "mild"]), 0)
        XCTAssertEqual(OARS.contentAgeLimit(filter: ["violence-realistic": "unexpected"]), 3)
    }

    func testTableIsCompleteAndNonDecreasing() {
        for (category, ages) in OARS.ages {
            XCTAssertEqual(ages.count, 4, category)
            XCTAssertEqual(ages, ages.sorted(), category)
        }
    }
}
