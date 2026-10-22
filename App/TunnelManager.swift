import Foundation
import NetworkExtension

@MainActor
final class TunnelManager: ObservableObject {
    @Published var status: TunnelStatus = .disconnected
    @Published var lastError: String?

    private let providerBundleIdentifier = "com.redfluent.vpn.tunnel"
    private let tunnelDescription = "RedFluent VPN"
    private var statusObserver: NSObjectProtocol?
    private var isRestarting = false
    private var attempts = StartAttemptTracker()

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let conn = note.object as? NEVPNConnection {
                Task { @MainActor in
                    let next = TunnelStatus(neStatus: conn.status)
                    self.status = next
                    switch next {
                    case .connected:
                        self.attempts.reachedConnected()
                    case .disconnected:
                        // Only an attempt this app began and that never connected can be a start
                        // failure; connected -> reasserting -> disconnected (network change,
                        // on-demand) and starts iOS triggers itself stay a plain "Disconnected".
                        if let attempt = self.attempts.attemptForDisconnect() {
                            self.reportStartFailure(conn, attempt: attempt)
                        }
                    default:
                        break
                    }
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
        // No stale errors: anything shown after this point belongs to this attempt.
        lastError = nil
        TunnelStartError.clear()
        let region = RegionStore.selectedRegion()
        do {
            // onDemand: true = iOS keeps the tunnel up (auto-reconnect on drop /
            // network change) and does not leak traffic outside it (kill-switch).
            let manager = try await loadOrCreateConfiguredManager(onDemand: true, region: region)
            attempts.begin(regionID: region.id)
            try manager.connection.startVPNTunnel()
        } catch {
            attempts.cancel()
            lastError = error.localizedDescription
            status = .failed
        }
    }

    func disconnect() async {
        status = .disconnecting
        attempts.cancel()
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

    /// Reconnect so a changed region takes effect (the extension reads its config only at start).
    func restart() async {
        guard !isRestarting else { return }
        isRestarting = true
        defer { isRestarting = false }
        status = .disconnecting
        attempts.cancel()
        do {
            // Same order as disconnect(): clear on-demand first so iOS does not bring the old
            // region back by itself, then stop and wait until the tunnel is really down.
            let manager = try await loadOrCreateConfiguredManager(onDemand: false)
            manager.connection.stopVPNTunnel()
            var waited = 0
            while waited < 50, manager.connection.status != .disconnected, manager.connection.status != .invalid {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
        } catch {
            lastError = error.localizedDescription
            status = .failed
            return
        }
        await connect()
    }

    /// The region selection changed (picker, or a reset after a /profile refresh). Connected: reconnect so
    /// it takes effect. Otherwise keep the saved tunnel configuration in step, so a start from Settings,
    /// Shortcuts or on-demand uses the region the picker shows.
    func selectedRegionChanged() async {
        // Signed out or revoked (the selection is reset then): there is no configuration to keep in step,
        // and a reconnect would start without the device token.
        guard ProfileStore.load() != nil else { return }
        if status.isConnected {
            await restart()
        } else {
            await syncSavedRegion()
        }
    }

    /// Re-save region + server address of an existing saved tunnel configuration, without starting it.
    private func syncSavedRegion() async {
        do {
            // Never configured yet: the first connect() writes it.
            guard let manager = try await loadManager() else { return }
            switch manager.connection.status {
            case .connected, .connecting, .reasserting:
                await restart()   // it is up after all: a save alone would not change the running region
                return
            default:
                break
            }
            guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return }
            let region = RegionStore.selectedRegion()
            let address = RegionPolicy.serverAddress(for: region)
            let saved = proto.providerConfiguration?["region"] as? String
            if saved == region.id, proto.serverAddress == address { return }
            proto.serverAddress = address
            proto.providerConfiguration = RegionPolicy.providerConfiguration(proto.providerConfiguration, region: region)
            manager.protocolConfiguration = proto
            try await manager.saveToPreferences()
        } catch {
            lastError = "Could not save the region: \(error.localizedDescription)"
        }
    }

    /// Show why a start attempt ended. First the extension's own message (a file in the App Group, so it
    /// does not depend on NetworkExtension status order), then whatever error iOS recorded. With neither,
    /// it stays a plain "Disconnected".
    private func reportStartFailure(_ connection: NEVPNConnection, attempt: StartAttempt) {
        Task { @MainActor [self] in
            let reason: String?
            if let fromExtension = TunnelStartError.read(since: attempt.startedAt) {
                reason = fromExtension
            } else {
                reason = await Self.lastDisconnectError(of: connection)
            }
            guard let reason, attempts.attempt == attempt else { return }   // nothing to say, or superseded
            attempts.finish()
            lastError = reason
            status = .failed
            if RegionPolicy.disablesOnDemandAfterFailure(regionID: attempt.regionID) {
                await turnOffOnDemand()
            }
        }
    }

    private static func lastDisconnectError(of connection: NEVPNConnection) async -> String? {
        await withCheckedContinuation { continuation in
            connection.fetchLastDisconnectError { error in
                continuation.resume(returning: error?.localizedDescription)
            }
        }
    }

    /// A non-default region that failed to start must not stay on on-demand, or iOS keeps retrying a
    /// start that cannot work (403 / 503). Tokyo keeps today's on-demand behaviour.
    private func turnOffOnDemand() async {
        do {
            guard let manager = try await loadManager(), manager.isOnDemandEnabled else { return }
            manager.isOnDemandEnabled = false
            manager.onDemandRules = []
            try await manager.saveToPreferences()
        } catch {
            lastError = (lastError.map { $0 + " " } ?? "") + "Could not turn off auto-reconnect: \(error.localizedDescription)"
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
    private func loadOrCreateConfiguredManager(
        onDemand: Bool,
        region: VPNRegion = RegionStore.selectedRegion()
    ) async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first ?? NETunnelProviderManager()

        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleIdentifier
        proto.serverAddress = RegionPolicy.serverAddress(for: region)
        var providerConfig: [String: Any] = ["configProfile": "review-safe-profile-v1", "region": region.id]
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
