import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tunnelManager: TunnelManager
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var quotaStore: QuotaStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingDiagnostics = false
    @State private var showingCreateInvite = false
    @State private var showingOwnerAdmin = false
    @State private var showingSignOutConfirm = false
    @State private var heartbeatTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    TrafficOrbRing(
                        status: tunnelManager.status,
                        snapshot: statsStore.snapshot,
                        action: { await tunnelManager.toggle() }
                    )
                    statusLabel
                    serverCard
                    StatsCardView()
                    QuotaCardView()
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
                        if appState.currentProfile?.ownerLabel == "Owner" {
                            Button { showingOwnerAdmin = true } label: {
                                Label("Owner admin", systemImage: "person.badge.key")
                            }
                            Button { showingCreateInvite = true } label: {
                                Label("Create invite", systemImage: "plus.circle")
                            }
                        }
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
            .sheet(isPresented: $showingCreateInvite) {
                CreateInviteView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingOwnerAdmin) {
                OwnerAdminView()
                    .environmentObject(appState)
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
                statsStore.refresh()
                await statsStore.ping()
                quotaStore.refresh(token: appState.currentProfile?.token)
                statsStore.startAutoRefresh()
                startHeartbeat()
            }
            .onDisappear {
                statsStore.stopAutoRefresh()
                stopHeartbeat()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    statsStore.refresh()
                    Task { await statsStore.ping() }
                    quotaStore.refresh(token: appState.currentProfile?.token)
                    statsStore.startAutoRefresh()
                    startHeartbeat()
                } else {
                    statsStore.stopAutoRefresh()
                    stopHeartbeat()
                }
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

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                await sendHeartbeat()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        Task { await sendHeartbeat(forceDisconnected: true) }
    }

    private func sendHeartbeat(forceDisconnected: Bool = false) async {
        guard let token = appState.currentProfile?.token else { return }
        let snap = statsStore.snapshot
        let connected = forceDisconnected ? false : (tunnelManager.status == .connected && (snap?.connected ?? false))
        try? await APIClient.shared.sendHeartbeat(
            connected: connected,
            activeConnections: snap?.activeConnections,
            totalUp: snap?.totalUp,
            totalDown: snap?.totalDown,
            token: token
        )
    }
}

#Preview {
    MainDashboardView()
        .environmentObject(AppState())
        .environmentObject(TunnelManager())
        .environmentObject(StatsStore())
        .environmentObject(QuotaStore())
}
