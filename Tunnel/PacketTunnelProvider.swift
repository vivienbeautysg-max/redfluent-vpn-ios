import NetworkExtension
import os.log

#if HAS_LIBBOX
import Libbox
import Network
#endif

final class PacketTunnelProvider: NEPacketTunnelProvider {
    let logger = Logger(subsystem: "com.redfluent.vpn.tunnel", category: "PacketTunnelProvider")

    #if HAS_LIBBOX
    var commandServer: LibboxCommandServer?
    private lazy var platformInterface = RedFluentPlatformInterface(provider: self)
    var networkSettings: NEPacketTunnelNetworkSettings?
    #endif

    override func startTunnel(options: [String: NSObject]?) async throws {
        logger.info("startTunnel called")

        #if HAS_LIBBOX
        try await startWithLibbox()
        #else
        try await startWithoutEngine()
        #endif
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        logger.info("stopTunnel reason=\(reason.rawValue)")
        #if HAS_LIBBOX
        try? commandServer?.close()
        commandServer = nil
        #endif
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        nil
    }

    private func startWithoutEngine() async throws {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "45.32.31.229")
        settings.mtu = 1500
        let ipv4 = NEIPv4Settings(addresses: ["10.255.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        let dns = NEDNSSettings(servers: ["1.1.1.1", "1.0.0.1"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        try await setTunnelNetworkSettings(settings)
        logger.warning("HAS_LIBBOX not set; tunnel is a no-op stub")
    }

    #if HAS_LIBBOX
    private func startWithLibbox() async throws {
        // 1. Resolve config (bundled JSON for now; future: fetch from /profile)
        let configContent = try loadConfig()

        // 2. Compute paths in extension's own sandbox container (no App Group needed)
        let containerURL = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first!
        let basePath = containerURL.path
        let workingPath = containerURL.appendingPathComponent("sing-box-working").path
        let tempPath = containerURL.appendingPathComponent("sing-box-temp").path

        try? FileManager.default.createDirectory(atPath: workingPath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: tempPath, withIntermediateDirectories: true)

        // 3. LibboxSetup (one-time global init)
        let setupOptions = LibboxSetupOptions()
        setupOptions.basePath = basePath
        setupOptions.workingPath = workingPath
        setupOptions.tempPath = tempPath
        setupOptions.logMaxLines = 3000
        setupOptions.debug = false
        setupOptions.crashReportSource = "RedFluentNetworkExtension"
        setupOptions.oomKillerEnabled = true

        var setupError: NSError?
        LibboxSetup(setupOptions, &setupError)
        if let setupError {
            throw NSError(domain: "rfv.tunnel", code: 100,
                          userInfo: [NSLocalizedDescriptionKey: "libbox setup: \(setupError.localizedDescription)"])
        }
        LibboxPromoteOOMDraft()

        // 4. Create CommandServer with our platform interface
        var serverError: NSError?
        guard let server = LibboxNewCommandServer(platformInterface, platformInterface, &serverError) else {
            throw NSError(domain: "rfv.tunnel", code: 101,
                          userInfo: [NSLocalizedDescriptionKey: "libbox new server: \(serverError?.localizedDescription ?? "?")"])
        }
        commandServer = server
        try server.start()
        logger.info("CommandServer started")

        // 5. Start the actual sing-box service with our config
        let overrideOptions = LibboxOverrideOptions()
        try server.startOrReloadService(configContent, options: overrideOptions)
        logger.info("sing-box service started")
    }

    private func loadConfig() throws -> String {
        if let url = Bundle.main.url(forResource: "review-tunnel", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        throw NSError(domain: "rfv.tunnel", code: 200,
                      userInfo: [NSLocalizedDescriptionKey: "review-tunnel.json not bundled in extension"])
    }
    #endif
}

#if HAS_LIBBOX

// MARK: - Platform Interface Bridge

final class RedFluentPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    private weak var provider: PacketTunnelProvider?
    private let logger = Logger(subsystem: "com.redfluent.vpn.tunnel", category: "PlatformInterface")
    private var nwMonitor: NWPathMonitor?

    init(provider: PacketTunnelProvider) {
        self.provider = provider
        super.init()
    }

    // MARK: openTun — bridges sing-box's tun fd to NEPacketTunnelProvider's packetFlow

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        try runBlocking { [self] in
            try await openTun0(options, ret0_)
        }
    }

