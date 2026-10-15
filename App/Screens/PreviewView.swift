import AppCore
import SwiftUI

/// The rendered PDF, with the share button and a banner naming the tasks that did not fit.
struct PreviewView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let shareButton = "shareButton"
        static let omittedTasksBanner = "omittedTasksBanner"
    }

    let rendered: RenderedAgenda

    var body: some View {
        PDFKitView(url: rendered.url)
            .accessibilityIdentifier(AgendaView.ID.pdfPreview)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !rendered.omittedTasks.isEmpty {
                    banner
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

    private var bannerTitle: String {
        let count = rendered.omittedTasks.count
        return count == 1
            ? "1 task didn't fit on the to-do list and was left out:"
            : "\(count) tasks didn't fit on the to-do list and were left out:"
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bannerTitle)
                .font(.footnote.weight(.semibold))
            ForEach(Array(rendered.omittedTasks.enumerated()), id: \.offset) { _, text in
                Text(text)
                    .font(.footnote)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(ID.omittedTasksBanner)
    }
}
