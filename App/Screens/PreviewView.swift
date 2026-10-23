import AppCore
import SwiftUI

/// The rendered PDF, with the share button and a banner naming the tasks that did not fit.
struct PreviewView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let shareButton = "shareButton"
    }

    let rendered: RenderedAgenda

    var body: some View {
        PDFKitView(url: rendered.url)
            .accessibilityIdentifier(AgendaView.ID.pdfPreview)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !rendered.omittedTasks.isEmpty {
                    OmittedTasksBanner(tasks: rendered.omittedTasks)
                }
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: rendered.url) {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier(ID.shareButton)
                }
            }
    }
}
