import SwiftUI
import UIKit

/// An empty view that reports the Apple Pencil's double-tap and squeeze, unless the person has
/// set them to do nothing or to run a shortcut in Settings.
struct PencilInteractionView: UIViewRepresentable {
    /// Called once per double-tap or completed squeeze.
    let onSwitch: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwitch: onSwitch)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.addInteraction(UIPencilInteraction(delegate: context.coordinator))
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onSwitch = onSwitch
    }

    @MainActor
    final class Coordinator: NSObject, UIPencilInteractionDelegate {
        var onSwitch: () -> Void

        init(onSwitch: @escaping () -> Void) {
            self.onSwitch = onSwitch
        }

        func pencilInteraction(
            _ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap
        ) {
            if Self.switches(UIPencilInteraction.preferredTapAction) {
                onSwitch()
            }
        }

        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
        ) {
            if squeeze.phase == .ended, Self.switches(UIPencilInteraction.preferredSqueezeAction) {
                onSwitch()
            }
        }

        // The system runs a shortcut itself; the binder leaves that action, and "Off", alone.
        private static func switches(_ action: UIPencilPreferredAction) -> Bool {
            ![.ignore, .runSystemShortcut].contains(action)
        }
    }
}

#Preview {
    PencilInteractionView(onSwitch: {})
}
