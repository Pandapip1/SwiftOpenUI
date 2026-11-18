import XCTest
import Foundation
@testable import SwiftOpenUICore

/// Status colours stay legible: 4.5:1 (WCAG AA for text) against every
/// background a status message sits on, 7:1 when contrast is increased.
final class StatusColorsContrastTests: XCTestCase {
    private let light: [(Double, Double, Double)] = [(1, 1, 1), (0.949, 0.949, 0.969)]          // #FFFFFF, #F2F2F7
    private let dark: [(Double, Double, Double)] = [(0, 0, 0), (0.110, 0.110, 0.118), (0.173, 0.173, 0.180)] // #000, #1C1C1E, #2C2C2E

    func testStatusColorsMeetContrastMinimums() {
        for kind in [StatusKind.error, .warning, .success] {
            for isDark in [false, true] {
                for increased in [false, true] {
                    let color = StatusColors.components(kind, dark: isDark, increased: increased)
                    for background in isDark ? dark : light {
                        let ratio = Self.contrast(color, background)
                        XCTAssertGreaterThanOrEqual(ratio, increased ? 7 : 4.5,
                            "\(kind) dark=\(isDark) increased=\(increased) on \(background): \(ratio)")
                    }
                }
            }
        }
    }

    private static func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ c: (Double, Double, Double)) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
    }
}
