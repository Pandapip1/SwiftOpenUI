#if canImport(SwiftUI)
import SwiftUI

/// A determinate circular progress indicator: a faint full circle and an arc
/// from twelve o'clock covering `fraction` of it. Same API as the portable
/// implementation.
public struct ProgressRing: View {
    private let fraction: Double
    private let lineWidth: Double

    public init(fraction: Double, lineWidth: Double = 2) {
        self.fraction = min(max(fraction, 0), 1)
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.3), lineWidth: lineWidth)
            Circle().trim(from: 0, to: fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
#endif
