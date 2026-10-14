extension AgendaLayout {
    /// `pages` with the navigation links appended: back to the overview, on to the notes page,
    /// and from each schedule entry to its meeting page.
    func addingLinks(
        to pages: [PagePlan], schedule: [ScheduleEntry], delegatedPageCount: Int
    ) -> [PagePlan] {
        let last = pages.count - 1
        return pages.enumerated().map { index, page in
            var links: [DrawOperation] = []
            if index > 0 {
                links += headerLinks(on: page, slot: "header.overview_label", target: 0)
            }
            if index < last {
                links += headerLinks(on: page, slot: "header.notes_label", target: last)
            }
            if index == 0 {
                links += scheduleLinks(on: page, entries: schedule, offset: 1 + delegatedPageCount)
            }
            return PagePlan(chrome: page.chrome, operations: page.operations + links)
        }
    }

    private func textRuns(on page: PagePlan) -> [TextRun] {
        page.operations.compactMap { operation -> TextRun? in
            if case .text(let run) = operation {
                return run
            }
            return nil
        }
    }

    private func headerLinks(on page: PagePlan, slot id: String, target: Int) -> [DrawOperation] {
        let runs = textRuns(on: page)
        return [manifest.slot(id)].compactMap { $0 }
            .flatMap { slot -> [DrawOperation] in
                let box = paddedBox(of: slot)
                return runs.filter { $0.container.x0 == box.x0 && $0.container.y0 == box.y0 }
                    .map { .link($0.bounds, targetPage: target) }
            }
    }

    private func scheduleLinks(
        on page: PagePlan, entries: [ScheduleEntry], offset: Int
    ) -> [DrawOperation] {
        let runs = textRuns(on: page)
        var seen = Set<Int>()
        return entries.filter { seen.insert($0.slot).inserted }
            .compactMap { entry in
                manifest.slot("schedule.slot.\(entry.slot)").map { (entry, $0) }
            }
            .flatMap { entry, slot -> [DrawOperation] in
                let padded = paddedBox(of: slot)
                let container = PlanRect(
                    x0: TemplateGeometry.scheduleTextX0 - TemplateGeometry.slotPadding.left,
                    y0: padded.y0, x1: TemplateGeometry.scheduleTextX1, y1: padded.y1)
                return runs.filter { $0.container == container }
                    .compactMap { run in
                        entry.meetingIndex.map { .link(run.bounds, targetPage: offset + $0) }
                    }
            }
    }
}
