import SwiftUI

extension StatusTone {
    var color: Color {
        switch self {
        case .neutral: return Theme.Color.textSecondary
        case .warning: return Theme.Color.warning
        case .danger:  return Theme.Color.danger
        }
    }
}

/// Region (segmented) and Access (preset menu, or custom days) rows of an invite, shared by Create and Edit.
/// Region is a plain value when there is nothing to choose between.
struct InviteAccessRows: View {
    @Binding var region: String
    @Binding var access: AccessChoice
    let regionOptions: [VPNRegion]
    var showsAccess: Bool = true
    var status: InviteStatus?

    var body: some View {
        regionRow
        if showsAccess {
            Picker("Access", selection: $access.preset) {
                ForEach(AccessPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.menu)
            if access.preset == .custom {
                LabeledContent("Days") {
                    TextField("Days", value: $access.customDays, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
            }
        }
        if let status {
            Text(status.text)
                .font(Theme.Font.caption)
                .foregroundStyle(status.tone.color)
        }
    }

    @ViewBuilder
    private var regionRow: some View {
        if regionOptions.count > 1 {
            LabeledContent("Region") {
                Picker("Region", selection: $region) {
                    ForEach(regionOptions) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
        } else {
            LabeledContent("Region", value: regionOptions.first?.name ?? "Tokyo")
        }
    }
}
