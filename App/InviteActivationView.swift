import SwiftUI

struct InviteActivationView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var inviteCode: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 700
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Wordmark()
                        .frame(height: 50)
                    LandingArt(landed: false, height: compact ? 150 : 200, showsPower: false)
                        .padding(.horizontal, -Theme.gutter)
                        .padding(.top, compact ? 0 : 12)
                    DotTitle(text: "Invite code", size: compact ? 44 : 50, dot: .filled)
                        .padding(.top, compact ? 10 : 20)
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
                    if let err = appState.lastActivationError {
                        Text(err)
                            .font(Theme.Font.text(13, .medium))
                            .foregroundStyle(Theme.Color.red)
                            .padding(.top, 10)
                    }
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
                    if FeatureFlags.appleSignInEnabled {
                        appleRecoverSection.padding(.top, 18)
                    }
                    footer
                        .padding(.top, 28)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .rfPage()
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
            Link("Privacy", destination: URL(string: "https://www.redfluent.com/privacy")!)
            Link("Terms", destination: URL(string: "https://www.redfluent.com/terms")!)
            Link("Support", destination: URL(string: "https://www.redfluent.com/support")!)
        }
        .font(Theme.Font.text(13, .medium))
        .foregroundStyle(Theme.Color.stone)
        .tint(Theme.Color.stone)
    }

    private var isBusy: Bool {
        if case .activating = appState.activation { return true } else { return false }
    }

    private func redeem() {
        let code = inviteCode
        Task { await appState.redeem(inviteCode: code) }
    }
}

#Preview {
    InviteActivationView()
        .environmentObject(AppState())
}
