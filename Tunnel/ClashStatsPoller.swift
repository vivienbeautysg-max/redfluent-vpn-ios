import Foundation
import os.log

/// Polls sing-box's clash-compatible REST API (running inside the extension
/// at 127.0.0.1:9090) every ~2 seconds and writes a `StatsSnapshot` into the
/// shared App Group container.
///
/// Intentionally framework-clean (no Libbox dependency) so it can be unit-
/// tested or reused in other targets.
final class ClashStatsPoller {

    // MARK: Configuration

    private let host: String
    private let port: Int
    private let interval: TimeInterval
    private let session: URLSession
    private let logger = Logger(subsystem: "com.redfluent.vpn.tunnel", category: "ClashStatsPoller")

    // MARK: State

    private var task: Task<Void, Never>?
    private var connectionStartedAt: Date?

    // MARK: Init

    init(host: String = "127.0.0.1",
         port: Int = 9090,
         interval: TimeInterval = 2.0) {
        self.host = host
        self.port = port
        self.interval = interval

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1.0
        cfg.timeoutIntervalForResource = 1.0
        cfg.waitsForConnectivity = false
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: cfg)
    }

    // MARK: Lifecycle

    func start() {
        guard task == nil else { return }
        logger.info("ClashStatsPoller starting (every \(self.interval, privacy: .public)s)")

        let intervalNs = UInt64(interval * 1_000_000_000)
        task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: intervalNs)
            }
        }
    }

    func stop() {
        logger.info("ClashStatsPoller stopping")
        task?.cancel()
        task = nil

        // Write a final "disconnected" snapshot so the UI can react promptly.
        let snap = StatsSnapshot(
            timestamp: Date(),
            connected: false,
            connectionStartedAt: nil,
            pingMs: nil
        )
        SharedContainer.writeStats(snap)
        connectionStartedAt = nil
    }

    // MARK: Polling

    private func tick() async {
        // Fetch traffic + connections concurrently. Either may fail (e.g. clash
        // API isn't up yet); we degrade gracefully.
        async let trafficResult: TrafficPayload? = fetch(path: "/traffic")
        async let connectionsResult: ConnectionsPayload? = fetch(path: "/connections")

        let traffic = await trafficResult
        let connections = await connectionsResult

        // If neither responded, the API is probably not ready yet — silently
        // skip this tick (no crash, no log spam).
        guard traffic != nil || connections != nil else { return }

        if connectionStartedAt == nil {
            connectionStartedAt = Date()
        }

        var proxy = 0
        var direct = 0
        if let conns = connections?.connections {
            for c in conns {
                let chains = c.chains ?? []
                let lower = chains.map { $0.lowercased() }
                if lower.contains("direct") {
                    direct += 1
                } else {
                    // Default to "proxy" — anything routed through a non-direct
                    // chain counts as proxied. This matches Clash dashboard UX.
                    proxy += 1
                }
            }
        }

        let snap = StatsSnapshot(
            timestamp: Date(),
            connected: true,
            connectionStartedAt: connectionStartedAt,
            uplinkBps: traffic?.up ?? 0,
            downlinkBps: traffic?.down ?? 0,
            totalUp: connections?.uploadTotal ?? 0,
            totalDown: connections?.downloadTotal ?? 0,
            activeConnections: connections?.connections?.count ?? 0,
            proxyConnections: proxy,
            directConnections: direct,
            pingMs: nil // populated by future latency probe
        )
        SharedContainer.writeStats(snap)
    }

    // MARK: HTTP

    private func fetch<T: Decodable>(path: String) async -> T? {
        guard let url = URL(string: "http://\(host):\(port)\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Connection refused / timeout / decode error — all expected during
            // boot races. Stay quiet to avoid log spam.
            return nil
        }
    }

    // MARK: Wire types
    //
    // We intentionally model only the fields we need and mark everything
    // optional so a schema drift in upstream sing-box doesn't crash the poller.

    private struct TrafficPayload: Decodable {
        let up: Int?
        let down: Int?
    }

    private struct ConnectionsPayload: Decodable {
        let connections: [ConnectionEntry]?
        let uploadTotal: Int?
        let downloadTotal: Int?
    }

    private struct ConnectionEntry: Decodable {
        let chains: [String]?
        let metadata: ConnectionMetadata?
    }

    private struct ConnectionMetadata: Decodable {
        let network: String?
        let destinationIP: String?
    }
}
