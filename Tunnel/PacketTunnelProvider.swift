import NetworkExtension
import os.log

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "com.redfluent.vpn.tunnel", category: "PacketTunnelProvider")

    override func startTunnel(options: [String: NSObject]?) async throws {
        logger.info("Starting RedFluent packet tunnel")

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "45.32.31.229")
        settings.mtu = 1500

        let ipv4 = NEIPv4Settings(addresses: ["10.255.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: ["1.1.1.1", "1.0.0.1"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        try await setTunnelNetworkSettings(settings)

        // TODO: Integrate the chosen tunnel engine here.
        // Option A: WireGuardKit-style engine.
        // Option B: sing-box core wrapper matching the current tested server.
        logger.info("Tunnel network settings applied; engine integration pending")
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        logger.info("Stopping RedFluent packet tunnel, reason: \(reason.rawValue)")
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        logger.info("Received app message")
        return nil
    }
}
