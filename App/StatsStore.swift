import Foundation
import SwiftUI

/// Reads the tunnel extension's `stats.json` from the shared App Group
/// container and exposes it to SwiftUI. Refresh is foreground-only by design
/// (no polling timer) — the user explicitly opted out of background polling.
@MainActor
final class StatsStore: ObservableObject {
    @Published var snapshot: StatsSnapshot?
    /// Light-weight reachability ping measured by the app process. Distinct
    /// from `snapshot.pingMs`, which is the tunnel→proxy latency reported
    /// by the extension.
    @Published var lastPingMs: Int?
    @Published var lastRefreshError: String?

    static let appGroupID = "group.com.redfluent.vpn"
    private static let statsFileName = "stats.json"
    private static let pingURL = URL(string: "https://vpn-api.redfluent.com/health")!

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Reused URLSession for ping(). Per Apple's URLSession docs, sessions
    /// should be retained across requests; constructing one per call leaks
    /// configuration objects and prevents connection reuse.
    private let pingSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        return URLSession(configuration: cfg)
    }()

    /// Tracks the in-flight ping so rapid scenePhase changes don't race; a
    /// late-completing failure can no longer overwrite an earlier success.
    private var pingTask: Task<Void, Never>?

    private var statsFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent(Self.statsFileName)
    }

    func refresh() {
        guard let url = statsFileURL else {
            lastRefreshError = "App Group container unavailable"
            return
        }
        do {
            let data = try Data(contentsOf: url)
            // Try ISO8601 first (matches encoder default), then fall back to
            // numeric timestamps in case the extension uses a different policy.
            if let decoded = try? decoder.decode(StatsSnapshot.self, from: data) {
                snapshot = decoded
            } else {
                let fallback = JSONDecoder()
                fallback.dateDecodingStrategy = .secondsSince1970
                snapshot = try fallback.decode(StatsSnapshot.self, from: data)
            }
            lastRefreshError = nil
        } catch CocoaError.fileReadNoSuchFile {
            // Extension hasn't written yet — not an error, just no data.
            snapshot = nil
            lastRefreshError = nil
        } catch {
            lastRefreshError = error.localizedDescription
        }
    }

    /// Lightweight HTTP HEAD-equivalent against the public health endpoint.
    /// Stores the round-trip in `lastPingMs`; sets nil on failure/timeout.
    /// Cancels any prior in-flight ping to dedup overlapping scenePhase calls.
    func ping() async {
        pingTask?.cancel()
        let session = pingSession
        let url = Self.pingURL
        let task = Task { [weak self] in
            var request = URLRequest(url: url, timeoutInterval: 3)
            request.httpMethod = "GET"
            let started = Date()
            let result: Int?
            do {
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                    result = Int(Date().timeIntervalSince(started) * 1000)
                } else {
                    result = nil
                }
            } catch {
                result = nil
            }
            if Task.isCancelled { return }
            await MainActor.run { self?.lastPingMs = result }
        }
        // Fire-and-forget: do NOT `await task.value` here. The whole point
        // of cancelling the prior task and storing the new one is so rapid
        // scenePhase callers don't queue behind a slow ping — awaiting the
        // value would re-introduce that serialization.
        pingTask = task
    }
}
