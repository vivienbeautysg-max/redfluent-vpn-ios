import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tunnelManager: TunnelManager
    @State private var showingDiagnostics = false
    @State private var showingSignOutConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    statusOrb
                    statusLabel
                    connectButton
                    serverCard
                    profileCard
                    Spacer(minLength: Theme.Spacing.xl)
                    privacyFootnote
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.xl)
            }
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("RedFluent VPN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingDiagnostics = true } label: {
                            Label("Diagnostics", systemImage: "stethoscope")
                        }
                        Button(role: .destructive) {
                            showingSignOutConfirm = true
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingDiagnostics) {
                DiagnosticsView()
            }
            .confirmationDialog("Remove activation from this device?",
                                isPresented: $showingSignOutConfirm,
                                titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { appState.signOut() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your invite remains valid. You can re-activate by entering the same invite code.")
            }
            .task {
                await tunnelManager.loadStatus()
                await appState.refresh()
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: tunnelManager.status.isConnected
                ? [Theme.Color.success.opacity(0.18), Color(.systemBackground)]
                : [Theme.Color.brandPrimary.opacity(0.10), Color(.systemBackground)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var statusOrb: some View {
        ZStack {
            Circle()
                .fill(orbGradient)
                .frame(width: 200, height: 200)
                .shadow(color: orbShadowColor, radius: 30, x: 0, y: 12)
            Image(systemName: orbIcon)
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(Theme.Color.textOnBrand)
        }
        .padding(.top, Theme.Spacing.lg)
        .scaleEffect(tunnelManager.status.isConnected ? 1.05 : 1.0)
        .animation(.spring(duration: 0.6), value: tunnelManager.status)
    }

    private var orbGradient: LinearGradient {
        switch tunnelManager.status {
        case .connected:
            return LinearGradient(colors: [Theme.Color.success, Theme.Color.success.opacity(0.7)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .connecting, .disconnecting:
            return LinearGradient(colors: [Theme.Color.warning, Theme.Color.warning.opacity(0.7)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .failed:
            return LinearGradient(colors: [Theme.Color.danger, Theme.Color.danger.opacity(0.7)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .disconnected:
            return LinearGradient(colors: [Theme.Color.brandPrimary, Theme.Color.brandSecondary],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var orbShadowColor: Color {
        switch tunnelManager.status {
        case .connected: return Theme.Color.success.opacity(0.4)
        case .failed:    return Theme.Color.danger.opacity(0.4)
        default:         return Theme.Color.brandPrimary.opacity(0.4)
        }
    }

    private var orbIcon: String {
        switch tunnelManager.status {
        case .connected:                       return "lock.shield.fill"
        case .connecting, .disconnecting:      return "arrow.triangle.2.circlepath"
        case .failed:                          return "exclamationmark.triangle.fill"
        case .disconnected:                    return "lock.shield"
        }
    }

    private var statusLabel: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(tunnelManager.status.displayName)
                .font(Theme.Font.displayMedium)
                .foregroundStyle(Theme.Color.textPrimary)
            Text(tunnelManager.status.detail)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var connectButton: some View {
        Button {
            Task { await tunnelManager.toggle() }
        } label: {
            Text(tunnelManager.status.isConnected ? "Disconnect" : "Connect")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(tunnelManager.status.isConnected
                            ? Theme.Color.danger
                            : Theme.Color.brandPrimary)
                .foregroundStyle(Theme.Color.textOnBrand)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .disabled(tunnelManager.status == .connecting || tunnelManager.status == .disconnecting)
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            row(icon: "globe.asia.australia.fill", label: "Server",
                value: appState.currentProfile?.serverRegion ?? "Tokyo")
            Divider()
            row(icon: "shield.lefthalf.filled", label: "Mode", value: "Secure Tunnel")
            Divider()
            row(icon: "antenna.radiowaves.left.and.right", label: "Provider", value: "RedFluent")
        }
        .card()
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(Theme.Color.brandPrimary)
                Text(appState.currentProfile?.ownerLabel ?? "—")
                    .font(Theme.Font.titleLarge)
                Spacer()
            }
            Text("Profile \(shortProfileId)")
                .font(Theme.Font.monoBody)
                .foregroundStyle(Theme.Color.textSecondary)
            Text("Config v\(appState.currentProfile?.configVersion ?? "—")")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .card()
    }

    private var shortProfileId: String {
        guard let id = appState.currentProfile?.profileId else { return "—" }
        return String(id.suffix(8))
    }

    private var privacyFootnote: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Link("Privacy", destination: URL(string: "https://www.redfluent.com/privacy")!)
            Link("Terms",   destination: URL(string: "https://www.redfluent.com/terms")!)
            Link("Support", destination: URL(string: "https://www.redfluent.com/support")!)
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Color.textSecondary)
        .padding(.bottom, Theme.Spacing.lg)
    }

    private func row(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Theme.Color.brandPrimary)
                .frame(width: 22)
            Text(label).foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(Theme.Font.body)
    }
}

#Preview {
    let state = AppState()
    return MainDashboardView()
        .environmentObject(state)
        .environmentObject(TunnelManager())
}
