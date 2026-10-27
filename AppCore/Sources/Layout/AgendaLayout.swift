/// Turns agenda content into a render plan: every line of text positioned and every rule drawn.
public struct AgendaLayout: Sendable {
    let manifest: TemplateManifest
    let measurer: any TextMeasuring
    let theme: Theme

    /// Creates a layout for a template, a text measurer and a theme.
    public init(manifest: TemplateManifest, measurer: any TextMeasuring, theme: Theme) {
        self.manifest = manifest
        self.measurer = measurer
        self.theme = theme
    }

    /// The plan for `content`: the overview, the delegated pages, one page per meeting and the
    /// further-notes page.
    public func plan(for content: AgendaContent) -> RenderPlan {
        let overview = overviewPage(for: content)
        let delegated = delegatedPages(for: content)
        var pages = [overview.page] + delegated
        pages += meetingTitles(of: content).enumerated().map { index, title in
            meetingPage(
                title: title, key: meetingKey(at: index, in: content),
                routines: content.meetingSummaryRoutines.indices.contains(index)
                    ? content.meetingSummaryRoutines[index] : [])
        }
        pages.append(furtherNotesPage())
        let header = headerOperations(for: content.date)
        return RenderPlan(
            pageWidth: manifest.pageWidth, pageHeight: manifest.pageHeight,
            pages: addingLinks(
                to: pages.map {
                    PagePlan(key: $0.key, chrome: $0.chrome, operations: $0.operations + header)
                },
                schedule: content.schedule, delegatedPageCount: delegated.count),
            omittedTodoItems: overview.omitted)
    }

    var fitter: TextFitter { TextFitter(measurer: measurer) }

    var placer: TextPlacer { TextPlacer(measurer: measurer) }

    func font(for slot: TemplateSlot) -> FontSpec {
        FontSpec.nominal(theme.fontPack, slot.weight, slot.points)
    }

    func color(for slot: TemplateSlot) -> RGBColor {
        theme.colors.color(for: slot.role)
    }

    /// The slots of one template page; a page the manifest does not list has none.
    func slots(on page: String) -> [TemplateSlot] {
        manifest.pageSlots.filter { $0.key == page }.flatMap { $0.value }
    }

    /// The slot's rectangle grown by the padding text is placed in.
    func paddedBox(of slot: TemplateSlot) -> PlanRect {
        let padding = TemplateGeometry.slotPadding
        return PlanRect(
            x0: slot.rect.x0 - padding.left, y0: slot.rect.y0 - padding.top,
            x1: slot.rect.x1 + padding.right, y1: slot.rect.y1 + padding.bottom)
    }

    /// `text` left-aligned in the slot's padded box, which may run on to the content's right edge.
    func leftRuns(_ text: String, in slot: TemplateSlot) -> [TextRun] {
        let box = paddedBox(of: slot)
        return placer.place(
            [text], font: font(for: slot), color: color(for: slot), in: box,
            container: PlanRect(
                x0: box.x0, y0: box.y0, x1: TemplateGeometry.contentRight, y1: box.y1),
            alignment: .left)
    }

    /// `text` centered between `x0` and `x1` in the slot's padded vertical range.
    func centeredRuns(_ text: String, in slot: TemplateSlot, x0: Double, x1: Double) -> [TextRun] {
        let padded = paddedBox(of: slot)
        let box = PlanRect(x0: x0, y0: padded.y0, x1: x1, y1: padded.y1)
        return placer.place(
            [text], font: font(for: slot), color: color(for: slot), in: box, container: box,
            alignment: .center)
    }

    /// The fixed labels among `slots`: the two overview bands are centered, the rest left-aligned.
    func labelRuns(of slots: [TemplateSlot]) -> [TextRun] {
        slots.compactMap { slot in slot.text.map { (slot, $0) } }
            .flatMap { slot, text -> [TextRun] in
                switch slot.id {
                case "todo.label":
                    centeredRuns(
                        text, in: slot, x0: TemplateGeometry.todoBandX0,
                        x1: TemplateGeometry.todoBandX1)
                case "schedule.label":
                    centeredRuns(
                        text, in: slot, x0: TemplateGeometry.scheduleBandX0,
                        x1: TemplateGeometry.scheduleBandX1)
                default:
                    leftRuns(text, in: slot)
                }
            }
    }

