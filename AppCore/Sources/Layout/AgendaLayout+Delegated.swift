extension AgendaLayout {
    private struct DelegatedRow {
        let item: DelegatedItem
        let taskLines: [String]
        let taskFont: FontSpec
        let owner: String
        let statusLines: [String]
        let statusIndents: [Double]
        let height: Double
    }

    /// The delegated-task pages; none when there is nothing delegated.
    func delegatedPages(for content: AgendaContent) -> [PagePlan] {
        if content.delegated.isEmpty { return [] }
        let rows = content.delegated.sortedForPage().map { delegatedRow(for: $0) }
        let top = manifest.delegatedTableTopLeft.y
        var groups: [[DelegatedRow]] = []
        var current: [DelegatedRow] = []
        var bottom = top
        for row in rows {
            if !current.isEmpty && bottom + row.height > TemplateGeometry.delegatedMaxY {
                groups.append(current)
                current = []
                bottom = top
            }
            current.append(row)
            bottom += row.height
        }
        groups.append(current)
        var number = 0
        return groups.enumerated().map { index, group in
            let page = delegatedPage(
                group, firstNumber: number + 1, isLast: index == groups.count - 1)
            number += group.count
            return page
        }
    }

    private var delegatedBodyFont: FontSpec {
        FontSpec.nominal(theme.fontPack, .extralight, 11)
    }

    private func delegatedRow(for item: DelegatedItem) -> DelegatedRow {
        let columns = TemplateGeometry.delegatedColumns
        let inset = 2 * TemplateGeometry.delegatedCellInset
        let font = delegatedBodyFont
        let task = fitter.downsizeOrWrap(
            item.text, pack: theme.fontPack, weight: .extralight, maxPoints: 11, minPoints: 9,
            maxWidth: columns.task - inset, maxLines: 6)
        let owner = fitter.singleLine(item.owner, font: font, maxWidth: columns.owner - inset)
        let status = statusLines(for: item.status)
        let contentLines = max(1 + task.lines.count, status.lines.count)
        let lineHeight = measurer.metrics(for: font).lineHeight
        return DelegatedRow(
            item: item, taskLines: [item.cadence.label] + task.lines, taskFont: task.font,
            owner: owner, statusLines: status.lines, statusIndents: status.indents,
            height: manifest.delegatedRowOverhead + max(0, Double(contentLines - 2)) * lineHeight)
    }

    /// The status log as bulleted lines within the line budget, and the indent of each line.
    private func statusLines(for status: [String]) -> (lines: [String], indents: [Double]) {
        let font = delegatedBodyFont
        let bullet = "• "
        let bulletWidth = measurer.width(of: bullet, font: font)
        let width =
            TemplateGeometry.delegatedColumns.status - 2 * TemplateGeometry.delegatedCellInset
            - bulletWidth
        var pending = status.map { TextFitter.normalized($0) }.filter { !$0.isEmpty }[...]
        var lines: [(text: String, isFirst: Bool)] = []
        while let entry = pending.first, lines.count < TemplateGeometry.delegatedStatusLines {
            pending.removeFirst()
            let wrapped = fitter.wrap(
                entry, font: font, maxWidth: width,
                maxLines: TemplateGeometry.delegatedStatusLines - lines.count)
            lines += wrapped.enumerated().map { (text: $1, isFirst: $0 == 0) }
        }
        if !pending.isEmpty {
            let last = lines[lines.count - 1]
            lines[lines.count - 1].text = fitter.ellipsized(
                ([last.text] + pending).joined(separator: " "), font: font, maxWidth: width)
        }
        return (
            lines.map { ($0.isFirst ? bullet : "") + $0.text },
            lines.map { $0.isFirst ? 0 : bulletWidth }
        )
    }

    private func delegatedPage(_ rows: [DelegatedRow], firstNumber: Int, isLast: Bool) -> PagePlan {
        let columns = TemplateGeometry.delegatedColumns
        let left = manifest.delegatedTableTopLeft.x
        let numberX1 = left + columns.number
        let taskX1 = numberX1 + columns.task
        let ownerX1 = taskX1 + columns.owner
        let right = ownerX1 + columns.status
        let inset = TemplateGeometry.delegatedCellInset
        let black = theme.colors.color(for: .body)
        let label = theme.colors.color(for: .label)
        var operations: [DrawOperation] = [.fill(TemplateGeometry.delegatedErase, .white)]
        let headers = [
            ("delegated.header.task", numberX1, taskX1),
            ("delegated.header.owner", taskX1, ownerX1),
            ("delegated.header.status", ownerX1, right),
        ]
        operations +=
            headers
            .compactMap { id, x0, x1 in
                manifest.slot(id).flatMap { slot in
                    slot.text.map { centeredRuns($0, in: slot, x0: x0, x1: x1) }
                }
            }
            .flatMap { $0 }
            .map { .text($0) }
        operations += labelRuns(
            of: slots(on: "delegated_shell").filter { $0.id == "delegated.footer_label" }
        ).map { .text($0) }
        var top = manifest.delegatedTableTopLeft.y
        for (offset, row) in rows.enumerated() {
            let rowBox = PlanRect(x0: left, y0: top, x1: right, y1: top + row.height)
            if row.item.marked {
                operations.append(.fill(rowBox, TemplateGeometry.markedFill))
            }
            operations.append(
                .line(
                    from: PlanPoint(x: left, y: top), to: PlanPoint(x: right, y: top), .black,
                    lineWidth: offset == 0
                        ? TemplateGeometry.delegatedThickBorder
                        : TemplateGeometry.delegatedThinBorder))
            let numberBox = PlanRect(x0: left, y0: top, x1: numberX1, y1: top + row.height)
            let taskBox = PlanRect(
                x0: numberX1 + inset, y0: top, x1: taskX1 - inset, y1: top + row.height)
            let ownerBox = PlanRect(
                x0: taskX1 + inset, y0: top, x1: ownerX1 - inset, y1: top + row.height)
            let statusBox = PlanRect(
                x0: ownerX1 + inset, y0: top, x1: right - inset, y1: top + row.height)
            let numberFont = FontSpec.nominal(theme.fontPack, .black, 14)
            let runs =
                placer.place(
                    [String(firstNumber + offset)], font: numberFont, color: label,
                    in: numberBox, container: numberBox, alignment: .center)
                + placer.place(
                    row.taskLines, font: row.taskFont, color: black, in: taskBox,
                    container: taskBox, alignment: .left)
                + placer.place(
                    [row.owner], font: delegatedBodyFont, color: black, in: ownerBox,
                    container: ownerBox, alignment: .center)
                + placer.place(
                    row.statusLines, font: delegatedBodyFont, color: black, in: statusBox,
                    container: statusBox, alignment: .left, indents: row.statusIndents)
            operations += runs.map { .text($0) }
            top += row.height
        }
        if !isLast {
            operations.append(
                .line(
                    from: PlanPoint(x: left, y: top), to: PlanPoint(x: right, y: top), .black,
                    lineWidth: TemplateGeometry.delegatedThinBorder))
        }
        return PagePlan(chrome: .delegated, operations: operations)
    }
}
