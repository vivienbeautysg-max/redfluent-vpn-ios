import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var onboardingDone: Bool = {
        #if DEBUG
        if ScreenshotMode.isOn { return !ScreenshotMode.wantsOnboardingShot }
        #endif
        return UserDefaults.standard.bool(forKey: "rfv.onboardingDone")
    }()

    var body: some View {
        Group {
            if !onboardingDone {
                OnboardingView(done: $onboardingDone)
            } else {
                switch appState.activation {
                case .notActivated, .activating, .error:
                    InviteActivationView()
                case .activated:
                    MainDashboardView()
                case .revoked:
                    RevokedView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingDone)
        .animation(.easeInOut(duration: 0.3), value: stateKey)
    }

    private var stateKey: String {
        switch appState.activation {
        case .notActivated:  return "notActivated"
        case .activating:    return "activating"
        case .activated:     return "activated"
        case .revoked:       return "revoked"
        case .error:         return "error"
        }
    }
}

struct RevokedView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "lock.slash.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Theme.Color.danger)
            Text("Access revoked")
                .font(Theme.Font.displayMedium)
            Text("This device's RedFluent VPN access has been disabled. Contact RedFluent support to re-enable, or enter a different invite code.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)
            Button("Enter a different invite") {
                appState.signOut()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Color.brandPrimary)
            Link("Contact support", destination: URL(string: "https://www.redfluent.com/support")!)
                .font(Theme.Font.caption)
        }
        .padding(Theme.Spacing.lg)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(TunnelManager())
}
