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
    func ping() async {
        var request = URLRequest(url: Self.pingURL, timeoutInterval: 3)
        request.httpMethod = "GET"
        let session = URLSession(configuration: .ephemeral)
        let started = Date()
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                lastPingMs = nil
                return
            }
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            lastPingMs = ms
        } catch {
            lastPingMs = nil
        }
    }
}
