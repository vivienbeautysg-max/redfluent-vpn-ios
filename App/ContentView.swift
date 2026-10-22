import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var onboardingDone: Bool = {
        #if DEBUG
        if ScreenshotMode.isOn { return !ScreenshotMode.wantsOnboardingShot }
        #endif
        return UserDefaults.standard.bool(forKey: "rfv.onboardingDone")
    }()

    var body: some View {
        Group {
            if !onboardingDone {
                OnboardingView(done: $onboardingDone)
            } else {
                switch appState.activation {
                case .notActivated, .activating, .error:
                    InviteActivationView()
                case .activated:
                    MainDashboardView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingDone)
        .animation(.easeInOut(duration: 0.3), value: stateKey)
    }

    private var stateKey: String {
        switch appState.activation {
        case .notActivated:  return "notActivated"
        case .activating:    return "activating"
        case .activated:     return "activated"
        case .error:         return "error"
        }
    }
}


#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(TunnelManager())
}
