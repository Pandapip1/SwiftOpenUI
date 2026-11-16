import Foundation

/// How much of an interpolated value a log message may reveal.
///
/// The same spellings as Apple's: `.public`, `.private`, `.sensitive`,
/// `.private(mask: .hash)` and `.auto`. As on Apple platforms, `.auto` keeps
/// scalars (integers, floating-point numbers, booleans) and keeps everything
/// else redacted. Redacted values are revealed only when the process runs with
/// `SWIFTOPENUI_LOG_PRIVATE=1`, the counterpart of enabling private data in a
/// logging profile.
public struct OSLogPrivacy: Sendable, Equatable {
    public struct Mask: Sendable, Equatable {
        enum Kind: Sendable, Equatable { case none, hash }
        let kind: Kind
        /// Replaces the redacted value with a stable hash, so equal values
        /// can be correlated across messages without revealing them.
        public static let hash = Mask(kind: .hash)
        public static let none = Mask(kind: .none)
    }

    enum Level: Sendable, Equatable { case auto, `public`, `private`, sensitive }

    let level: Level
    let mask: Mask

    public static let auto = OSLogPrivacy(level: .auto, mask: .none)
    public static let `public` = OSLogPrivacy(level: .public, mask: .none)
    public static let `private` = OSLogPrivacy(level: .private, mask: .none)
    /// Never revealed, not even with private data enabled.
    public static let sensitive = OSLogPrivacy(level: .sensitive, mask: .none)

    public static func auto(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(level: .auto, mask: mask) }
    public static func `private`(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(level: .private, mask: mask) }
    public static func sensitive(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(level: .sensitive, mask: mask) }
}

/// Integer formats accepted by `OSLogMessage` interpolation.
public struct OSLogIntegerFormatting: Sendable, Equatable {
    enum Radix: Sendable, Equatable { case decimal, hex, octal }
    let radix: Radix
    let explicitPositiveSign: Bool
    let includePrefix: Bool

    public static let decimal = OSLogIntegerFormatting(radix: .decimal, explicitPositiveSign: false, includePrefix: false)
    public static let hex = OSLogIntegerFormatting(radix: .hex, explicitPositiveSign: false, includePrefix: false)
    public static let octal = OSLogIntegerFormatting(radix: .octal, explicitPositiveSign: false, includePrefix: false)

    public static func decimal(explicitPositiveSign: Bool = false) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: .decimal, explicitPositiveSign: explicitPositiveSign, includePrefix: false)
    }

    public static func hex(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: .hex, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix)
    }

    func format(_ value: some BinaryInteger) -> String {
        let sign = explicitPositiveSign && value > 0 ? "+" : ""
        switch radix {
        case .decimal: return sign + String(value)
        case .hex: return sign + (includePrefix ? "0x" : "") + String(value, radix: 16)
        case .octal: return sign + (includePrefix ? "0o" : "") + String(value, radix: 8)
        }
    }
}

/// Floating-point formats accepted by `OSLogMessage` interpolation.
public struct OSLogFloatFormatting: Sendable, Equatable {
    let precision: Int?

    public static let fixed = OSLogFloatFormatting(precision: 6)
    public static func fixed(precision: Int) -> OSLogFloatFormatting { OSLogFloatFormatting(precision: precision) }
    public static let general = OSLogFloatFormatting(precision: nil)

    func format(_ value: Double) -> String {
        guard let precision else { return String(value) }
        return String(format: "%.\(precision)f", value)
    }
}

/// Alignment accepted by `OSLogMessage` interpolation (padding is ignored).
public struct OSLogStringAlignment: Sendable, Equatable {
    public static let none = OSLogStringAlignment()
    public static func right(columns: Int) -> OSLogStringAlignment { OSLogStringAlignment() }
    public static func left(columns: Int) -> OSLogStringAlignment { OSLogStringAlignment() }
}

/// Bool formats accepted by `OSLogMessage` interpolation.
public enum OSLogBoolFormat: Sendable, Equatable {
    case truth, answer
}

/// A log message built by string interpolation, keeping each interpolated
/// value's privacy so it is redacted when the message is written, the
/// counterpart of Apple's `OSLogMessage`.
public struct OSLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral, Sendable {
    struct Segment: Sendable, Equatable {
        let text: String
        /// nil for literal text, which is always public.
        let privacy: OSLogPrivacy?
        /// Whether `.auto` resolves to public (scalars do).
        let scalar: Bool
    }

    let segments: [Segment]

