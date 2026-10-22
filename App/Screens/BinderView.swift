import AppCore
import SwiftUI

/// The day's binder on iPad: its pages one under the other, each with a canvas to write on, the
/// page indicator, and Share PDF with the handwriting on the pages.
struct BinderView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let binderView = "binderView"
        static let binderPageIndicator = "binderPageIndicator"
        static let binderShareButton = "binderShareButton"

        static func binderPage(_ n: Int) -> String { "binderPage.\(n)" }
    }

    let binder: BinderSession

    @Environment(AgendaController.self) private var controller
    @Environment(\.allowsFingerDrawing) private var allowsFingerDrawing

    @State private var visibleKey: PageKey?

    /// The position of the page at the top of the scroll view; the first page until it scrolls.
    private var visibleIndex: Int {
        visibleKey.flatMap { binder.index(of: $0) } ?? 0
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
        ScrollView(.vertical) {
            LazyVStack(spacing: 16) {
                ForEach(Array(plan.pages.enumerated()), id: \.element.key) { index, page in
                    BinderPageView(
                        page: page, pageWidth: plan.pageWidth, pageHeight: plan.pageHeight,
                        ink: binder.ink[page.key], allowsFingerDrawing: allowsFingerDrawing,
                        onInkChange: { data in binder.setInk(data, on: page.key) }
                    )
                    .aspectRatio(plan.pageWidth / plan.pageHeight, contentMode: .fit)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(ID.binderPage(index))
                    .accessibilityLabel(Self.label(for: page.key))
                    .accessibilityValue(binder.ink[page.key] == nil ? "Blank" : "Handwritten")
                }
            }
            .scrollTargetLayout()
            .padding(16)
        }
        .scrollPosition(id: $visibleKey)
        // Room after the last page, so it can scroll to the top and become the visible page.
        .contentMargins(.bottom, 600, for: .scrollContent)
        .accessibilityIdentifier(ID.binderView)
        .background(Color(.secondarySystemBackground))
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
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
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Page \(visibleIndex + 1) of \(plan.pages.count)")
                .font(.footnote.monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .accessibilityIdentifier(ID.binderPageIndicator)
        }
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
