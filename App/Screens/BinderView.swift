import AppCore
import SwiftUI

/// The day's binder on iPad: its pages side by side, one whole page per screen, each with a
/// canvas to write on, the page indicator, and Share PDF with the handwriting on the pages.
struct BinderView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let binderView = "binderView"
        static let binderPageIndicator = "binderPageIndicator"
        static let binderShareButton = "binderShareButton"
        static let overviewButton = "binderOverviewButton"
        static let delegatedButton = "binderDelegatedButton"
        static let notesButton = "binderNotesButton"
        static let eraserButton = "eraserButton"
        static let undoButton = "undoButton"
        static let redoButton = "redoButton"
        static let addPageButton = "addPageButton"
        static let deletePageButton = "deletePageButton"
        static let confirmDeletePageButton = "confirmDeletePageButton"
        static let cancelDeletePageButton = "cancelDeletePageButton"

        static func penButton(_ pen: BinderPen) -> String { "penButton.\(pen.rawValue)" }

        static func binderPage(_ n: Int) -> String { "binderPage.\(n)" }
    }

    let binder: BinderSession

    @Environment(AgendaController.self) private var controller
    @Environment(\.allowsFingerDrawing) private var allowsFingerDrawing

    @State private var visibleKey: PageKey?
    @State private var tool = BinderTool.pen(.black)
    @State private var lastPen = BinderPen.black
    @State private var confirmsDelete = false

    /// The position of the page on screen; the first page until it moves.
    private var visibleIndex: Int {
        visibleKey.flatMap { binder.index(of: $0) } ?? 0
    }

    private func scroll(to key: PageKey) {
        withAnimation {
            visibleKey = key
        }
    }

    /// Scrolls to the page an undo or redo changed, unless it is already the visible page or is not
    /// shown.
    private func reveal(_ key: PageKey?) {
        guard let key, key != visibleKey, binder.index(of: key) != nil else {
            return
        }
        scroll(to: key)
    }

    /// Adds a blank page after the one on screen and shows it.
    private func addPage() {
        let visible = visibleKey.flatMap { binder.index(of: $0) != nil ? $0 : nil }
        guard let after = visible ?? binder.plan.pages.first?.key else {
            return
        }
        scroll(to: binder.addPage(after: after))
    }

    /// Deletes the added page on screen and shows the page before it.
    private func deleteVisiblePage() {
        guard let key = visibleKey, let next = binder.deletePage(key) else {
            return
        }
        scroll(to: next)
    }

    /// Shown while an exported PDF waits to be shared.
    private var showsShareSheet: Binding<Bool> {
        Binding(
            get: { controller.binderExport != nil },
            set: { shows in
                if !shows {
                    controller.clearBinderExport()
                }
            })
    }

    var body: some View {
        let plan = binder.plan
        // The bars and the page indicator are stacked around the pages instead of inset into the
        // scroll view, so a page is fitted to the room they leave, even under a long banner, and a
        // swipe in that room reaches the pages.
        VStack(spacing: 0) {
            BinderToolbar(
                tool: $tool,
                hasDelegatedPage: plan.pages.contains { $0.key == .delegated(0) },
                canUndo: binder.canUndo, canRedo: binder.canRedo,
                goToOverview: { scroll(to: .overview) },
                goToDelegated: { scroll(to: .delegated(0)) },
                goToNotes: { scroll(to: .notes) },
                undo: { reveal(binder.undo()) }, redo: { reveal(binder.redo()) },
                addPage: addPage,
                canDeletePage: visibleKey.map { binder.canDelete($0) } ?? false,
                deletePage: { confirmsDelete = true })
            if !plan.omittedTodoItems.isEmpty {
                OmittedTasksBanner(tasks: plan.omittedTodoItems.map(\.text))
            }
            if let message = binder.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
            pages(plan)
            Text("Page \(visibleIndex + 1) of \(plan.pages.count)")
                .font(.footnote.monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .accessibilityIdentifier(ID.binderPageIndicator)
                .padding(.bottom, 8)
        }
        .background(Color(.secondarySystemBackground))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await controller.exportBinder() }
                } label: {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier(ID.binderShareButton)
            }
        }
        .sheet(isPresented: showsShareSheet, onDismiss: { controller.clearBinderExport() }) {
            if let url = controller.binderExport {
                ActivityView(url: url, onDone: { controller.clearBinderExport() })
            }
        }
        .alert("Delete this page?", isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive, action: deleteVisiblePage)
                .accessibilityIdentifier(ID.confirmDeletePageButton)
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier(ID.cancelDeletePageButton)
        } message: {
            Text("The page and its handwriting will be removed. This can't be undone.")
        }
    }

    /// The pages side by side, one whole page per screen.
    private func pages(_ plan: RenderPlan) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(plan.pages.enumerated()), id: \.element.key) { index, page in
                    BinderPageView(
                        page: page, pageWidth: plan.pageWidth, pageHeight: plan.pageHeight,
                        ink: binder.ink[page.key], allowsFingerDrawing: allowsFingerDrawing,
                        tool: tool,
                        linkTarget: { plan.linkTarget(at: $0, onPage: index) },
                        onLinkTap: { target in
                            if plan.pages.indices.contains(target) {
                                scroll(to: plan.pages[target].key)
                            }
                        },
                        onInkChange: { data in binder.setInk(data, on: page.key) }
                    )
                    .aspectRatio(plan.pageWidth / plan.pageHeight, contentMode: .fit)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(ID.binderPage(index))
                    .accessibilityLabel(Self.label(for: page.key))
                    .accessibilityValue(binder.ink[page.key] == nil ? "Blank" : "Handwritten")
                    .padding(16)
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $visibleKey)
        .background(PencilInteractionView(onSwitch: { tool = tool.switched(backTo: lastPen) }))
        .onChange(of: tool) {
            if case .pen(let pen) = tool {
                lastPen = pen
            }
        }
        .accessibilityIdentifier(ID.binderView)
    }

    /// What VoiceOver calls the page with `key`.
    private static func label(for key: PageKey) -> String {
        switch key {
        case .overview:
            "Overview"
        case .delegated(let index):
            "Delegated tasks, page \(index + 1)"
        case .meeting:
            "Meeting notes"
        case .notes:
            "Notes"
        case .extra:
            "Added page"
        }
    }
}

#Preview {
    if let services = AppEnvironment.previewServices() {
        NavigationStack {
            if let binder = services.controller.binder {
                BinderView(binder: binder)
            }
        }
        .environment(services.controller)
        .environment(\.pageDrawer, services.pageDrawer)
        .task {
            await services.controller.start()
            await services.controller.render()
        }
    }
}
