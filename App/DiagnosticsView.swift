import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var tunnelManager: TunnelManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

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
}