    private func openTun0(_ options: LibboxTunOptionsProtocol?, _ ret0_: UnsafeMutablePointer<Int32>?) async throws {
        guard let options, let ret0_, let provider else {
            throw NSError(domain: "rfv.platform", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing args"])
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: options.getMTU())

        // DNS
        let dnsServer = try options.getDNSServerAddress()
        let dns = NEDNSSettings(servers: [dnsServer.value])
        dns.matchDomains = [""]
        dns.matchDomainsNoSearch = false
        settings.dnsSettings = dns

        // IPv4
        var ipv4Addresses: [String] = []
        var ipv4Masks: [String] = []
        if let it = options.getInet4Address() {
            while it.hasNext() {
                if let prefix = it.next() {
                    ipv4Addresses.append(prefix.address())
                    ipv4Masks.append(prefix.mask())
                }
            }
        }
        if !ipv4Addresses.isEmpty {
            let ipv4 = NEIPv4Settings(addresses: ipv4Addresses, subnetMasks: ipv4Masks)
            var routes: [NEIPv4Route] = []
            if let it = options.getInet4RouteAddress() {
                while it.hasNext() {
                    if let p = it.next() {
                        routes.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask()))
                    }
                }
            }
            ipv4.includedRoutes = routes.isEmpty ? [NEIPv4Route.default()] : routes
            var excludes: [NEIPv4Route] = []
            if let it = options.getInet4RouteExcludeAddress() {
                while it.hasNext() {
                    if let p = it.next() {
                        excludes.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask()))
                    }
                }
            }
            ipv4.excludedRoutes = excludes
            settings.ipv4Settings = ipv4
        }

        // IPv6
        var ipv6Addresses: [String] = []
        var ipv6Prefixes: [NSNumber] = []
        if let it = options.getInet6Address() {
            while it.hasNext() {
                if let prefix = it.next() {
                    ipv6Addresses.append(prefix.address())
                    ipv6Prefixes.append(NSNumber(value: prefix.prefix()))
                }
            }
        }
        if !ipv6Addresses.isEmpty {
            let ipv6 = NEIPv6Settings(addresses: ipv6Addresses, networkPrefixLengths: ipv6Prefixes)
            var routes: [NEIPv6Route] = []
            if let it = options.getInet6RouteAddress() {
                while it.hasNext() {
                    if let p = it.next() {
                        routes.append(NEIPv6Route(destinationAddress: p.address(),
                                                  networkPrefixLength: NSNumber(value: p.prefix())))
                    }
                }
            }
            ipv6.includedRoutes = routes.isEmpty ? [NEIPv6Route.default()] : routes
            settings.ipv6Settings = ipv6
        }

        try await provider.setTunnelNetworkSettings(settings)
        provider.networkSettings = settings

        // Get the tun fd via KVC trick (NEPacketTunnelProvider exposes it under "socket.fileDescriptor")
        if let tunFd = provider.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = tunFd
            return
        }
        let fd = LibboxGetTunnelFileDescriptor()
        if fd != -1 {
            ret0_.pointee = fd
            return
        }
        throw NSError(domain: "rfv.platform", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "could not obtain tun fd"])
    }

    // MARK: Other LibboxPlatformInterface methods

    func usePlatformAutoDetectControl() -> Bool { false }
    func autoDetectControl(_ fd: Int32) throws { }
    func useProcFS() -> Bool { false }

    func findConnectionOwner(_ ipProtocol: Int32,
                             sourceAddress: String?,
                             sourcePort: Int32,
                             destinationAddress: String?,
                             destinationPort: Int32) throws -> LibboxConnectionOwner {
        throw NSError(domain: "rfv.platform", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "findConnectionOwner not implemented on iOS"])
    }

    func writeLog(_ message: String?) {
        if let message {
            logger.info("singbox: \(message, privacy: .public)")
        }
    }

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        nwMonitor = monitor
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            self.notifyInterface(listener, path)
            semaphore.signal()
            monitor.pathUpdateHandler = { path in
                self.notifyInterface(listener, path)
            }
        }
        monitor.start(queue: DispatchQueue.global())
        semaphore.wait()
    }

    private func notifyInterface(_ listener: LibboxInterfaceUpdateListenerProtocol, _ path: Network.NWPath) {
        if path.status == .unsatisfied || path.availableInterfaces.isEmpty {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        let iface = path.availableInterfaces[0]
        listener.updateDefaultInterface(iface.name,
                                        interfaceIndex: Int32(iface.index),
                                        isExpensive: path.isExpensive,
                                        isConstrained: path.isConstrained)
    }

    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        nwMonitor?.cancel()
        nwMonitor = nil
    }

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let nwMonitor else {
            return InterfaceIterator(interfaces: [])
        }
        let path = nwMonitor.currentPath
        if path.status == .unsatisfied {
            return InterfaceIterator(interfaces: [])
        }
        var ifaces: [LibboxNetworkInterface] = []
        for it in path.availableInterfaces {
            let iface = LibboxNetworkInterface()
            iface.name = it.name
            iface.index = Int32(it.index)
            switch it.type {
            case .wifi:          iface.type = LibboxInterfaceTypeWIFI
            case .cellular:      iface.type = LibboxInterfaceTypeCellular
            case .wiredEthernet: iface.type = LibboxInterfaceTypeEthernet
            default:             iface.type = LibboxInterfaceTypeOther
            }
            ifaces.append(iface)
        }
        return InterfaceIterator(interfaces: ifaces)
    }

    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }

    func clearDNSCache() {
        guard let provider, let settings = provider.networkSettings else { return }
        runBlocking {
            provider.reasserting = true
            defer { provider.reasserting = false }
            await withCheckedContinuation { c in
                provider.setTunnelNetworkSettings(nil) { _ in c.resume() }
            }
            await withCheckedContinuation { c in
                provider.setTunnelNetworkSettings(settings) { _ in c.resume() }
            }
        }
    }

    func readWIFIState() -> LibboxWIFIState? {
        let network = runBlocking {
            await NEHotspotNetwork.fetchCurrent()
        }
        guard let network else { return nil }
        return LibboxWIFIState(network.ssid, wifiBSSID: network.bssid)
    }

    func readWIFISSID() -> String? {
        runBlocking { await NEHotspotNetwork.fetchCurrent()?.ssid }
    }

    // MARK: LibboxCommandServerHandler — minimum viable safe defaults

    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        let status = LibboxSystemProxyStatus()
        status.available = false
        status.enabled = false
        return status
    }

    func setSystemProxyEnabled(_ enabled: Bool) throws { }
    func serviceReload() throws { }
    func serviceStop() throws { }
    func triggerNativeCrash() throws {
        fatalError("triggerNativeCrash invoked")
    }
    func writeDebugMessage(_ message: String?) {
        if let message {
            logger.debug("debug: \(message, privacy: .public)")
        }
    }
}

// MARK: - LibboxNetworkInterfaceIterator implementation

private final class InterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    private var iterator: IndexingIterator<[LibboxNetworkInterface]>
    private var current: LibboxNetworkInterface?

    init(interfaces: [LibboxNetworkInterface]) {
        self.iterator = interfaces.makeIterator()
    }

    func hasNext() -> Bool {
        current = iterator.next()
        return current != nil
    }

    func next() -> LibboxNetworkInterface? { current }
}

// MARK: - runBlocking helper (sync from async)

func runBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>!
    Task.detached {
        do {
            let value = try await operation()
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try result.get()
}

func runBlocking<T>(_ operation: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: T!
    Task.detached {
        result = await operation()
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

#endif
