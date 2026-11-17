import Foundation

/// A determinate circular progress indicator: a faint full circle and an arc
/// from twelve o'clock covering `fraction` of it. One API on every backend
/// (SwiftUI: a trimmed circle; other renderers: an arc path).
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
            ProgressArc(fraction: fraction).stroke(Color.blue, lineWidth: lineWidth)
        }
    }
}

private struct ProgressArc: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0 else { return path }
        let radius = min(rect.width, rect.height) / 2
        let start = -Double.pi / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: start, endAngle: start + 2 * Double.pi * fraction, clockwise: false)
        return path
    }
}
