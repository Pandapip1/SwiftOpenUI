/// A horizontal slider for selecting a value from a range.
public struct Slider: View {
    public typealias Body = Never

    public let value: Binding<Double>
    public let range: ClosedRange<Double>
    public let step: Double
    public let onEditingChanged: (Bool) -> Void

    public init(value: Binding<Double>, in range: ClosedRange<Double> = 0...1,
                step: Double = 0.01, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.value = value
        self.range = range
        self.step = step
        self.onEditingChanged = onEditingChanged
    }

    public var body: Never { fatalError("Slider is a primitive view") }
}
