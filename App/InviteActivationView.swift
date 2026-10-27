import SwiftUI

struct InviteActivationView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var inviteCode: String = ""
    @State private var feedback: ActionFeedback?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 700
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Wordmark()
                        .frame(height: 50)
                        .entrance(0)
                    LandingArt(landed: false, height: compact ? 150 : 200, showsPower: false)
                        .padding(.horizontal, -Theme.gutter)
                        .padding(.top, compact ? 0 : 12)
                        .entrance(1)
                    DotTitle(text: "Invite code", size: compact ? 44 : 50, dot: .filled)
                        .padding(.top, compact ? 10 : 20)
                        .entrance(2)
                    if appState.signedOut {
                        Label(SignedOut.notice, systemImage: "rectangle.portrait.and.arrow.right")
                            .font(Theme.Font.text(14, .semibold))
                            .foregroundStyle(Theme.Color.red)
                            .padding(.top, 12)
                    }
                    TextField("", text: $inviteCode, prompt: Text("RF-XXXX-XXXX").foregroundStyle(Theme.Color.stone))
                        .font(Theme.Font.mono(20, medium: true))
                        .foregroundStyle(Theme.Color.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .submitLabel(.go)
                        .onSubmit { redeem() }
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(fieldFocused ? Theme.Color.ink : Theme.Color.rule).frame(height: fieldFocused ? 1.5 : 1)
                        }
                        .padding(.top, compact ? 16 : 26)
                        .accessibilityLabel("Invite code")
                        .entrance(3)
                    Button {
                        redeem()
                    } label: {
                        if isBusy {
                            ProgressView().tint(Theme.Color.onRed)
                        } else {
                            Text("Activate")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !isBusy))
                    .disabled(isBusy)
                    .padding(.top, 22)
                    .entrance(4)
                    if FeatureFlags.appleSignInEnabled {
                        appleRecoverSection.padding(.top, 18)
                    }
                    footer
                        .padding(.top, 28)
                        .entrance(5)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .actionBanner($feedback)   // inside the reader: the banner's space never flips the compact layout
        }
        .rfPage()
        .onChange(of: appState.lastActivationError) { _, error in
            // Activation and Apple recovery both report here; the banner shows it above the keyboard.
            if let error { feedback = .failure(error) }
        }
        .onAppear {
            #if DEBUG
            if ScreenshotMode.isOn { return }   // screenshots: no keyboard over the page
            #endif
            fieldFocused = true
        }
    }

    // For someone on a new phone: no need to ask the owner for the code again.
    private var appleRecoverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New phone").rfLabelStyle()
            AppleRecoverButton(
                onLightBackground: colorScheme != .dark,
                onToken: { token in
                    Task { await appState.recoverWithApple(identityToken: token) }
                },
                onError: { message in
                    appState.lastActivationError = message
                }
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 22) {
            footerLink("Privacy", "https://www.redfluent.com/privacy")
            footerLink("Terms", "https://www.redfluent.com/terms")
            footerLink("Support", "https://www.redfluent.com/support")
        }
        .font(Theme.Font.text(13, .medium))
        .foregroundStyle(Theme.Color.stone)
        .tint(Theme.Color.stone)
    }

    private func footerLink(_ title: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Text(title).touchTarget(height: 16)
        }
        .buttonStyle(PressStyle())
    }

    private var isBusy: Bool {
        if case .activating = appState.activation { return true } else { return false }
    }

    private func redeem() {
        guard !isBusy else { return }
        Task {
            // Read the field only after editing ended: text still being composed is in it now.
            await EditCommit.endEditing()
            #if DEBUG
            if ScreenshotMode.isOn {
                // Demo runs never activate against the real server: answer as it does for an unknown code.
                appState.lastActivationError = nil
                await DemoAPI.accept()
                appState.lastActivationError = APIError.status(403, #"{"ok":false,"error":"invalid invite"}"#).localizedDescription
                return
            }
            #endif
            await appState.redeem(inviteCode: inviteCode)
            // Success replaces this page with the home screen; say so in the hand too.
            if appState.currentProfile != nil { Haptics.success() }
        }
    }
}

#Preview {
    InviteActivationView()
        .environmentObject(AppState())
}
