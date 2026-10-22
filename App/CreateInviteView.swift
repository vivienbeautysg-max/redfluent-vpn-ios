import SwiftUI
import UIKit

struct CreateInviteView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var label = ""
    @State private var maxDevices = 1
    @State private var monthlyQuotaGB = 200
    @State private var region = RegionPolicy.defaultID
    @State private var access = AccessChoice()
    /// Does the backend know about region / access? Asked once; older backends do not, and then the controls stay hidden.
    @State private var supportsAccess = false
    @State private var createdInvite: CreatedInvite?
    @State private var errorMessage: String?
    @State private var isCreating = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("New Invite") {
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Theme.Font.monoBody)
                    TextField("Label (optional)", text: $label)
                        .textInputAutocapitalization(.words)
                    Stepper("Device limit: \(maxDevices)", value: $maxDevices, in: 1...100)
                    Stepper("Monthly limit: \(monthlyQuotaGB) GB", value: $monthlyQuotaGB, in: 1...2000, step: 50)
                }

                if supportsAccess {
                    Section {
                        InviteAccessRows(
                            region: $region,
                            access: $access,
                            regionOptions: InviteRegionOptions.options(ownerRegions: appState.regions, current: nil)
                        )
                    }
                }

                if let createdInvite {
                    Section("Created") {
                        LabeledContent("Code", value: createdInvite.code)
                            .font(Theme.Font.monoBody)
                        LabeledContent("Label", value: createdInvite.label)
                        LabeledContent("Device limit", value: "\(createdInvite.maxDevices)")
                        LabeledContent("Monthly limit", value: "\(createdInvite.monthlyQuotaGB) GB")
                        if supportsAccess {
                            LabeledContent("Region", value: RegionPolicy.name(of: region, in: InviteRegionOptions.options(ownerRegions: appState.regions, current: region)))
                            LabeledContent("Access", value: access.summary)
                        } else {
                            LabeledContent("Expires", value: "Never")
                        }
                        Button {
                            UIPasteboard.general.string = createdInvite.code
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy code", systemImage: "doc.on.doc")
                        }
                        ShareLink("Share code", item: createdInvite.code)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.Color.danger)
                    }
                }
            }
            .navigationTitle("Create Invite")
            .task { await probeAccessSupport() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createInvite()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(isCreating || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func probeAccessSupport() async {
        #if DEBUG
        if ScreenshotMode.isOn {
            supportsAccess = true
            return
        }
        #endif
        guard let token = appState.currentProfile?.token,
              let result = try? await APIClient.shared.fetchOwnerInvites(token: token) else { return }
        supportsAccess = result.access.values.contains { $0.isPresent }
    }

    private func createInvite() {
        guard let profile = appState.currentProfile else {
            errorMessage = "No active profile"
            return
        }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            errorMessage = "Invite code is required"
            return
        }

        isCreating = true
        errorMessage = nil
        copied = false
        let body = InviteBody.create(
            code: trimmedCode,
            label: trimmedLabel.isEmpty ? nil : trimmedLabel,
            maxDevices: maxDevices,
            monthlyQuotaGB: monthlyQuotaGB,
            region: supportsAccess ? region : nil,
            access: supportsAccess ? access : nil
        )
        Task {
            do {
                let invite = try await APIClient.shared.createInvite(body: body, token: profile.token)
                createdInvite = invite
                code = invite.code
                label = invite.label
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}

#Preview {
    CreateInviteView()
        .environmentObject(AppState())
}
