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
        VStack(spacing: 0) {
            BarRow(title: "") {
                BarButton(title: "Done", bold: true) { dismiss() }
            } trailing: {
                ShareLink(item: diagnosticsText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Color.ink)
                        .frame(width: 28, height: 28)
                        .touchTarget(width: 28, height: 28)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Share diagnostics")
            }
            .padding(.horizontal, Theme.gutter)
            details
        }
        .rfPage()
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DotTitle(text: "Diagnostics", size: 46, dot: .filled)
                    .padding(.top, 14)
                    .entrance(0)

                section("Tunnel", order: 1) {
                    row("Status", tunnelManager.status.displayName)
                    row("Server", appState.serverDisplayName(connected: tunnelManager.status == .connected) ?? HomeFormat.none)
                    row("Mode", "Secure Tunnel")
                }

                if let profile = appState.currentProfile {
                    section("Activation", order: 2) {
                        row("Owner", profile.ownerLabel)
                        row("Profile", profile.profileId, mono: true)
                        row("Config", profile.configVersion, mono: true)
                        if let exp = profile.expiresAt { row("Expires", exp, mono: true) }
                    }
                }

                section("Device", order: 3) {
                    row("Public ID", publicID, mono: true)
                    row("App", DeviceIdentity.appVersion, mono: true)
                    row("Fonts", fontsText, mono: true)
                }

                section("Live stats", order: 4) {
                    if let snap = statsStore.snapshot {
                        row("Timestamp", Self.tsFormatter.string(from: snap.timestamp), mono: true)
                        row("Active conns", "\(snap.activeConnections)", mono: true)
                        row("Proxy:Direct", "\(snap.proxyConnections):\(snap.directConnections)", mono: true)
                        row("Total \u{2191}", "\(snap.totalUp) B", mono: true)
                        row("Total \u{2193}", "\(snap.totalDown) B", mono: true)
                        row("Tunnel ping", snap.pingMs.map { "\($0) ms" } ?? HomeFormat.none, mono: true)
                    } else {
                        row("Snapshot", HomeFormat.none)
                    }
                    row("Light ping", statsStore.lastPingMs.map { "\($0) ms" } ?? HomeFormat.none, mono: true)
                    if let err = statsStore.lastRefreshError {
                        row("Refresh error", err, color: Theme.Color.red)
                    }
                }

                section("Last error", order: 5) {
                    Text(tunnelManager.lastError ?? appState.lastActivationError ?? "None")
                        .font(Theme.Font.text(14))
                        .foregroundStyle((tunnelManager.lastError ?? appState.lastActivationError) == nil ? Theme.Color.stone : Theme.Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) { Rule() }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .underPinnedBar()
    }

    /// This install's public device id; a placeholder in screenshots.
    private var publicID: String {
        #if DEBUG
        if ScreenshotMode.isOn { return "demo-device-0000" }
        #endif
        return DeviceIdentity.publicId
    }

    private var fontsText: String {
        let missing = FontCheck.missing()
        return "\(AppFonts.all.count - missing.count)/\(AppFonts.all.count)"
    }

    private func section<Content: View>(_ title: String, order: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: title).padding(.bottom, 2)
            Rule()
            content()
        }
        .padding(.top, 26)
        .entrance(order)
    }

    private func row(_ label: String, _ value: String, mono: Bool = false, color: Color = Theme.Color.ink) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Theme.Font.text(14, .medium))
                .foregroundStyle(Theme.Color.stone)
                .fixedSize()
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? Theme.Font.mono(12.5) : Theme.Font.text(14, .medium))
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rule() }
    }

    private var diagnosticsText: String {
        let profile = appState.currentProfile
        return """
        Redfluent VPN diagnostics
        Status:    \(tunnelManager.status.displayName)
        Server:    \(appState.serverDisplayName(connected: tunnelManager.status == .connected) ?? "—")
        Mode:      Secure Tunnel
        Owner:     \(profile?.ownerLabel ?? "—")
        Profile:   \(profile?.profileId ?? "—")
        Config:    \(profile?.configVersion ?? "—")
        Device:    \(publicID)
        App:       \(DeviceIdentity.appVersion)
        Fonts:     \(fontsText)
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
