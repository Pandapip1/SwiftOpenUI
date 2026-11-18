import Foundation

extension Font {
    /// The text style a scaled metric follows (SwiftUI's `Font.TextStyle`).
    public enum TextStyle: Sendable, Hashable, CaseIterable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
    }
}

extension DynamicTypeSize {
    /// How much larger than the default (`.large`) text is at this size,
    /// following the platform type ramps' body style.
    public var scaleFactor: Double {
        switch self {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .xLarge: 1.12
        case .xxLarge: 1.24
        case .xxxLarge: 1.35
        case .accessibility1: 1.65
        case .accessibility2: 1.94
        case .accessibility3: 2.35
        case .accessibility4: 2.76
        case .accessibility5: 3.12
        }
    }
}

/// A dimension that grows and shrinks with the user's text size (SwiftUI's
/// `ScaledMetric`): control heights, icon sizes and spacing next to text.
/// Read at render time from the environment's `dynamicTypeSize`.
@propertyWrapper
public struct ScaledMetric<Value: BinaryFloatingPoint & Sendable>: Sendable {
    private let base: Value

    public init(wrappedValue: Value) {
        base = wrappedValue
    }

    public init(wrappedValue: Value, relativeTo _: Font.TextStyle) {
        base = wrappedValue
    }

    public var wrappedValue: Value {
        base * Value(getCurrentEnvironment().dynamicTypeSize.scaleFactor)
    }
}
