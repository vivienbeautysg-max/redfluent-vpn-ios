import Foundation
import NetworkExtension

@MainActor
final class TunnelManager: ObservableObject {
    @Published var status: TunnelStatus = .disconnected
    @Published var lastError: String?

    private let providerBundleIdentifier = "com.redfluent.vpn.tunnel"
    private let tunnelDescription = "RedFluent VPN"
    private var statusObserver: NSObjectProtocol?

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let conn = note.object as? NEVPNConnection {
                Task { @MainActor in
                    self.status = TunnelStatus(neStatus: conn.status)
                }
            }
        }
    }

    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func loadStatus() async {
        do {
            // Read-only: do NOT re-save preferences just to check status
            // (saving re-prompts the iOS VPN permission sheet and churns config).
            if let manager = try await loadManager() {
                status = TunnelStatus(neStatus: manager.connection.status)
            } else {
                status = .disconnected
            }
        } catch {
            lastError = error.localizedDescription
            status = .failed
        }
    }

    func toggle() async {
        if status.isConnected {
            await disconnect()
        } else {
            await connect()
        }
    }

    func connect() async {
        status = .connecting
        do {
            // onDemand: true = iOS keeps the tunnel up (auto-reconnect on drop /
            // network change) and does not leak traffic outside it (kill-switch).
            let manager = try await loadOrCreateConfiguredManager(onDemand: true)
            try manager.connection.startVPNTunnel()
        } catch {
            lastError = error.localizedDescription
            status = .failed
        }
    }

    func disconnect() async {
        status = .disconnecting
        do {
            // Clear on-demand FIRST so iOS doesn't immediately re-establish the
            // tunnel, then stop it. Without this the user can't actually turn it off.
            let manager = try await loadOrCreateConfiguredManager(onDemand: false)
            manager.connection.stopVPNTunnel()
        } catch {
            lastError = error.localizedDescription
            status = .failed
        }
    }

    /// Read-only load of the existing tunnel manager (no save). Returns nil if
    /// the user has never configured the tunnel yet.
    private func loadManager() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first
    }

    /// Load-or-create the tunnel manager, apply our configuration, set the
    /// on-demand (kill-switch / auto-reconnect) state, and persist. Only called
    /// from connect()/disconnect() — never from a plain status read.
    private func loadOrCreateConfiguredManager(onDemand: Bool) async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first ?? NETunnelProviderManager()

        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleIdentifier
        proto.serverAddress = "RedFluent Tokyo"
        var providerConfig: [String: Any] = ["configProfile": "review-safe-profile-v1"]
        // Pass the device token + API base so the tunnel extension can fetch a
        // per-device sing-box config (its own uuid) from the backend. The
        // extension falls back to the bundled config if this is absent or fails.
        if let profile = ProfileStore.load() {
            providerConfig["token"] = profile.token
            providerConfig["apiBase"] = "https://vpn-api.redfluent.com"
        }
        proto.providerConfiguration = providerConfig
        proto.disconnectOnSleep = false

        manager.localizedDescription = tunnelDescription
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        // Kill-switch + auto-reconnect: while the user wants the VPN on, mark it
        // on-demand so iOS re-establishes it on drop/network-change and blocks
        // traffic from leaking outside the tunnel. Cleared on explicit disconnect.
        manager.isOnDemandEnabled = onDemand
        manager.onDemandRules = onDemand ? [NEOnDemandRuleConnect()] : []

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        return manager
    }
}

enum TunnelStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed

    init(neStatus: NEVPNStatus) {
        switch neStatus {
        case .connected:                  self = .connected
        case .connecting, .reasserting:   self = .connecting
        case .disconnecting:              self = .disconnecting
        case .disconnected, .invalid:     self = .disconnected
        @unknown default:                 self = .failed
        }
    }

    var isConnected: Bool { self == .connected || self == .connecting }

    var displayName: String {
        switch self {
        case .disconnected:  return "Disconnected"
        case .connecting:    return "Connecting"
        case .connected:     return "Connected"
        case .disconnecting: return "Disconnecting"
        case .failed:        return "Needs attention"
        }
    }

    var detail: String {
        switch self {
        case .disconnected:  return "Tap Connect to start the secure tunnel."
        case .connecting:    return "Establishing the encrypted tunnel."
        case .connected:     return "Your device is using the RedFluent secure tunnel."
        case .disconnecting: return "Closing the tunnel."
        case .failed:        return "Open Diagnostics for details."
        }
    }
}
