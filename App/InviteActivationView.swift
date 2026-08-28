import SwiftUI

struct InviteActivationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var inviteCode: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            backgroundGradient
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    Spacer(minLength: Theme.Spacing.xxl)
                    logo
                    headline
                    Spacer(minLength: Theme.Spacing.lg)
                    activationCard
                    if FeatureFlags.appleSignInEnabled {
                        appleRecoverSection
                    }
                    privacyFootnote
                    Spacer(minLength: Theme.Spacing.lg)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .onAppear { fieldFocused = true }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Theme.Color.brandPrimary, Theme.Color.brandSecondary],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 96, height: 96)
            Text("RF")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.textOnBrand)
        }
        .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 6)
    }

    private var headline: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("RedFluent VPN")
                .font(Theme.Font.displayLarge)
                .foregroundStyle(Theme.Color.textOnBrand)
            Text("Private secure tunnel for trusted devices")
                .font(Theme.Font.bodyLarge)
                .foregroundStyle(Theme.Color.textOnBrand.opacity(0.85))
                .multilineTextAlignment(.center)
        }
    }

    private var activationCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Enter your invite code")
                .font(Theme.Font.titleLarge)
                .foregroundStyle(Theme.Color.textPrimary)

            Text("RedFluent VPN is private invite-only software. Each device receives its own revocable profile.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)

            TextField("Invite code", text: $inviteCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(Theme.Font.monoBody)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .focused($fieldFocused)
                .submitLabel(.go)
                .onSubmit { redeem() }

            if let err = appState.lastActivationError {
                Text(err)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            activationButton
        }
        .padding(Theme.Spacing.lg)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
    }

    private var activationButton: some View {
        Button {
            redeem()
        } label: {
            HStack {
                if case .activating = appState.activation {
                    ProgressView().tint(Theme.Color.textOnBrand)
                } else {
                    Text("Activate")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Color.brandPrimary)
            .foregroundStyle(Theme.Color.textOnBrand)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .disabled(isBusy)
    }

    // 换了手机的人走这条：不用再回去找 owner 要邀请码。
    private var appleRecoverSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("换了手机？")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textOnBrand.opacity(0.85))
            AppleRecoverButton(
                onLightBackground: false,
                onToken: { token in
                    Task { await appState.recoverWithApple(identityToken: token) }
                },
                onError: { message in
                    appState.lastActivationError = message
                }
            )
        }
        .padding(.horizontal, Theme.Spacing.sm)
    }

    private var privacyFootnote: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Link("Privacy", destination: URL(string: "https://www.redfluent.com/privacy")!)
            Link("Terms",   destination: URL(string: "https://www.redfluent.com/terms")!)
            Link("Support", destination: URL(string: "https://www.redfluent.com/support")!)
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Color.textOnBrand.opacity(0.85))
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