    /// The header drawn on every page.
    private func headerOperations(for day: CalendarDay) -> [DrawOperation] {
        let fields = CalendarMath.header(for: day)
        var values = [
            "header.heading": fields.heading, "header.cw": fields.calendarWeek,
            "header.month": fields.month, "header.year": fields.year,
        ]
        for (index, number) in fields.weekDays.enumerated() {
            values["header.dayno.\(index)"] = String(number)
        }
        return manifest.headerSlots
            .compactMap { slot in (slot.text ?? values[slot.id]).map { (slot, $0) } }
            .flatMap { slot, text in leftRuns(text, in: slot) }
            .map { DrawOperation.text($0) }
    }

    /// One title per meeting page; an empty list gives one blank page.
    private func meetingTitles(of content: AgendaContent) -> [String] {
        content.meetings.isEmpty ? [""] : content.meetings
    }

    /// The key of meeting page `index`: its event ID, else its position; a day without meetings
    /// has the one blank page.
    private func meetingKey(at index: Int, in content: AgendaContent) -> PageKey {
        if content.meetings.isEmpty { return .meeting("") }
        let hasID = index < content.meetingIDs.count
        return .meeting(hasID ? content.meetingIDs[index] : "#\(index)")
    }

    /// The runs of a meeting page's title, ellipsized to fit the title slot.
    func meetingTitleRuns(_ title: String) -> [TextRun] {
        ["meeting.title"].compactMap { manifest.slot($0) }
            .flatMap { slot -> [TextRun] in
                let box = paddedBox(of: slot)
                return placer.place(
                    [
                        fitter.singleLine(
                            title, font: font(for: slot),
                            maxWidth: TemplateGeometry.meetingTitleWidth)
                    ],
                    font: font(for: slot), color: color(for: slot), in: box,
                    container: PlanRect(
                        x0: box.x0, y0: box.y0, x1: TemplateGeometry.meetingTitleRight, y1: box.y1),
                    alignment: .left)
            }
    }

    /// The text a continued meeting page shows as its title.
    static func continuedTitle(_ title: String) -> String {
        title.isEmpty ? "cont." : "cont. \(title)"
    }

    /// `page`'s operations with its meeting title replaced by the continued title, when `page` is a
    /// meeting page laid out from `content`; otherwise its operations unchanged.
    func continuedOperations(of page: PagePlan, in content: AgendaContent) -> [DrawOperation] {
        guard page.chrome == .meeting,
            let index = meetingTitles(of: content).indices.first(where: {
                meetingKey(at: $0, in: content) == page.key
            })
        else {
            return page.operations
        }
        let title = meetingTitles(of: content)[index]
        // A meeting page's operations start with its label runs, then its title runs.
        let start = labelRuns(of: slots(on: "meeting_unit")).count
        let end = start + meetingTitleRuns(title).count
        return Array(page.operations[..<start])
            + meetingTitleRuns(Self.continuedTitle(title)).map { .text($0) }
            + page.operations[end...]
    }

    private func meetingPage(title: String, key: PageKey, routines: [SummaryRoutine]) -> PagePlan {
        let label = labelRuns(of: slots(on: "meeting_unit"))
        return PagePlan(
            key: key, chrome: .meeting,
            operations: (label + meetingTitleRuns(title)).map { .text($0) }
                + meetingSummaryOperations(routines: routines))
    }

    /// The "Summary:" label and, after it, the names of the meeting's summary routines joined with
    /// ", "; nothing when the meeting asks for none.
    func meetingSummaryOperations(routines: [SummaryRoutine]) -> [DrawOperation] {
        guard !routines.isEmpty, let slot = manifest.slot("meeting.label") else { return [] }
        let font = FontSpec.nominal(
            theme.fontPack, slot.weight, TemplateGeometry.meetingSummaryPoints)
        let color = color(for: slot)
        let box = TemplateGeometry.meetingSummaryBox
        let labelText = placer.place(
            ["Summary:"], font: font, color: color, in: box, container: box, alignment: .left)
        guard let label = labelText.first else { return [] }
        let start = label.x + label.width + TemplateGeometry.meetingSummaryGap
        let namesBox = PlanRect(
            x0: start, y0: box.y0, x1: TemplateGeometry.meetingTitleRight, y1: box.y1)
        let names = routines.map(\.name).joined(separator: ", ")
        return labelText.map { DrawOperation.text($0) }
            + placer.place(
                [fitter.singleLine(names, font: font, maxWidth: namesBox.x1 - namesBox.x0)],
                font: font, color: color, in: namesBox, container: namesBox, alignment: .left
            ).map { .text($0) }
    }

    private func furtherNotesPage() -> PagePlan {
        let label = labelRuns(of: slots(on: "further_notes"))
        return PagePlan(key: .notes, chrome: .furtherNotes, operations: label.map { .text($0) })
    }
}
