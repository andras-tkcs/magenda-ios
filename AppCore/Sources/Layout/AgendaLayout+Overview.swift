extension AgendaLayout {
    /// The overview page and the to-do items that did not fit on it.
    func overviewPage(for content: AgendaContent) -> (page: PagePlan, omitted: [TodoItem]) {
        var operations: [DrawOperation] = [.fill(TemplateGeometry.todoErase, .white)]
        let slots = slots(on: "overview")
        operations += labelRuns(of: slots).map { .text($0) }
        let todo = todoOperations(for: content.todoItems)
        operations += todo.operations
        operations += scheduleOperations(for: content.schedule)
        operations += nextFourWeeksOperations(from: content.date)
        return (PagePlan(chrome: .overview, operations: operations), todo.omitted)
    }

    private struct TodoRow {
        let lines: [String]
        let font: FontSpec
        let height: Double
    }

    private func todoRow(for item: TodoItem) -> TodoRow {
        let notes = TextFitter.normalized(item.notes)
        let fitted = fitter.downsizeOrWrap(
            notes.isEmpty ? item.text : item.text + ":", pack: theme.fontPack, weight: .thin,
            maxPoints: 12, minPoints: 9, maxWidth: TemplateGeometry.todoTaskWidth, maxLines: 3)
        var lines = fitted.lines
        if !notes.isEmpty {
            lines.append(
                fitter.singleLine(
                    notes, font: fitted.font, maxWidth: TemplateGeometry.todoTaskWidth))
        }
        let lineHeight = measurer.metrics(for: fitted.font).lineHeight
        let baseLines = max(1, (TemplateGeometry.todoBaseRow / lineHeight).rounded(.down))
        let extra = max(0, Double(lines.count) - baseLines)
        return TodoRow(
            lines: lines, font: fitted.font,
            height: TemplateGeometry.todoBaseRow + extra * lineHeight)
    }

    /// The ruled line above a row (except the first) and the row's checkbox.
    private func rowFrame(top: Double, height: Double) -> [DrawOperation] {
        let half = TemplateGeometry.checkboxSize / 2
        let centerY = top + height / 2
        var operations: [DrawOperation] = []
        if top > TemplateGeometry.todoTop {
            operations.append(
                .line(
                    from: PlanPoint(x: TemplateGeometry.todoGridX0, y: top),
                    to: PlanPoint(x: TemplateGeometry.todoGridX1, y: top),
                    TemplateGeometry.todoLineColor, lineWidth: TemplateGeometry.todoLineWidth))
        }
        operations.append(
            .stroke(
                PlanRect(
                    x0: TemplateGeometry.checkboxCenterX - half, y0: centerY - half,
                    x1: TemplateGeometry.checkboxCenterX + half, y1: centerY + half),
                .black, lineWidth: TemplateGeometry.checkboxLineWidth))
        return operations
    }

    private func todoOperations(
        for items: [TodoItem]
    ) -> (operations: [DrawOperation], omitted: [TodoItem]) {
        let limit = TemplateGeometry.todoBottom + 0.5
        let dueFont = FontSpec.nominal(theme.fontPack, .thin, 12)
        let black = theme.colors.color(for: .body)
        var operations: [DrawOperation] = []
        var omitted: [TodoItem] = []
        var top = TemplateGeometry.todoTop
        for (index, item) in items.enumerated() {
            let row = todoRow(for: item)
            if top + row.height > limit {
                omitted = Array(items[index...])
                break
            }
            operations += rowFrame(top: top, height: row.height)
            let taskBox = PlanRect(
                x0: TemplateGeometry.todoTaskX0, y0: top, x1: TemplateGeometry.todoTaskX1,
                y1: top + row.height)
            let dueBox = PlanRect(
                x0: TemplateGeometry.todoDueX0, y0: top, x1: TemplateGeometry.todoDueX1,
                y1: top + row.height)
            let due = fitter.singleLine(
                item.due, font: dueFont, maxWidth: TemplateGeometry.todoDueWidth)
            let runs =
                placer.place(
                    row.lines, font: row.font, color: black, in: taskBox, container: taskBox,
                    alignment: .left)
                + placer.place(
                    [due], font: dueFont, color: black, in: dueBox, container: dueBox,
                    alignment: .left)
            operations += runs.map { .text($0) }
            top += row.height
        }
        while top + TemplateGeometry.todoBaseRow <= limit {
            operations += rowFrame(top: top, height: TemplateGeometry.todoBaseRow)
            top += TemplateGeometry.todoBaseRow
        }
        return (operations, omitted)
    }

    private func scheduleOperations(for entries: [ScheduleEntry]) -> [DrawOperation] {
        var seen = Set<Int>()
        return entries.filter { seen.insert($0.slot).inserted }
            .compactMap { entry in
                manifest.slot("schedule.slot.\(entry.slot)").map { (entry, $0) }
            }
            .flatMap { entry, slot -> [TextRun] in
                let padded = paddedBox(of: slot)
                let box = PlanRect(
                    x0: TemplateGeometry.scheduleTextX0 - TemplateGeometry.slotPadding.left,
                    y0: padded.y0, x1: TemplateGeometry.scheduleTextX1, y1: padded.y1)
                let text = fitter.singleLine(
                    entry.text, font: font(for: slot),
                    maxWidth: TemplateGeometry.scheduleTextWidth)
                return placer.place(
                    [text], font: font(for: slot), color: color(for: slot), in: box,
                    container: box, alignment: .left)
            }
            .map { .text($0) }
    }

    private func nextFourWeeksOperations(from day: CalendarDay) -> [DrawOperation] {
        var values: [String: String] = [:]
        for (week, row) in CalendarMath.nextFourWeeks(from: day).enumerated() {
            values["next4weeks.week.\(week).cw"] = row.calendarWeek
            for (index, number) in row.days.enumerated() {
                values["next4weeks.week.\(week).day.\(index)"] = String(number)
            }
        }
        return slots(on: "overview")
            .compactMap { slot in values[slot.id].map { (slot, $0) } }
            .flatMap { slot, text in leftRuns(text, in: slot) }
            .map { .text($0) }
    }
}
