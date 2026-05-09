// Real sing-box integration. Compiles only when Libbox.xcframework is linked
// (set HAS_SINGBOX in OTHER_SWIFT_FLAGS or via project.yml's
// `swiftCompilerFlags: ["-D", "HAS_SINGBOX"]` once the framework is in place).
//
// To enable:
//   1. Build Libbox.xcframework via sing-box-for-apple's ./libbox.sh
//   2. Drop into Frameworks/Libbox.xcframework
//   3. Add framework dependency to RedFluentVPNTunnel target in project.yml:
//        dependencies:
//          - framework: Frameworks/Libbox.xcframework
//            embed: true
//        settings:
//          base:
//            OTHER_SWIFT_FLAGS: -DHAS_SINGBOX
//   4. xcodegen generate
//   5. Re-archive
//
// The libbox API used here is documented in sing-box-for-apple's
// PacketTunnelProvider.swift; the symbols come from the Libbox golang
// module wrapped by gomobile bind.

#if HAS_SINGBOX
import Foundation
import NetworkExtension
import os.log
import Libbox

extension PacketTunnelProvider {

    func startSingBoxEngine() async throws {
        let configJSON = try loadConfig()
        let platform = RedFluentPlatform(provider: self)

        var error: NSError?
        guard let service = LibboxNewService(configJSON, platform, &error) else {
            throw error ?? NSError(domain: "rfv.tunnel", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "libbox failed to create service"])
        }
        boxService = service
        try service.start()
    }

    func stopSingBoxEngine() async {
        try? boxService?.close()
        boxService = nil
    }

    private func loadConfig() throws -> String {
        // Phase 1: bundled review-safe profile JSON
        if let url = Bundle.main.url(forResource: "review-tunnel", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        // Phase 2: fetched from /profile and cached in app group
        if let cached = try? readGroupContainer("active-profile.json"),
           let json = String(data: cached, encoding: .utf8) {
            return json
        }
        throw NSError(domain: "rfv.tunnel", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "no tunnel config available"])
    }

    private func readGroupContainer(_ filename: String) throws -> Data {
        let groupID = "group.com.redfluent.vpn"
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(filename) else {
            throw NSError(domain: "rfv.tunnel", code: 3)
        }
        return try Data(contentsOf: url)
    }
}

/// Bridges libbox's PlatformInterface protocol to NEPacketTunnelProvider.
final class RedFluentPlatform: NSObject, LibboxPlatformInterfaceProtocol {
    private weak var provider: PacketTunnelProvider?
    private let logger = Logger(subsystem: "com.redfluent.vpn.tunnel", category: "Platform")

    init(provider: PacketTunnelProvider) {
        self.provider = provider
        super.init()
    }

    func usePlatformAutoDetectInterfaceControl() -> Bool { true }
    func autoDetectControl(_ fd: Int32) throws { /* iOS handles this */ }
    func usePlatformDefaultInterfaceMonitor() -> Bool { true }
    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws { }
    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws { }
    func usePlatformInterfaceGetter() -> Bool { false }
    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        throw NSError(domain: "rfv.tunnel", code: 100, userInfo: nil)
    }
    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }
    func clearDNSCache() { }

    func writeLog(_ message: String?) {
        if let message { logger.debug("singbox: \(message, privacy: .public)") }
    }

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: AutoreleasingUnsafeMutablePointer<NSNumber?>?) throws {
        // sing-box wants the raw tun fd. iOS NEPacketTunnelProvider gives us
        // a packetFlow instead; we configure NE network settings here from
        // libbox's options and let NE handle the rest.
        guard let provider, let opts = options else { throw NSError(domain: "rfv.tunnel", code: 101) }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: opts.getInet4Address() ?? "10.0.0.1")
        settings.mtu = NSNumber(value: opts.getMTU())

        if let v4 = opts.getInet4Address(), !v4.isEmpty {
            let ipv4 = NEIPv4Settings(addresses: [v4], subnetMasks: ["255.255.255.0"])
            ipv4.includedRoutes = [NEIPv4Route.default()]
            settings.ipv4Settings = ipv4
        }

        if let dns = opts.getDNSServerAddress(), !dns.isEmpty {
            let dnsSettings = NEDNSSettings(servers: [dns])
            dnsSettings.matchDomains = [""]
            settings.dnsSettings = dnsSettings
        }

        Task {
            try await provider.setTunnelNetworkSettings(settings)
        }
        ret0_?.pointee = NSNumber(value: -1) // we don't pass back a real fd; libbox's iOS path handles via packetFlow
    }
}
#endif
