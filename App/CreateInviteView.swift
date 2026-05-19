import SwiftUI
import UIKit

struct CreateInviteView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var label = ""
    @State private var maxDevices = 1
    @State private var monthlyQuotaGB = 200
    @State private var createdInvite: CreatedInvite?
    @State private var errorMessage: String?
    @State private var isCreating = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Theme.Font.monoBody)
                    TextField("Label (optional)", text: $label)
                        .textInputAutocapitalization(.words)
                    Stepper("Device limit: \(maxDevices)", value: $maxDevices, in: 1...100)
                    Stepper("Monthly limit: \(monthlyQuotaGB) GB", value: $monthlyQuotaGB, in: 1...2000, step: 50)
                } header: {
                    Text("New Invite")
                } footer: {
                    Text("The code has no required format and no expiration date. Test invites default to one device and a 200 GB monthly limit.")
                }

                if let createdInvite {
                    Section("Created") {
                        LabeledContent("Code", value: createdInvite.code)
                            .font(Theme.Font.monoBody)
                        LabeledContent("Label", value: createdInvite.label)
                        LabeledContent("Device limit", value: "\(createdInvite.maxDevices)")
                        LabeledContent("Monthly limit", value: "\(createdInvite.monthlyQuotaGB) GB")
                        LabeledContent("Expires", value: "Never")
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
        Task {
            do {
                let invite = try await APIClient.shared.createInvite(
                    code: trimmedCode,
                    label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                    maxDevices: maxDevices,
                    monthlyQuotaGB: monthlyQuotaGB,
                    token: profile.token
                )
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
