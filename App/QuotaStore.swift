import Foundation

/// Fetches the monthly bandwidth snapshot from the backend quota endpoint
/// and caches the last successful response to the
/// shared App Group container so cold-start UIs can show stale data
/// while a fresh fetch is in flight.
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var isFetching = false

    private let endpoint: URL?
    private let clientSecret: String?
    private let session: URLSession
    private var fetchTask: Task<Void, Never>?

    /// App Group container shared with the packet tunnel extension.
    private static let appGroupID = "group.com.redfluent.vpn"
    private static let cacheFileName = "quota.json"

    /// True when a real quota endpoint has been configured via
    /// `QuotaEndpointURL` in Info.plist. UI surfaces should hide the
    /// quota card entirely when this is false rather than render an
    /// error from the placeholder host.
    var isConfigured: Bool { endpoint != nil }

    /// Default initializer reads `QuotaEndpointURL` from Info.plist. If
    /// the key is absent or still equals the literal string `PLACEHOLDER`
    /// (the value the orchestrator stamps in pre-deploy), `endpoint` is
    /// nil and `refresh()` becomes a no-op.
    init() {
        let infoEndpoint = Bundle.main.object(forInfoDictionaryKey: "QuotaEndpointURL") as? String
        if let raw = infoEndpoint {
            // Trim + uppercase-compare so misformatted plist values (extra
            // whitespace, "placeholder", "Placeholder", etc.) fail closed
            // — i.e. the card hides — rather than attempting a URL fetch
            // against a bad host.
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               trimmed.uppercased() != "PLACEHOLDER",
               let url = URL(string: trimmed) {
                self.endpoint = url
            } else {
                self.endpoint = nil
            }
        } else {
            self.endpoint = nil
        }
        let secret = Bundle.main.object(forInfoDictionaryKey: "QuotaClientSecret") as? String
        if let secret, !secret.isEmpty, secret != "PLACEHOLDER" {
            self.clientSecret = secret
        } else {
            self.clientSecret = nil
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.urlCache = URLCache(memoryCapacity: 64 * 1024, diskCapacity: 0, directory: nil)
        self.session = URLSession(configuration: cfg)
        loadFromDisk()
    }

    /// Test-only initializer that lets callers inject an explicit endpoint
    /// (e.g. to point at a local mock server).
    init(endpoint: URL?, clientSecret: String? = nil) {
        self.endpoint = endpoint
        self.clientSecret = clientSecret
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
        guard let endpoint else {
            // Worker not yet deployed — silently no-op so the card can hide
            // itself rather than surface a fake error.
            self.lastError = nil
            self.snapshot = nil
            return
        }
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            self.isFetching = true
            defer { self.isFetching = false }
            do {
                let requestURL: URL
                if var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) {
                    var queryItems = components.queryItems ?? []
                    queryItems.append(URLQueryItem(name: "fresh", value: "1"))
                    components.queryItems = queryItems
                    requestURL = components.url ?? endpoint
                } else {
                    requestURL = endpoint
                }

                var req = URLRequest(url: requestURL)
                req.httpMethod = "GET"
                req.cachePolicy = .reloadIgnoringLocalCacheData
                req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                if let secret = self.clientSecret {
                    req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await self.session.data(for: req)
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
