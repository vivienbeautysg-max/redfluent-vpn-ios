import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
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

private struct RevokedView: View {
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
