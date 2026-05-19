import Foundation

/// Fetches the monthly bandwidth snapshot for the currently activated
/// profile and caches the last successful response per-profile inside the
/// shared App Group container so cold-start UIs can still show stale data
/// while a fresh fetch is in flight.
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var isFetching = false

    private let api: APIClient
    private var fetchTask: Task<Void, Never>?
    private var activeProfileId: String?

    /// App Group container shared with the packet tunnel extension.
    private static let appGroupID = "group.com.redfluent.vpn"

    init(api: APIClient = APIClient.shared) {
        self.api = api
    }

    /// Refresh the quota for the active device profile.
    func refresh(profile: DeviceProfile?) {
        guard let profile else {
            fetchTask?.cancel()
            activeProfileId = nil
            snapshot = nil
            lastError = nil
            isFetching = false
            return
        }

        if activeProfileId != profile.profileId {
            activeProfileId = profile.profileId
            snapshot = loadFromDisk(profileId: profile.profileId)
            lastError = nil
        }

        fetchTask?.cancel()
        let profileId = profile.profileId
        let token = profile.token

        fetchTask = Task { [weak self] in
            guard let self else { return }
            self.isFetching = true
            defer { self.isFetching = false }

            do {
                let parsed = try await self.api.fetchQuota(token: token)
                if Task.isCancelled || self.activeProfileId != profileId { return }
                self.snapshot = parsed
                self.lastError = nil
                self.cacheToDisk(parsed, profileId: profileId)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled || self.activeProfileId != profileId { return }
                self.lastError = error.localizedDescription
                if self.snapshot == nil {
                    self.snapshot = self.loadFromDisk(profileId: profileId)
                }
            }
        }
    }

    // MARK: - App Group disk cache

    private func cacheURL(profileId: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent(cacheFileName(for: profileId), isDirectory: false)
    }

    private func cacheFileName(for profileId: String) -> String {
        let safeProfileId = profileId.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]"#,
            with: "-",
            options: .regularExpression
        )
        return "quota-\(safeProfileId).json"
    }

    private func cacheToDisk(_ snapshot: QuotaSnapshot, profileId: String) {
        guard let url = cacheURL(profileId: profileId) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // Best-effort cache; never surface to UI.
        }
    }

    private func loadFromDisk(profileId: String) -> QuotaSnapshot? {
        guard let url = cacheURL(profileId: profileId),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(QuotaSnapshot.self, from: data)
    }
}
