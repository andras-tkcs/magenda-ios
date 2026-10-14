/// A way a plan's text or links break the layout.
public struct LayoutViolation: Equatable, Sendable {
    /// What is wrong.
    public enum Kind: Equatable, Sendable {
        /// A run's glyphs stick out of the box they must stay inside.
        case outsideContainer(text: String)
        /// A run's container reaches beyond the page.
        case outsidePage(text: String)
        /// Two runs on one page cover the same area.
        case overlap(String, String)
        /// A link points at a page that does not exist.
        case badLinkTarget(Int)
        /// The plan has no pages.
        case noPages
    }

    /// The index of the page the problem is on.
    public let page: Int
    /// What is wrong.
    public let kind: Kind

    /// Creates a violation.
    public init(page: Int, kind: Kind) {
        self.page = page
        self.kind = kind
    }
}

/// Checks a render plan for text that leaves its box or the page, text drawn over text, and links
/// to pages that do not exist.
public enum LayoutAudit {
    private static let tolerance = 0.5

    /// Every violation in `plan`, page by page; empty when the layout is sound.
    public static func violations(in plan: RenderPlan) -> [LayoutViolation] {
        if plan.pages.isEmpty {
            return [LayoutViolation(page: 0, kind: .noPages)]
        }
        let pageRect = PlanRect(x0: 0, y0: 0, x1: plan.pageWidth, y1: plan.pageHeight)
        return plan.pages.enumerated().flatMap { index, page in
            let runs = page.operations.compactMap { operation -> TextRun? in
                if case .text(let run) = operation {
                    return run
                }
                return nil
            }
            let containment = runs.flatMap { run in
                containmentKinds(of: run, pageRect: pageRect)
            }
            let overlaps = runs.enumerated().flatMap { offset, run in
                runs.dropFirst(offset + 1)
                    .filter { run.bounds.intersects($0.bounds, tolerance: tolerance) }
                    .map { LayoutViolation.Kind.overlap(run.text, $0.text) }
            }
            let links = page.operations.compactMap { operation -> LayoutViolation.Kind? in
                if case .link(_, let target) = operation,
                    !plan.pages.indices.contains(target)
                {
                    return .badLinkTarget(target)
                }
                return nil
            }
            return (containment + overlaps + links).map { LayoutViolation(page: index, kind: $0) }
        }
    }

    private static func containmentKinds(of run: TextRun, pageRect: PlanRect)
        -> [LayoutViolation.Kind]
    {
        let outsideContainer =
            run.container.contains(run.bounds, tolerance: tolerance)
            ? [] : [LayoutViolation.Kind.outsideContainer(text: run.text)]
        let outsidePage =
            pageRect.contains(run.container, tolerance: tolerance)
            ? [] : [LayoutViolation.Kind.outsidePage(text: run.text)]
        return outsideContainer + outsidePage
    }
}
