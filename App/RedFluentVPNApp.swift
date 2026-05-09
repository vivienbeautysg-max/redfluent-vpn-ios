import SwiftUI

@main
struct RedFluentVPNApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var tunnelManager = TunnelManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(tunnelManager)
                .preferredColorScheme(nil)
                .task {
                    await tunnelManager.loadStatus()
                    await appState.refresh()
                }
        }
    }
}
