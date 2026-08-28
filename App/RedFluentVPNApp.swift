import SwiftUI

@main
struct RedFluentVPNApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var tunnelManager = TunnelManager()
    @StateObject private var statsStore = StatsStore()
    @StateObject private var quotaStore = QuotaStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(tunnelManager)
                .environmentObject(statsStore)
                .environmentObject(quotaStore)
                .preferredColorScheme(nil)
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
}
