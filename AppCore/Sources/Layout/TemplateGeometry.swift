/// Measured positions on the template pages, in points with the origin at the top left.
enum TemplateGeometry {
    /// The right edge of the page content that headers and labels may reach.
    static let contentRight = 574.1
    /// The right edge of a meeting title.
    static let meetingTitleRight = 566.95
    /// The widest a meeting title may be.
    static let meetingTitleWidth = 330.15
    /// The box the "Summary:" label sits in, below a meeting title.
    static let meetingSummaryBox = PlanRect(x0: 56.8, y0: 114.0, x1: 566.95, y1: 134.0)
    /// The gap between the "Summary:" label and the routine names.
    static let meetingSummaryGap = 6.0
    /// The nominal size of the "Summary:" line.
    static let meetingSummaryPoints = 12.0

    /// The left edge of the to-do grid.
    static let todoGridX0 = 56.7
    /// The right edge of the to-do grid.
    static let todoGridX1 = 297.0
    /// The top of the first to-do row.
    static let todoTop = 144.95
    /// The height of a base to-do row.
    static let todoBaseRow = 28.35
    /// The lowest a to-do row may end, before the half-point allowance.
    static let todoBottom = 655.25
    /// The color of the ruled lines between to-do rows.
    static let todoLineColor = RGBColor(red: 0x08, green: 0x30, blue: 0x50)
    /// The width of the ruled lines between to-do rows.
    static let todoLineWidth = 0.75
    /// The side of a to-do checkbox.
    static let checkboxSize = 6.48
    /// The horizontal center of a to-do checkbox.
    static let checkboxCenterX = 65.8
    /// The stroke width of a to-do checkbox.
    static let checkboxLineWidth = 0.75
    /// The left edge of the to-do task text.
    static let todoTaskX0 = 97.4
    /// The right edge of the to-do task text.
    static let todoTaskX1 = 216.4
    /// The widest a to-do task line may be.
    static let todoTaskWidth = 119.0
    /// The left edge of the to-do due text.
    static let todoDueX0 = 222.4
    /// The right edge of the to-do due text.
    static let todoDueX1 = 293.0
    /// The widest a to-do due date may be.
    static let todoDueWidth = 70.6
    /// The left edge of the "TO-DO LIST" band.
    static let todoBandX0 = 56.7
    /// The right edge of the "TO-DO LIST" band.
    static let todoBandX1 = 293.15
    /// The area that hides the template's own to-do grid.
    static let todoErase = PlanRect(x0: 55.7, y0: 146.0, x1: 298.0, y1: 656.5)

    /// The left edge of the "DAILY SCHEDULE" band.
    static let scheduleBandX0 = 326.0
    /// The right edge of the "DAILY SCHEDULE" band.
    static let scheduleBandX1 = 574.05
    /// The left edge of schedule text.
    static let scheduleTextX0 = 366.9
    /// The right edge of schedule text.
    static let scheduleTextX1 = 568.7
    /// The widest a schedule entry may be.
    static let scheduleTextWidth = 201.8

    /// The widths of the delegated table's columns, left to right.
    static let delegatedColumns = (number: 30.75, task: 173.2, owner: 84.45, status: 229.0)
    /// The space between a delegated cell's edge and its text.
    static let delegatedCellInset = 5.4
    /// The lowest a delegated row may end.
    static let delegatedMaxY = 628.2
    /// The area that hides the line the template draws under the delegated table's header.
    static let delegatedErase = PlanRect(x0: 56.2, y0: 178.3, x1: 574.6, y1: 179.8)
    /// The fill of a delegated row whose check-in is due.
    static let markedFill = RGBColor(red: 0xD6, green: 0xFC, blue: 0xEC)
    /// The width of the border above a delegated page's first row.
    static let delegatedThickBorder = 3.0
    /// The width of the other delegated borders.
    static let delegatedThinBorder = 0.5
    /// How many lines a delegated status may take.
    static let delegatedStatusLines = 10

    /// The padding of a slot's box in which its text is placed: left, top, right, bottom.
    static let slotPadding = (left: 1.5, top: 3.0, right: 1.5, bottom: 4.0)
}
