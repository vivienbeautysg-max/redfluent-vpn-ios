import SwiftUI

@main
struct RedFluentVPNApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var tunnelManager = TunnelManager()
    @StateObject private var statsStore = StatsStore()
    @StateObject private var quotaStore = QuotaStore()
    /// When the app last reconnected by itself after a server stop (at most once in 30 minutes).
    @State private var lastAutoReconnect = Date.distantPast

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(tunnelManager)
                .environmentObject(statsStore)
                .environmentObject(quotaStore)
                .preferredColorScheme(nil)
                .onChange(of: appState.selectedRegionID) { _, _ in
                    // Any change of the selection (picker, or a server-side reset): reconnect when
                    // connected, otherwise keep the saved tunnel configuration in step with it.
                    Task { await tunnelManager.selectedRegionChanged() }
                }
                .onChange(of: tunnelManager.serverStop) { _, stop in
                    guard let stop else { return }
                    Task { await handleServerStop(stop) }
                }
                .onChange(of: appState.expiry.expired) { _, expired in
                    // The account just turned out to be expired: do not keep the tunnel up.
                    guard expired, tunnelManager.status.isConnected else { return }
                    Task { await tunnelManager.disconnect() }
                }
                .task {
                    #if DEBUG
                    if ScreenshotMode.isOn {
                        let now = Date()
                        tunnelManager.status = .connected   // 让 Live Traffic 卡片展示真实的已连接形态
                        statsStore.snapshot = ScreenshotMode.stats(now: now)
                        quotaStore.injectForScreenshot(ScreenshotMode.quota(now: now))
                        return
                    }
                    #endif
                    await tunnelManager.loadStatus()
                    await appState.refresh()
                }
        }
    }

    /// The tunnel stopped because the server ended access. /profile says what that means: Expired state, or
    /// Revoked screen. A "revoked" stop with a profile that is fine only meant a stale login token in the
    /// tunnel's saved configuration, so start again once with the current one.
    private func handleServerStop(_ stop: ServerStop) async {
        let answered = await appState.refresh()
        tunnelManager.acknowledgeServerStop()
        guard answered, stop == .revoked, case .activated = appState.activation, !appState.expiry.expired,
              Date().timeIntervalSince(lastAutoReconnect) > 1800 else { return }
        lastAutoReconnect = Date()
        await tunnelManager.connect()
    }
}
