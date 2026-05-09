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
                    await tunnelManager.loadStatus()
                    await appState.refresh()
                }
        }
    }
}
