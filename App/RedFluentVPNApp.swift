import SwiftUI

@main
struct RedFluentVPNApp: App {
    @StateObject private var tunnelManager = TunnelManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tunnelManager)
                .task {
                    await tunnelManager.loadStatus()
                }
        }
    }
}
