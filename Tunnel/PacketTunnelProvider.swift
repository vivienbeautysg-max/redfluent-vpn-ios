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
    private var statsPoller: ClashStatsPoller?
    // Region follow (see startFollowing)
    private let followLock = NSLock()
    private var followTask: Task<Void, Never>?
    private var pathDebounceTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var lastPath: FollowPolicy.PathSignature?
    private var lastFollowCheckAt = Date.distantPast
    /// The region the running engine was configured for.
    private var activeRegionID = RuntimeConfigRequest.defaultRegion
    #endif

    // Clash API endpoint injected into the sing-box config at boot.
    private static let clashAPIController = "127.0.0.1:9090"

    #if HAS_LIBBOX
    // Per-process random secret for the loopback clash API. Defense-in-depth:
    // even though the API only binds to 127.0.0.1, we still require a Bearer
    // token so any other process on the device cannot poll our stats.
    private let clashSecret = UUID().uuidString
    #endif

    override func startTunnel(options: [String: NSObject]?) async throws {
        logger.info("startTunnel called")
        SharedContainer.clearActiveRegion()
        // The server ended this device's access (expired / revoked) and the app has not cleared that yet:
        // refuse starts nobody asked for (on-demand, Settings) without even fetching.
        if let stop = SharedContainer.readStopReason() {
            throw NSError(domain: "rfv.tunnel", code: stop == .expired ? 403 : 401,
                          userInfo: [NSLocalizedDescriptionKey: stop.message])
        }
        SharedContainer.clearStartError()

        do {
            #if HAS_LIBBOX
            try await startWithLibbox()
            #else
            try await startWithoutEngine()
            #endif
        } catch {
            // Hand the reason to the app through a file before iOS tears the extension down.
            SharedContainer.writeStartError(error.localizedDescription)
            throw error
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        logger.info("stopTunnel reason=\(reason.rawValue)")
        SharedContainer.clearActiveRegion()
        #if HAS_LIBBOX
        await stopFollowing()
        if let poller = statsPoller {
            await poller.stop()
        }
        statsPoller = nil
        try? commandServer?.close()
        commandServer = nil
        #endif
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        nil
    }

    private func startWithoutEngine() async throws {
        // No real engine linked — fail loudly instead of bringing up a tunnel
        // that captures traffic but routes nothing (a fake "Connected" with no
        // internet). Production builds always define HAS_LIBBOX.
        logger.error("HAS_LIBBOX not set — refusing to start a no-op tunnel")
        throw NSError(domain: "rfv.tunnel", code: 500,
                      userInfo: [NSLocalizedDescriptionKey: "VPN engine not linked; cannot start tunnel."])
    }

    #if HAS_LIBBOX
    private func startWithLibbox() async throws {
        // 1. Resolve config — per-device from backend, else bundled fallback.
        let configContent = try await loadConfig()

        // 2. Compute paths in extension's own sandbox container (no App Group needed)
        guard let containerURL = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "rfv.tunnel", code: 103,
                          userInfo: [NSLocalizedDescriptionKey: "no library directory in container"])
        }
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
        setupOptions.logMaxLines = 500
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

        // 6. Write an immediate "connected" snapshot so the UI reflects state
        //    without waiting for the first poll tick (~2s later).
        let bootedAt = Date()
        let bootSnap = StatsSnapshot(
            timestamp: bootedAt,
            connected: true,
            connectionStartedAt: bootedAt
        )
        SharedContainer.writeStats(bootSnap)

        // 7. Kick off the clash API poller. The actor serializes start/stop
        //    against any in-flight tick. Pass the boot timestamp so the
        //    duration timer never resets backwards on the first tick.
        let poller = ClashStatsPoller()
        statsPoller = poller
        let secret = clashSecret
        Task {
            await poller.start(bootedAt: bootedAt, secret: secret)
        }

        // 8. Follow the server's region assignment / expiry while connected.
        startFollowing()
    }

    private func loadConfig() async throws -> String {
        // Prefer a per-device config from the backend (carries this device's own
        // uuid, so revoking it server-side actually cuts the tunnel). Fall back
        // to the bundled shared config on ANY failure so the tunnel still comes up.
        // Exceptions: an expired invite never connects, and a non-default region never falls back
        // (the bundled config is Tokyo; connecting there while the app says Singapore would be a lie).
        let region = requestedRegion
        let fetched = await fetchPerDeviceConfigData(region: region, serverDecides: serverDecidesRegion)
        if let perDevice = fetched.data {
            let active = fetched.echoedRegion ?? region
            activeRegionID = active
            SharedContainer.writeActiveRegion(id: active, name: fetched.serverRegion ?? active.capitalized)
            return try injectClashAPI(into: perDevice)
        }
        if FollowPolicy.blocksStart(fetched.outcome) {
            throw NSError(domain: "rfv.tunnel", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: StopKind.expired.message])
        }
        guard RuntimeConfigRequest.isDefault(region: region) else {
            throw NSError(domain: "rfv.tunnel", code: 210,
                          userInfo: [NSLocalizedDescriptionKey: RuntimeConfigRequest.failureMessage(
                              region: region, detail: fetched.failure ?? "no response")])
        }
        logger.warning("falling back to the bundled Tokyo config: \(fetched.failure ?? "no response", privacy: .public)")
        guard let url = Bundle.main.url(forResource: "review-tunnel", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw NSError(domain: "rfv.tunnel", code: 200,
                          userInfo: [NSLocalizedDescriptionKey: "review-tunnel.json not bundled in extension"])
        }
        activeRegionID = RuntimeConfigRequest.defaultRegion
        SharedContainer.writeActiveRegion(id: activeRegionID, name: "Tokyo")
        return try injectClashAPI(into: data)
    }

    /// The region the app asked for in providerConfiguration; missing means the default (Tokyo).
    private var requestedRegion: String {
        let cfg = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        guard let region = cfg?["region"] as? String, !region.isEmpty else {
            return RuntimeConfigRequest.defaultRegion
        }
        return region
    }

    /// Everyone but the owner: the app says "server" and the request carries no region parameter, so the
    /// server decides which region this account gets. A configuration saved by an older app has no mode
    /// and keeps sending the region explicitly.
    private var serverDecidesRegion: Bool {
        let cfg = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        return (cfg?["regionMode"] as? String) == "server"
    }

    private struct RuntimeConfigFetch {
        var data: Data?
        var serverRegion: String?
        /// The region the server says it answered with.
        var echoedRegion: String?
        var outcome: RuntimeConfigOutcome
        var failure: String?
    }

    /// Fetch this device's sing-box config from the backend, using the token the app passed via
    /// providerConfiguration. On any failure `data` is nil and `outcome` / `failure` say why, so the caller
    /// can fall back to the bundled config (default region only) or react to expiry.
    private func fetchPerDeviceConfigData(region: String, serverDecides: Bool) async -> RuntimeConfigFetch {
        let cfg = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        guard let token = cfg?["token"] as? String,
              let base = cfg?["apiBase"] as? String,
              let url = RuntimeConfigRequest.url(
                base: base,
                region: RuntimeConfigRequest.regionParameter(region: region, serverDecides: serverDecides)) else {
            return RuntimeConfigFetch(outcome: .network, failure: "device not activated")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return RuntimeConfigFetch(outcome: .network, failure: "no HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                let reason = RuntimeConfigRequest.serverReason(from: data)
                return RuntimeConfigFetch(outcome: .http(status: http.statusCode, error: reason),
                                          failure: "HTTP \(http.statusCode)" + (reason.map { ": \($0)" } ?? ""))
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["ok"] as? Bool == true,
                  let rc = obj["runtimeConfig"] else {
                return RuntimeConfigFetch(outcome: .http(status: http.statusCode, error: nil), failure: "unexpected response")
            }
            // A region asked for by name must be confirmed: a backend that predates regions ignores
            // ?region= and answers with the Tokyo config.
            if !serverDecides, !RuntimeConfigRequest.isDefault(region: region),
               !RuntimeConfigRequest.confirms(region: region, in: obj) {
                return RuntimeConfigFetch(outcome: .http(status: http.statusCode, error: "region not confirmed"),
                                          failure: "server did not confirm the region")
            }
            logger.info("using per-device config from backend")
            let echoed = obj["region"] as? String
            return RuntimeConfigFetch(data: try JSONSerialization.data(withJSONObject: rc),
                                      serverRegion: obj["serverRegion"] as? String,
                                      echoedRegion: echoed,
                                      outcome: .config(region: echoed))
        } catch {
            logger.warning("per-device config fetch failed: \(error.localizedDescription, privacy: .public)")
            return RuntimeConfigFetch(outcome: .network, failure: error.localizedDescription)
        }
    }

    // MARK: - Region follow

    /// While connected: one timer (every 5 minutes) plus a debounced network-change check. Both only sleep
    /// or wait for events, so nothing runs between checks.
    private func startFollowing() {
        let timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(FollowPolicy.interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await self.followCheck(reason: "timer")
            }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in self?.followPathChanged(path) }
        monitor.start(queue: DispatchQueue(label: "com.redfluent.vpn.tunnel.follow-path"))
        followLock.lock()
        followTask = timer
        pathMonitor = monitor
        followLock.unlock()
    }

    private func followPathChanged(_ path: Network.NWPath) {
        let current = FollowPolicy.PathSignature(
            satisfied: path.status == .satisfied,
            interfaces: path.availableInterfaces.map(\.name).sorted())
        followLock.lock()
        defer { followLock.unlock() }
        let previous = lastPath
        lastPath = current
        guard FollowPolicy.pathChangeWarrantsCheck(previous: previous, current: current) else { return }
        pathDebounceTask?.cancel()
        pathDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(FollowPolicy.pathDebounce * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.followCheck(reason: "network change")
        }
    }

    /// Ends the follower, and waits for a check or engine reload still in flight so the engine is never
    /// closed underneath it.
    private func stopFollowing() async {
        let (tasks, monitor): ([Task<Void, Never>], NWPathMonitor?) = followLock.withLock {
            let tasks = [followTask, pathDebounceTask].compactMap { $0 }
            let monitor = pathMonitor
            followTask = nil
            pathDebounceTask = nil
            pathMonitor = nil
            lastPath = nil
            return (tasks, monitor)
        }
        monitor?.cancel()
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
    }

    private func followCheck(reason: String) async {
        let tooSoon: Bool = followLock.withLock {
            let now = Date()
            let soon = now.timeIntervalSince(lastFollowCheckAt) < FollowPolicy.minGap
            if !soon { lastFollowCheckAt = now }
            return soon
        }
        guard !tooSoon, commandServer != nil else { return }

        let fetched = await fetchPerDeviceConfigData(region: requestedRegion, serverDecides: serverDecidesRegion)
        guard !Task.isCancelled, commandServer != nil else { return }
        switch FollowPolicy.decide(active: activeRegionID, outcome: fetched.outcome) {
        case .keep:
            logger.info("region follow (\(reason, privacy: .public)): kept; \(fetched.failure ?? "no change", privacy: .public)")
        case .reload(let region):
            reloadEngine(fetched, region: region)
        case .stop(let kind):
            stopForServer(kind)
        }
    }

    /// The server now assigns another region: restart the sing-box service with the new config. The tunnel
    /// itself stays up (same path the official client takes to reload a profile).
    private func reloadEngine(_ fetched: RuntimeConfigFetch, region: String) {
        guard let data = fetched.data, let server = commandServer else { return }
        do {
            let content = try injectClashAPI(into: data)
            reasserting = true
            defer { reasserting = false }
            try server.startOrReloadService(content, options: LibboxOverrideOptions())
            activeRegionID = region
            SharedContainer.writeActiveRegion(id: region, name: fetched.serverRegion ?? region.capitalized)
            logger.info("region follow: engine reloaded for \(region, privacy: .public)")
        } catch {
            // The old engine is gone and the new one did not start: stop visibly instead of limping.
            let message = "Could not switch region: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            SharedContainer.writeStartError(message)
            cancelTunnelWithError(NSError(domain: "rfv.tunnel", code: 220,
                                          userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }

    /// Expired / revoked: leave the reason for the app (which asks /profile and shows Expired / Revoked)
    /// and stop the tunnel.
    private func stopForServer(_ kind: StopKind) {
        logger.warning("region follow: server says \(kind.rawValue, privacy: .public); stopping the tunnel")
        SharedContainer.writeStopReason(kind)
        cancelTunnelWithError(NSError(domain: "rfv.tunnel", code: kind == .expired ? 403 : 401,
                                      userInfo: [NSLocalizedDescriptionKey: kind.message]))
    }

    /// Parse the bundled config JSON, ensure `experimental.clash_api` exists
    /// with our external_controller address, and re-serialise.
    ///
    /// We always force the controller to match the poller; bundled configs
    /// cannot override this (otherwise a stale port in the bundled JSON
    /// would silently break stats polling). Idempotency is preserved —
    /// re-setting the same value is a no-op.
    private func injectClashAPI(into data: Data) throws -> String {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "rfv.tunnel", code: 201,
                          userInfo: [NSLocalizedDescriptionKey: "review-tunnel.json: root is not an object"])
        }

        var experimental = (root["experimental"] as? [String: Any]) ?? [:]
        var clashAPI = (experimental["clash_api"] as? [String: Any]) ?? [:]

        // Unconditional overwrite — the poller is hardcoded to talk to this
        // address; any mismatch in the bundled config would silently break it.
        clashAPI["external_controller"] = Self.clashAPIController
        // Defense-in-depth: require a Bearer secret on the loopback API.
        clashAPI["secret"] = self.clashSecret
        if clashAPI["store_selected"] == nil {
            clashAPI["store_selected"] = false
        }

        experimental["clash_api"] = clashAPI
        root["experimental"] = experimental

        let mutated = try JSONSerialization.data(withJSONObject: root, options: [])
        guard let json = String(data: mutated, encoding: .utf8) else {
            throw NSError(domain: "rfv.tunnel", code: 202,
                          userInfo: [NSLocalizedDescriptionKey: "could not stringify mutated config"])
        }
        return json
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
        var dnsServers: [String] = []
        let dnsIter = try options.getDNSServerAddress()
        while dnsIter.hasNext() {
            dnsServers.append(dnsIter.next())
        }
        if !dnsServers.isEmpty {
            let dns = NEDNSSettings(servers: dnsServers)
            dns.matchDomains = [""]
            dns.matchDomainsNoSearch = false
            settings.dnsSettings = dns
        }

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

    // Newer libbox API additions — all safe defaults

    func startNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws { }
    func closeNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws { }

    func localDNSTransport() -> LibboxLocalDNSTransportProtocol? { nil }

    func systemCertificates() -> LibboxStringIteratorProtocol? { nil }

    func registerMyInterface(_ name: String?) { }

    func send(_ notification: LibboxNotification?) throws { }

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
