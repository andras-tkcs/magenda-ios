import AppCore
import SwiftUI

/// How the PDF looks: its font and its five colors, pushed from the settings form.
struct LookView: View {
    /// The accessibility identifiers UI tests find elements by.
    enum ID {
        static let form = "lookForm"
        static let colorError = "colorError"
        static let resetColorsButton = "resetColorsButton"

        static func fontOption(_ pack: FontPack) -> String { "fontOption.\(pack.rawValue)" }
        static func colorField(_ role: ColorRole) -> String { "colorField.\(role.rawValue)" }
    }

    /// The five colors the person can change.
    enum ColorRole: String, CaseIterable, Identifiable {
        case weekend, heading, label, accent, notes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .weekend: "Weekend"
            case .heading: "Date heading"
            case .label: "Section labels"
            case .accent: "Accent"
            case .notes: "Notes heading"
            }
        }

        var keyPath: WritableKeyPath<ThemeColors, RGBColor> {
            switch self {
            case .weekend: \.weekend
            case .heading: \.heading
            case .label: \.label
            case .accent: \.accent
            case .notes: \.notes
            }
        }
    }

    @Environment(AgendaController.self) private var controller

    @State private var hexDrafts: [ColorRole: String] = [:]
    @State private var invalidRoles: Set<ColorRole> = []

    var body: some View {
        Form {
            fontSection
            colorsSection
        }
        .accessibilityIdentifier(ID.form)
        .navigationTitle("Look")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { resetHexDrafts() }
    }

    private var fontSection: some View {
        Section("Font") {
            ForEach(FontPack.allCases, id: \.self) { pack in
                Button {
                    Task { await controller.updateSettings { $0.fontPack = pack } }
                } label: {
                    HStack {
                        Text(pack.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if controller.settings.fontPack == pack {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityAddTraits(controller.settings.fontPack == pack ? .isSelected : [])
                .accessibilityIdentifier(ID.fontOption(pack))
            }
        }
    }

    private var colorsSection: some View {
        Section("Colors") {
            ForEach(ColorRole.allCases) { role in
                colorRow(role)
            }
            Button("Reset colors") {
                invalidRoles = []
                Task {
                    await controller.updateSettings { $0.colors = .default }
                    resetHexDrafts()
                }
            }
            .accessibilityIdentifier(ID.resetColorsButton)
        }
    }

    private func colorRow(_ role: ColorRole) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                let color = controller.settings.colors[keyPath: role.keyPath]
                RoundedRectangle(cornerRadius: 4)
                    .fill(Self.swatch(color))
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(role.title)
                Spacer()
                TextField("215E99", text: hexBinding(role))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .frame(maxWidth: 120)
                    .onSubmit { commitHex(role) }
                    .accessibilityIdentifier(ID.colorField(role))
            }
            if invalidRoles.contains(role) {
                Text("Use six hex digits, like 215E99.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(ID.colorError)
            }
        }
    }

    private static func swatch(_ color: RGBColor) -> Color {
        Color(
            red: Double(color.red) / 255, green: Double(color.green) / 255,
            blue: Double(color.blue) / 255)
    }

    private func hexBinding(_ role: ColorRole) -> Binding<String> {
        Binding(
            get: { hexDrafts[role] ?? controller.settings.colors[keyPath: role.keyPath].hex },
            set: { hexDrafts[role] = $0 })
    }

    private func commitHex(_ role: ColorRole) {
        let text = hexDrafts[role] ?? ""
        guard let color = RGBColor(hex: text) else {
            invalidRoles.insert(role)
            return
        }
        invalidRoles.remove(role)
        hexDrafts[role] = color.hex
        Task { await controller.updateSettings { $0.colors[keyPath: role.keyPath] = color } }
    }

    private func resetHexDrafts() {
        var drafts: [ColorRole: String] = [:]
        for role in ColorRole.allCases {
            drafts[role] = controller.settings.colors[keyPath: role.keyPath].hex
        }
        hexDrafts = drafts
    }
}

#Preview {
    if let services = AppEnvironment.previewServices() {
        NavigationStack { LookView() }
            .environment(services.controller)
            .environment(services.handoff)
            .task {
                await services.controller.start()
                services.handoff.start()
            }
    }
}
