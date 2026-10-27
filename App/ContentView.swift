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
                    .transition(Self.screenSwap)
            } else {
                switch appState.activation {
                case .notActivated, .activating, .error:
                    InviteActivationView()
                        .transition(Self.screenSwap)
                case .activated:
                    MainDashboardView()
                        .transition(Self.screenSwap)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingDone)
        .animation(.easeInOut(duration: 0.3), value: stateKey)
    }

    /// One screen for another: the old one goes in 150 ms, the new one fades in (its content then rises into place).
    private static let screenSwap: AnyTransition = .asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.08)),
        removal: .opacity.animation(.easeIn(duration: 0.15)))

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
