import Foundation
import Network

/// Watches the Wi-Fi path only (NWPathMonitor scoped to .wifi), so a running VPN tunnel does not hide what the
/// Wi-Fi itself offers: is it up, and can it route IPv6? Feeds IPv6Hint on the home screen.
@MainActor
final class WiFiPathWatcher: ObservableObject {
    @Published private(set) var onWiFi = false
    @Published private(set) var wifiHasIPv6 = true

    private var monitor: NWPathMonitor?

    func start() {
        #if DEBUG
        if ScreenshotMode.isOn {
            // Screenshots: fixed state, no real network reads.
            onWiFi = ScreenshotMode.ipv4OnlyWiFi
            wifiHasIPv6 = !ScreenshotMode.ipv4OnlyWiFi
            return
        }
        #endif
        guard monitor == nil else { return }
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            let v6 = path.supportsIPv6
            Task { @MainActor in
                self?.onWiFi = up
                self?.wifiHasIPv6 = v6
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.redfluent.vpn.wifi-path"))
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
