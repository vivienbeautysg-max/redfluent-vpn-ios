import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var tunnelManager: TunnelManager

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Tunnel", value: tunnelManager.status.displayName)
                LabeledContent("Server", value: "Tokyo")
                LabeledContent("Mode", value: "Secure Tunnel")
                LabeledContent("Config", value: "review-safe-profile-v1")
            }

            Section("Last Error") {
                Text(tunnelManager.lastError ?? "No recent error")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ShareLink("Copy diagnostics", item: diagnosticsText)
            }
        }
        .navigationTitle("Diagnostics")
    }

    private var diagnosticsText: String {
        """
        RedFluent VPN diagnostics
        Status: \(tunnelManager.status.displayName)
        Server: Tokyo
        Mode: Secure Tunnel
        Config: review-safe-profile-v1
        Last error: \(tunnelManager.lastError ?? "none")
        """
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
            .environmentObject(TunnelManager())
    }
}
