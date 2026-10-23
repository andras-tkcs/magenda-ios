/// A pen color the binder offers.
public enum BinderPen: String, CaseIterable, Sendable {
    case black
    case blue
    case red
    case green

    /// The ink color.
    public var color: RGBColor {
        switch self {
        case .black:
            RGBColor(red: 0, green: 0, blue: 0)
        case .blue:
            RGBColor(red: 31, green: 95, blue: 209)
        case .red:
            RGBColor(red: 209, green: 47, blue: 47)
        case .green:
            RGBColor(red: 30, green: 140, blue: 69)
        }
    }

    /// What the pen is called on screen.
    public var name: String {
        switch self {
        case .black:
            "Black"
        case .blue:
            "Blue"
        case .red:
            "Red"
        case .green:
            "Green"
        }
    }
}

/// What a touch on a binder page does.
public enum BinderTool: Equatable, Sendable {
    /// Writes in the pen's color.
    case pen(BinderPen)
    /// Erases strokes.
    case eraser
}
