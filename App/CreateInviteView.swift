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
    /// Set once the server created the invite: the page shows it at the top and there is no second Create.
    @State private var createdInvite: CreatedInvite?
    @State private var feedback: ActionFeedback?
    @State private var isCreating = false
    @State private var copied = false
    @FocusState private var quotaFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Pinned: Cancel / Create and Create's busy state stay in view whatever the scroll and the keyboard.
            BarRow(title: "") {
                BarButton(title: createdInvite == nil ? "Cancel" : "Done") { dismiss() }
            } trailing: {
                if createdInvite == nil {
                    if isCreating {
                        ProgressView().tint(Theme.Color.stone)
                    } else {
                        BarButton(title: "Create", bold: true, enabled: canCreate) { createInvite() }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let createdInvite {
                        created(createdInvite)
                    } else {
                        form
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .underPinnedBar()
            .actionBanner($feedback)
        }
        .rfPage()
        .task { await probeAccessSupport() }
        #if DEBUG
        .task { await composeMarkedTextForCheck() }
        #endif
    }

    @ViewBuilder
    private var form: some View {
        DotTitle(text: "New invite", size: 46, dot: .filled)
            .padding(.top, 14)
            .entrance(0)

        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Invite").padding(.top, 26).padding(.bottom, 2)
            Rule()
        }
        .entrance(1)
        VStack(alignment: .leading, spacing: 0) {
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
        }
        .disabled(isCreating)
        .entrance(2)
    }

    /// The created invite, at the top of the page: the code, what it gives, Copy and Share.
    private func created(_ invite: CreatedInvite) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DotTitle(text: "Invite created", size: 46, dot: .filled, lineLimit: 2)
                .padding(.top, 14)
            Text(invite.code)
                .font(Theme.Font.mono(26, medium: true))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
                .padding(.top, 22)
            Text(summary(invite))
                .font(Theme.Font.text(13.5))
                .foregroundStyle(Theme.Color.stone)
                .padding(.top, 8)
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = invite.code
                    if !copied { Haptics.select() }
                    withAnimation(Motion.fade) { copied = true }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(OutlineButtonStyle())
                ShareLink(item: invite.code) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(OutlineButtonStyle())
            }
            .padding(.top, 18)
            Rule().padding(.top, 24)
        }
        .transition(.opacity)
    }

    private func summary(_ invite: CreatedInvite) -> String {
        [invite.label,
         "\(invite.maxDevices) device" + (invite.maxDevices == 1 ? "" : "s"),
         "\(invite.monthlyQuotaGB) GB",
         supportsAccess ? RegionPolicy.name(of: region, in: InviteRegionOptions.options(ownerRegions: appState.regions, current: region)) : nil,
         supportsAccess ? access.summary : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
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
        // One Create per invite: never a second POST for the same form, not even on a fast double tap.
        guard !isCreating, createdInvite == nil else { return }
        isCreating = true
        feedback = nil
        copied = false
        Task {
            // Read the fields only after editing ended: text still being composed is in them now.
            await EditCommit.endEditing()
            let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let profile = appState.currentProfile, !trimmedCode.isEmpty,
                  case .success(let quota) = QuotaInput.parse(quotaText) else {
                isCreating = false
                return
            }
            let body = InviteBody.create(
                code: trimmedCode,
                label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                maxDevices: maxDevices,
                monthlyQuotaGB: quota,
                region: supportsAccess ? region : nil,
                access: supportsAccess ? access : nil
            )
            do {
                let invite = try await send(body, token: profile.token)
                withAnimation(.easeInOut(duration: 0.25)) { createdInvite = invite }
                code = invite.code
                label = invite.label
                feedback = .success("Invite created")
            } catch {
                feedback = .failure(error.localizedDescription)
            }
            isCreating = false
        }
    }

    private func send(_ body: [String: JSONValue], token: String) async throws -> CreatedInvite {
        #if DEBUG
        if ScreenshotMode.isOn {
            return try await DemoAPI.createInvite(body: body, existing: ScreenshotMode.ownerInvites.map(\.code))
        }
        #endif
        return try await APIClient.shared.createInvite(body: body, token: token)
    }

    #if DEBUG
    /// `-RFVMarkedText p`: fill the form and leave "p" composing in Name, as on the phone where this went wrong.
    /// `-RFVPrefillCreate`: the same, with nothing composed (the UI test types "p" on the Pinyin keyboard).
    private func composeMarkedTextForCheck() async {
        guard ScreenshotMode.isOn, ScreenshotMode.markedText != nil || ScreenshotMode.prefillsCreate else { return }
        code = ScreenshotMode.markedFormCode
        label = ScreenshotMode.markedFormLabel
        try? await Task.sleep(nanoseconds: 800_000_000)
        ScreenshotMode.compose(ScreenshotMode.markedText ?? "", inFieldShowing: ScreenshotMode.markedFormLabel)
    }
    #endif
}

#Preview {
    CreateInviteView()
        .environmentObject(AppState())
}
