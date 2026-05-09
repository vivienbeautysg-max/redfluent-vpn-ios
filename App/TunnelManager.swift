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
            let manager = try await loadOrCreateManager()
            status = TunnelStatus(neStatus: manager.connection.status)
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
            let manager = try await loadOrCreateManager()
            try manager.connection.startVPNTunnel()
        } catch {
            lastError = error.localizedDescription
            status = .failed
        }
    }

    func disconnect() async {
        status = .disconnecting
        do {
            let manager = try await loadOrCreateManager()
            manager.connection.stopVPNTunnel()
        } catch {
            lastError = error.localizedDescription
            status = .failed
        }
    }

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first ?? NETunnelProviderManager()

        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleIdentifier
        proto.serverAddress = "RedFluent Tokyo"
        proto.providerConfiguration = [
            "configProfile": "review-safe-profile-v1"
        ]
        proto.disconnectOnSleep = false

        manager.localizedDescription = tunnelDescription
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        manager.isOnDemandEnabled = false

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
