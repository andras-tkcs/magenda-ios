/// Lays out a binder day: the content's pages, the retained pages and the added pages, with links
/// pointing at the right pages; and rebuilds a day onto new content without losing handwriting.
public struct BinderLayout: Sendable {
    let manifest: TemplateManifest
    let measurer: any TextMeasuring

    /// Creates a binder layout for a template and a text measurer.
    public init(manifest: TemplateManifest, measurer: any TextMeasuring) {
        self.manifest = manifest
        self.measurer = measurer
    }

    /// A page of the composed plan with the index of the plan its links refer to.
    private struct ComposedPage {
        let page: PagePlan
        let origin: Int
    }

    private func layout(_ theme: Theme) -> AgendaLayout {
        AgendaLayout(manifest: manifest, measurer: measurer, theme: theme)
    }

    /// The plan for `day`: the content's pages, the retained pages and the added pages. An added
    /// copy of a meeting page is titled as continued.
    public func plan(for day: BinderDay) -> RenderPlan {
        let base = composeBase(day)
        var contents: [AgendaContent] = []
        let placed = day.retained.map { retained -> (page: RetainedPage, origin: Int) in
            if let index = contents.firstIndex(of: retained.content) {
                return (retained, index + 1)
            }
            contents.append(retained.content)
            return (retained, contents.count)
        }
        let origins = [base.plan] + contents.map { layout(day.theme).plan(for: $0) }
        let originContents = [day.content] + contents
        let withRetained = insertRetained(placed, origins: origins, into: base.pages)
        let composed = insertExtras(
            day.extras, into: withRetained, layout: layout(day.theme), contents: originContents)
        return RenderPlan(
            pageWidth: base.plan.pageWidth, pageHeight: base.plan.pageHeight,
            pages: remapLinks(composed, origins: origins),
            omittedTodoItems: base.plan.omittedTodoItems)
    }

    /// Step 1: the content's own plan, every page remembering that it came from it.
    private func composeBase(_ day: BinderDay) -> (plan: RenderPlan, pages: [ComposedPage]) {
        let plan = layout(day.theme).plan(for: day.content)
        return (plan, plan.pages.map { ComposedPage(page: $0, origin: 0) })
    }

    /// Steps 2 and 3: each retained page not already shown goes after the last page with its
    /// chrome, or right before the notes page when there is none.
    private func insertRetained(
        _ placed: [(page: RetainedPage, origin: Int)], origins: [RenderPlan],
        into pages: [ComposedPage]
    ) -> [ComposedPage] {
        var result = pages
        for (retained, origin) in placed {
            guard !result.contains(where: { $0.page.key == retained.key }),
                let page = origins[origin].pages.first(where: { $0.key == retained.key })
            else { continue }
            let after = result.lastIndex { $0.page.chrome == page.chrome }.map { $0 + 1 }
            let notes = result.firstIndex { $0.page.key == .notes }
            if let index = after ?? notes {
                result.insert(ComposedPage(page: page, origin: origin), at: index)
            }
        }
        return result
    }

    /// Steps 4 and 5: the added pages, each a copy of its source page, right after the page they
    /// follow; those whose page is gone follow their source's run.
    private func insertExtras(
        _ extras: [ExtraPage], into pages: [ComposedPage], layout agenda: AgendaLayout,
        contents: [AgendaContent]
    ) -> [ComposedPage] {
        let live = extras.compactMap { extra in
            pages.first { $0.page.key == extra.source }.map { (extra: extra, source: $0) }
        }
        var emitted = Set<Int>()

        func copy(of entry: (extra: ExtraPage, source: ComposedPage)) -> ComposedPage {
            ComposedPage(
                page: PagePlan(
                    key: .extra(entry.extra.id), chrome: entry.source.page.chrome,
                    operations: agenda.continuedOperations(
                        of: entry.source.page, in: contents[entry.source.origin])),
                origin: entry.source.origin)
        }

        func chains(following key: PageKey) -> [ComposedPage] {
            var result: [ComposedPage] = []
            for (index, entry) in live.enumerated()
            where !emitted.contains(index) && entry.extra.after == key {
                emitted.insert(index)
                result.append(copy(of: entry))
                result += chains(following: .extra(entry.extra.id))
            }
            return result
        }

        var result = pages.flatMap { [$0] + chains(following: $0.page.key) }
        let pending = live.enumerated().filter { !emitted.contains($0.offset) }
        let roots = pending.filter { root in
            !pending.contains {
                $0.offset != root.offset && .extra($0.element.extra.id) == root.element.extra.after
            }
        }
        for (_, root) in roots {
            let chain = [copy(of: root)] + chains(following: .extra(root.extra.id))
            let start = result.firstIndex { $0.page.key == root.extra.source }
            if let start {
                var end = start + 1
                while end < result.count, case .extra = result[end].page.key { end += 1 }
                result.insert(contentsOf: chain, at: end)
            }
        }
        return result
    }

    /// Step 6: every link points at the composed index of the page it pointed at in the plan its
    /// page came from; a link to a page that is not shown is dropped.
    private func remapLinks(_ composed: [ComposedPage], origins: [RenderPlan]) -> [PagePlan] {
        var positions: [PageKey: Int] = [:]
        for (index, entry) in composed.enumerated() where positions[entry.page.key] == nil {
            positions[entry.page.key] = index
        }
        return composed.map { entry in
            let pages = origins[entry.origin].pages
            let operations = entry.page.operations.compactMap { operation -> DrawOperation? in
                guard case .link(let rect, let target) = operation else { return operation }
                return pages.enumerated().first { $0.offset == target }
                    .flatMap { positions[$0.element.key] }
                    .map { .link(rect, targetPage: $0) }
            }
            return PagePlan(key: entry.page.key, chrome: entry.page.chrome, operations: operations)
        }
    }

    /// `day` moved onto new content and theme. Pages that left the content but carry handwriting
    /// (their own, or on an added copy) are retained with the content they were laid out from;
    /// added pages whose source is no longer shown are dropped. Locked pages are kept like inked
    /// ones.
    public func rebased(
        _ day: BinderDay, onto content: AgendaContent, theme: Theme, inkedKeys: Set<PageKey>
    ) -> BinderDay {
        let oldKeys = plan(for: day).pages.map(\.key).filter { key in
            if case .extra = key { return false }
            return true
        }
        let kept = oldKeys.filter { key in
            inkedKeys.contains(key) || day.locked.contains(key)
                || day.extras.contains { $0.source == key && inkedKeys.contains(.extra($0.id)) }
        }
        let newKeys = Set(layout(theme).plan(for: content).pages.map(\.key))
        let retained = kept.filter { !newKeys.contains($0) }
            .map { key in
                day.retained.first { $0.key == key }
                    ?? RetainedPage(key: key, content: day.content)
            }
        let shown = newKeys.union(retained.map(\.key))
        return BinderDay(
            content: content, theme: theme, extras: day.extras.filter { shown.contains($0.source) },
            retained: retained, locked: day.locked)
    }
}
