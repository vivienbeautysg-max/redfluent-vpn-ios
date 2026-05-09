import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var tunnelManager: TunnelManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsStore: StatsStore
    @Environment(\.dismiss) private var dismiss

    private static let tsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section("Tunnel") {
                    LabeledContent("Status", value: tunnelManager.status.displayName)
                    LabeledContent("Server", value: appState.currentProfile?.serverRegion ?? "—")
                    LabeledContent("Mode",   value: "Secure Tunnel")
                }

                if let profile = appState.currentProfile {
                    Section("Activation") {
                        LabeledContent("Owner",   value: profile.ownerLabel)
                        LabeledContent("Profile", value: profile.profileId)
                            .font(Theme.Font.monoBody)
                        LabeledContent("Config",  value: profile.configVersion)
                        if let exp = profile.expiresAt {
                            LabeledContent("Expires", value: exp)
                        }
                    }
                }

                Section("Device") {
                    LabeledContent("Public ID", value: DeviceIdentity.publicId)
                        .font(Theme.Font.monoBody)
                    LabeledContent("App",       value: DeviceIdentity.appVersion)
                }

                Section("Live Stats") {
                    if let snap = statsStore.snapshot {
                        LabeledContent("Timestamp",
                                       value: Self.tsFormatter.string(from: snap.timestamp))
                            .font(Theme.Font.monoBody)
                        LabeledContent("Active conns", value: "\(snap.activeConnections)")
                        LabeledContent("Proxy:Direct",
                                       value: "\(snap.proxyConnections):\(snap.directConnections)")
                        LabeledContent("Total ↑", value: "\(snap.totalUp) B")
                        LabeledContent("Total ↓", value: "\(snap.totalDown) B")
                        LabeledContent("Tunnel ping",
                                       value: snap.pingMs.map { "\($0) ms" } ?? "—")
                    } else {
                        Text("No snapshot yet")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    LabeledContent("Light ping",
                                   value: statsStore.lastPingMs.map { "\($0) ms" } ?? "—")
                    if let err = statsStore.lastRefreshError {
                        LabeledContent("Refresh error", value: err)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.danger)
                    }
                }

                Section("Last error") {
                    Text(tunnelManager.lastError ?? appState.lastActivationError ?? "No recent error")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.textSecondary)
                }

                Section {
                    ShareLink("Copy diagnostics", item: diagnosticsText)
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var diagnosticsText: String {
        let profile = appState.currentProfile
        return """
        RedFluent VPN diagnostics
        Status:    \(tunnelManager.status.displayName)
        Server:    \(profile?.serverRegion ?? "—")
        Mode:      Secure Tunnel
        Owner:     \(profile?.ownerLabel ?? "—")
        Profile:   \(profile?.profileId ?? "—")
        Config:    \(profile?.configVersion ?? "—")
        Device:    \(DeviceIdentity.publicId)
        App:       \(DeviceIdentity.appVersion)
        Last err:  \(tunnelManager.lastError ?? appState.lastActivationError ?? "none")
        """
    }
}

#Preview {
    DiagnosticsView()
        .environmentObject(TunnelManager())
        .environmentObject(AppState())
        .environmentObject(StatsStore())
}
