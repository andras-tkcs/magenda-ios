import SwiftUI

/// A banner naming the tasks that did not fit on the to-do list and were left out.
struct OmittedTasksBanner: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let omittedTasksBanner = "omittedTasksBanner"
    }

    let tasks: [String]

    private var title: String {
        tasks.count == 1
            ? "1 task didn't fit on the to-do list and was left out:"
            : "\(tasks.count) tasks didn't fit on the to-do list and were left out:"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
            ForEach(Array(tasks.enumerated()), id: \.offset) { _, text in
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
