/// Horizontal alignment for children within a VStack.
public enum HorizontalAlignment {
    case leading
    case center
    case trailing
}

/// Vertical alignment for children within an HStack.
public enum VerticalAlignment {
    case top
    case center
    case bottom

    /// Text baselines. These backends lay rows out by their edges, so the
    /// first baseline is the top and the last the bottom (equal for one line
    /// of same-size text, the usual case).
    public static var firstTextBaseline: VerticalAlignment { .top }
    public static var lastTextBaseline: VerticalAlignment { .bottom }
}

/// Two-dimensional alignment for ZStack and frame alignment.
public enum Alignment {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing
}
