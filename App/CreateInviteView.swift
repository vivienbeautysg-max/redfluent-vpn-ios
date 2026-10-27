import SwiftUI
import UIKit

struct CreateInviteView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var label = ""
    @State private var maxDevices = 1
    @State private var quotaText = "200"
    @State private var region = RegionPolicy.defaultID
    @State private var access = AccessChoice()
    /// Does the backend know about region / access? Asked once; older backends do not, and then the controls stay hidden.
    @State private var supportsAccess = false
    @State private var createdInvite: CreatedInvite?
    @State private var errorMessage: String?
    @State private var isCreating = false
    @State private var copied = false
    @FocusState private var quotaFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BarRow(title: "") {
                    BarButton(title: createdInvite == nil ? "Cancel" : "Done") { dismiss() }
                } trailing: {
                    if isCreating {
                        ProgressView().tint(Theme.Color.stone)
                    } else {
                        BarButton(title: "Create", bold: true, enabled: canCreate) { createInvite() }
                    }
                }
                DotTitle(text: "New invite", size: 46, dot: .filled)
                    .padding(.top, 14)

                SectionLabel(text: "Invite").padding(.top, 26).padding(.bottom, 2)
                Rule()
                SettingRow(label: "Code") {
                    ThemedField(placeholder: "RF-XXXX-XXXX", text: $code, mono: true)
                }
                SettingRow(label: "Name") {
                    ThemedField(placeholder: "Optional", text: $label)
                }
                QuotaField(text: $quotaText, focused: $quotaFocused)
                SettingRow(label: "Device limit") {
                    NumberStepper(value: $maxDevices, range: PersonDraft.deviceLimit)
                }
                if supportsAccess {
                    InviteAccessRows(
                        region: $region,
                        access: $access,
                        regionOptions: InviteRegionOptions.options(ownerRegions: appState.regions, current: nil)
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.text(13, .medium))
                        .foregroundStyle(Theme.Color.red)
                        .padding(.top, 14)
                }

                if let createdInvite {
                    created(createdInvite)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .rfPage()
        .task { await probeAccessSupport() }
    }

    private func created(_ invite: CreatedInvite) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Created").padding(.top, 28).padding(.bottom, 10)
            Text(invite.code)
                .font(Theme.Font.mono(22, medium: true))
                .foregroundStyle(Theme.Color.ink)
                .textSelection(.enabled)
            Text([invite.label,
                  "\(invite.maxDevices) device" + (invite.maxDevices == 1 ? "" : "s"),
                  "\(invite.monthlyQuotaGB) GB",
                  supportsAccess ? RegionPolicy.name(of: region, in: InviteRegionOptions.options(ownerRegions: appState.regions, current: region)) : nil,
                  supportsAccess ? access.summary : nil]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " \u{00B7} "))
                .font(Theme.Font.text(13))
                .foregroundStyle(Theme.Color.stone)
                .padding(.top, 6)
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = invite.code
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(OutlineButtonStyle())
                ShareLink(item: invite.code) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(OutlineButtonStyle())
            }
            .padding(.top, 14)
        }
    }

    private var canCreate: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (try? QuotaInput.parse(quotaText).get()) != nil
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
            errorMessage = "Not signed in"
            return
        }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty, case .success(let quota) = QuotaInput.parse(quotaText) else { return }

        isCreating = true
        errorMessage = nil
        copied = false
        quotaFocused = false
        let body = InviteBody.create(
            code: trimmedCode,
            label: trimmedLabel.isEmpty ? nil : trimmedLabel,
            maxDevices: maxDevices,
            monthlyQuotaGB: quota,
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