    public init(stringLiteral value: String) {
        segments = [Segment(text: value, privacy: nil, scalar: false)]
    }

    public init(stringInterpolation: StringInterpolation) {
        segments = stringInterpolation.segments
    }

    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        var segments: [Segment] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            segments.reserveCapacity(interpolationCount * 2 + 1)
        }

        public mutating func appendLiteral(_ literal: String) {
            segments.append(Segment(text: literal, privacy: nil, scalar: false))
        }

        public mutating func appendInterpolation(
            _ value: @autoclosure () -> String, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            segments.append(Segment(text: value(), privacy: privacy, scalar: false))
        }

        public mutating func appendInterpolation<T: CustomStringConvertible>(
            _ value: @autoclosure () -> T, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            segments.append(Segment(text: value().description, privacy: privacy, scalar: false))
        }

        public mutating func appendInterpolation<T: BinaryInteger>(
            _ value: @autoclosure () -> T, format: OSLogIntegerFormatting = .decimal,
            align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            segments.append(Segment(text: format.format(value()), privacy: privacy, scalar: true))
        }

        // Concrete overloads, so integers are not taken by the
        // CustomStringConvertible overload (and redacted as strings would be).
        public mutating func appendInterpolation(
            _ value: @autoclosure () -> Int, format: OSLogIntegerFormatting = .decimal,
            align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            appendInteger(value(), format: format, privacy: privacy)
        }

        public mutating func appendInterpolation(
            _ value: @autoclosure () -> Int32, format: OSLogIntegerFormatting = .decimal,
            align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            appendInteger(value(), format: format, privacy: privacy)
        }

        public mutating func appendInterpolation(
            _ value: @autoclosure () -> Int64, format: OSLogIntegerFormatting = .decimal,
            align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            appendInteger(value(), format: format, privacy: privacy)
        }

        public mutating func appendInterpolation(
            _ value: @autoclosure () -> UInt, format: OSLogIntegerFormatting = .decimal,
            align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            appendInteger(value(), format: format, privacy: privacy)
        }

        public mutating func appendInterpolation(
            _ value: @autoclosure () -> UInt32, format: OSLogIntegerFormatting = .decimal,
            align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            appendInteger(value(), format: format, privacy: privacy)
        }

        public mutating func appendInterpolation(
            _ value: @autoclosure () -> UInt64, format: OSLogIntegerFormatting = .decimal,
            align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            appendInteger(value(), format: format, privacy: privacy)
        }

        mutating func appendInteger(_ value: some BinaryInteger, format: OSLogIntegerFormatting, privacy: OSLogPrivacy) {
            segments.append(Segment(text: format.format(value), privacy: privacy, scalar: true))
        }

        public mutating func appendInterpolation(
            _ value: @autoclosure () -> Double, format: OSLogFloatFormatting = .fixed,
            align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            segments.append(Segment(text: format.format(value()), privacy: privacy, scalar: true))
        }

        public mutating func appendInterpolation(
            _ value: @autoclosure () -> Float, format: OSLogFloatFormatting = .fixed,
            align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            segments.append(Segment(text: format.format(Double(value())), privacy: privacy, scalar: true))
        }

        public mutating func appendInterpolation(
            _ value: @autoclosure () -> Bool, format: OSLogBoolFormat = .truth, privacy: OSLogPrivacy = .auto
        ) {
            let text: String = switch format {
            case .truth: value() ? "true" : "false"
            case .answer: value() ? "YES" : "NO"
            }
            segments.append(Segment(text: text, privacy: privacy, scalar: true))
        }

        public mutating func appendInterpolation(
            _ value: @autoclosure () -> any Any.Type, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto
        ) {
            segments.append(Segment(text: String(reflecting: value()), privacy: privacy, scalar: true))
        }
    }

    /// The message as text, with each value redacted as its privacy demands.
    public func formatted(revealPrivate: Bool) -> String {
        var result = ""
        for segment in segments {
            guard let privacy = segment.privacy else {
                result += segment.text
                continue
            }
            let visible: Bool = switch privacy.level {
            case .public: true
            case .auto: segment.scalar || revealPrivate
            case .private: revealPrivate
            case .sensitive: false
            }
            if visible {
                result += segment.text
            } else if privacy.mask == .hash {
                result += "<mask.hash: '\(Self.stableHash(segment.text))'>"
            } else {
                result += "<private>"
            }
        }
        return result
    }

    /// FNV-1a, stable across processes (unlike `Hasher`), so redacted values
    /// can be matched between log lines and launches.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 36)
    }
}
