import NetworkExtension
import os.log

/// RedFluent VPN packet tunnel.
///
/// CURRENT STATE: scaffold only. `setTunnelNetworkSettings` runs but no
/// engine is wired in, so traffic is not actually routed through the
/// configured remote. The Connect button in the host app will appear to
/// succeed but the device's external IP will not change.
///
/// NEXT STEP: integrate `Libbox.xcframework` from
/// `https://github.com/SagerNet/sing-box-for-apple`. See
/// `redfluent-vpn/docs/vpn-engine-decision.md` for the full plan.
/// The integration shape is sketched below behind `#if HAS_SINGBOX`.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    let logger = Logger(subsystem: "com.redfluent.vpn.tunnel", category: "PacketTunnelProvider")

    #if HAS_SINGBOX
    var boxService: AnyObject?  // typed as LibboxService when framework linked
    #endif

    override func startTunnel(options: [String: NSObject]?) async throws {
        logger.info("startTunnel called, options=\(String(describing: options))")

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "45.32.31.229")
        settings.mtu = 1500

        let ipv4 = NEIPv4Settings(addresses: ["10.255.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: ["1.1.1.1", "1.0.0.1"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        try await setTunnelNetworkSettings(settings)
        logger.info("Tunnel network settings applied")

        #if HAS_SINGBOX
        try await startSingBoxEngine()
        #else
        logger.warning("sing-box engine not linked; tunnel is a no-op stub")
        // Without an engine the system will treat the tunnel as connected but
        // packets entering the utun interface have nowhere to go. This is OK
        // for App Review smoke testing but obviously not for real users.
        #endif
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        logger.info("stopTunnel reason=\(reason.rawValue)")
        #if HAS_SINGBOX
        await stopSingBoxEngine()
        #endif
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        logger.info("handleAppMessage \(messageData.count) bytes")
        return nil
    }

    // MARK: - sing-box integration sketch

    #if HAS_SINGBOX
    // Pseudocode pending xcframework drop-in.
    //
    // private var boxService: LibboxService?
    //
    // private func startSingBoxEngine() async throws {
    //     let configJSON = try loadEmbeddedConfig()
    //     let platform   = LibboxPlatformInterface(provider: self)
    //     boxService     = LibboxNewService(configJSON, platform, &error)
    //     try boxService?.start()
    // }
    //
    // private func stopSingBoxEngine() async {
    //     try? boxService?.close()
    //     boxService = nil
    // }
    //
    // private func loadEmbeddedConfig() throws -> String {
    //     // Phase 1: bundle a static review-safe config JSON.
    //     // Phase 2: fetch from api.redfluent.com/profile and cache in app group.
    //     guard let url = Bundle.main.url(forResource: "review-tunnel", withExtension: "json"),
    //           let data = try? Data(contentsOf: url),
    //           let json = String(data: data, encoding: .utf8)
    //     else { throw NSError(domain: "rfv.tunnel", code: 1) }
    //     return json
    // }
    #endif
}
