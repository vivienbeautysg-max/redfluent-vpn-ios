import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var tunnelManager: TunnelManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                header
                statusCard
                connectButton
                serverCard
                Spacer()
                footerLinks
            }
            .padding(24)
            .navigationTitle("RedFluent VPN")
            .toolbar {
                NavigationLink("Logs") {
                    DiagnosticsView()
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Private secure tunnel")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Protect trusted devices on public Wi-Fi and mobile networks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var statusCard: some View {
        VStack(spacing: 10) {
            Text(tunnelManager.status.displayName)
                .font(.title3)
                .fontWeight(.semibold)
            Text(tunnelManager.status.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var connectButton: some View {
        Button {
            Task {
                await tunnelManager.toggle()
            }
        } label: {
            Text(tunnelManager.status.isConnected ? "Disconnect" : "Connect")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(tunnelManager.status == .connecting || tunnelManager.status == .disconnecting)
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoRow(label: "Server", value: "Tokyo")
            InfoRow(label: "Mode", value: "Secure Tunnel")
            InfoRow(label: "Provider", value: "RedFluent")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var footerLinks: some View {
        HStack(spacing: 18) {
            Link("Privacy", destination: URL(string: "https://www.redfluent.com/privacy")!)
            Link("Terms", destination: URL(string: "https://www.redfluent.com/terms")!)
            Link("Support", destination: URL(string: "https://www.redfluent.com/support")!)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

#Preview {
    ContentView()
        .environmentObject(TunnelManager())
}
