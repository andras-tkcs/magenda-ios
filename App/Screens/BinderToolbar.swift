import AppCore
import SwiftUI

/// The binder's controls in one scrolling row: go to a page, pick a pen or the eraser, undo and
/// redo, and add a page.
struct BinderToolbar: View {
    @Binding var tool: BinderTool
    /// Whether the plan has a delegated-tasks page to go to.
    let hasDelegatedPage: Bool
    let canUndo: Bool
    let canRedo: Bool
    let goToOverview: () -> Void
    let goToDelegated: () -> Void
    let goToNotes: () -> Void
    let undo: () -> Void
    let redo: () -> Void
    let addPage: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                button("square.grid.2x2", "Go to overview", BinderView.ID.overviewButton) {
                    goToOverview()
                }
                if hasDelegatedPage {
                    button("person.2", "Go to delegated tasks", BinderView.ID.delegatedButton) {
                        goToDelegated()
                    }
                }
                button("note.text", "Go to notes", BinderView.ID.notesButton) { goToNotes() }
                Divider().frame(height: 24)
                ForEach(BinderPen.allCases, id: \.self) { pen in
                    toolButton(
                        .pen(pen), image: "circle.fill", label: "\(pen.name) pen",
                        identifier: BinderView.ID.penButton(pen),
                        tint: Color(
                            red: Double(pen.color.red) / 255, green: Double(pen.color.green) / 255,
                            blue: Double(pen.color.blue) / 255))
                }
                toolButton(
                    .eraser, image: "eraser", label: "Eraser",
                    identifier: BinderView.ID.eraserButton, tint: .primary)
                Divider().frame(height: 24)
                button(
                    "arrow.uturn.backward", "Undo", BinderView.ID.undoButton, isEnabled: canUndo
                ) { undo() }
                button(
                    "arrow.uturn.forward", "Redo", BinderView.ID.redoButton, isEnabled: canRedo
                ) { redo() }
                Divider().frame(height: 24)
                button("doc.badge.plus", "Add page after this one", BinderView.ID.addPageButton) {
                    addPage()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private func button(
        _ image: String, _ label: String, _ identifier: String, isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .frame(minWidth: 36, minHeight: 36)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func toolButton(
        _ value: BinderTool, image: String, label: String, identifier: String, tint: Color
    ) -> some View {
        let isSelected = tool == value
        return Button {
            tool = value
        } label: {
            Image(systemName: image)
                .foregroundStyle(tint)
                .frame(minWidth: 36, minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
