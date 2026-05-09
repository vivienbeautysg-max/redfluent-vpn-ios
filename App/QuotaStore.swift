import Foundation

/// Fetches the monthly bandwidth snapshot from the Cloudflare Worker
/// (`workers/quota.js`) and caches the last successful response to the
/// shared App Group container so cold-start UIs can show stale data
/// while a fresh fetch is in flight.
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var isFetching = false

    private let endpoint: URL
    private let session: URLSession
    private var fetchTask: Task<Void, Never>?

    /// App Group container shared with the packet tunnel extension.
    private static let appGroupID = "group.com.redfluent.vpn"
    private static let cacheFileName = "quota.json"

    // TODO: replace `PLACEHOLDER` with your Cloudflare Workers subdomain
    // after deploying `workers/quota.js` — see `workers/README.md`.
    init(endpoint: URL = URL(string: "https://redfluent-quota.PLACEHOLDER.workers.dev/quota")!) {
        self.endpoint = endpoint
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.urlCache = URLCache(memoryCapacity: 64 * 1024, diskCapacity: 0, directory: nil)
        self.session = URLSession(configuration: cfg)
        loadFromDisk()
    }

    /// Kick off a refresh. Cancels any in-flight fetch first so the latest
    /// caller wins (the dashboard pull-to-refresh shouldn't queue behind
    /// a slow earlier request).
    func refresh() {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            self.isFetching = true
            defer { self.isFetching = false }
            do {
                let (data, response) = try await self.session.data(from: self.endpoint)
                if Task.isCancelled { return }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw NSError(
                        domain: "QuotaStore",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
                    )
                }
                let dec = JSONDecoder()
                dec.dateDecodingStrategy = .iso8601
                let parsed = try dec.decode(QuotaSnapshot.self, from: data)
                self.snapshot = parsed
                self.lastError = nil
                self.cacheToDisk(data)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                self.lastError = error.localizedDescription
                if self.snapshot == nil {
                    self.loadFromDisk()
                }
            }
        }
    }

    // MARK: - App Group disk cache (graceful degradation when offline)

    private var cacheURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent(Self.cacheFileName, isDirectory: false)
    }

    private func cacheToDisk(_ data: Data) {
        guard let url = cacheURL else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // Best-effort cache; never surface to UI.
        }
    }

    private func loadFromDisk() {
        guard let url = cacheURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let cached = try? dec.decode(QuotaSnapshot.self, from: data) {
            self.snapshot = cached
        }
    }
}
