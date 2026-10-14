import AppCore
import SwiftUI

/// The Agenda menu: the screen's actions in the iPad menu bar and the shortcut list shown by
/// holding ⌘. Every item is disabled while there is no controller.
struct AgendaCommands: Commands {
    let controller: AgendaController?

    private var canRender: Bool {
        controller?.status == .ready && controller?.draft != nil
    }

    private var canNavigate: Bool {
        switch controller?.status {
        case .ready, .failed: true
        default: false
        }
    }

    private var canGoToNextWorkingDay: Bool {
        canNavigate && controller?.showsNextWorkingDay == true
    }

    var body: some Commands {
        CommandMenu("Agenda") {
            Button("Render") {
                run { await $0.render() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!canRender)
            Button("Previous Day") {
                run { await $0.setDay($0.day.adding(days: -1)) }
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!canNavigate)
            Button("Next Day") {
                run { await $0.setDay($0.day.adding(days: 1)) }
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!canNavigate)
            Button("Reload") {
                run { await $0.load() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!canNavigate)
            Button("Next Working Day") {
                run { await $0.goToNextWorkingDay() }
            }
            .keyboardShortcut("]", modifiers: [.command, .option])
            .disabled(!canGoToNextWorkingDay)
        }
    }

    private func run(_ action: @escaping @MainActor (AgendaController) async -> Void) {
        guard let controller else {
            return
        }
        Task { await action(controller) }
    }
}
