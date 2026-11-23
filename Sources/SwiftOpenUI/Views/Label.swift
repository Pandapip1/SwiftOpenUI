/// A view that displays an icon alongside a text label.
public struct Label: View {
    public typealias Body = Never

    public let title: String
    public let systemImage: String?
    public let imagePath: String?

    /// Create a label with a system icon name.
    public init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        self.imagePath = nil
    }

    /// Create a label with an image file path.
    public init(_ title: String, image: String) {
        self.title = title
        self.systemImage = nil
        self.imagePath = image
    }

    public var body: Never { fatalError("Label is a primitive view") }
}

/// How a label shows its title and icon.
public enum LabelStyleKind: Sendable, Equatable {
    case automatic, titleAndIcon, iconOnly, titleOnly
}

extension Label {
    /// Shows only the icon (the title stays as its accessibility label) or
    /// only the title; `automatic` and `titleAndIcon` show both.
    @ViewBuilder
    public func labelStyle(_ style: LabelStyleKind) -> some View {
        switch style {
        case .iconOnly:
            if let systemImage {
                Image(systemName: systemImage).accessibilityLabel(title)
            } else {
                self
            }
        case .titleOnly:
            Text(title)
        case .automatic, .titleAndIcon:
            self
        }
    }
}

extension View where Self: Equatable {
    /// SwiftUI skips redrawing an equatable view whose value did not change;
    /// these backends compare in their own diffing, so this is the view itself.
    public func equatable() -> Self { self }
}
