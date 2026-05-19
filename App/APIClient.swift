import Foundation

struct DeviceProfile: Codable, Equatable {
    let profileId: String
    let token: String
    let ownerLabel: String
    let serverRegion: String
    let configVersion: String
    let monthlyQuotaGB: Int?
    let expiresAt: String?
}

struct ProfileStatus: Codable, Equatable {
    let enabled: Bool
    let profileId: String
    let ownerLabel: String
    let serverRegion: String
    let routingMode: String
    let monthlyQuotaGB: Int?
}

struct CreatedInvite: Codable, Equatable {
    let code: String
    let label: String
    let maxDevices: Int
    let monthlyQuotaGB: Int
    let enabled: Bool
    let expiresAt: String?
}

struct OwnerInvite: Codable, Equatable, Identifiable {
    var id: String { code }
    let code: String
    let label: String
    let maxDevices: Int
    let activeDevices: Int
    let monthlyQuotaGB: Int?
    let enabled: Bool
    let expiresAt: String?
    let createdAt: String?
}

struct OwnerDevice: Codable, Equatable, Identifiable {
    var id: String { profileId }
    let profileId: String
    let inviteCode: String
    let inviteLabel: String?
    let displayName: String
    let deviceName: String?
    let appVersion: String?
    let ownerLabel: String
    let enabled: Bool
    let connected: Bool
    let inUse: Bool
    let lastSeenAt: String?
    let lastHeartbeatAt: String?
    let lastConnectedAt: String?
    let lastDisconnectedAt: String?
    let lastActiveConnections: Int?
    let lastTotalUp: Int64?
    let lastTotalDown: Int64?
    let createdAt: String
    let revokedAt: String?
}

struct OwnerActivationEvent: Codable, Equatable, Identifiable {
    let id: String
    let inviteCodeInput: String?
    let inviteCodeNormalized: String?
    let matchedInviteCode: String?
    let devicePublicId: String?
    let deviceName: String?
    let appVersion: String?
    let outcome: String
    let reason: String?
    let httpStatus: Int
    let profileId: String?
    let activeDevices: Int?
    let maxDevices: Int?
    let remoteIp: String?
    let userAgent: String?
    let createdAt: String
    let createdAtSgt: String
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case transport(Error)
    case status(Int, String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:                return "Invalid API URL"
        case .transport(let err):        return "Network error: \(err.localizedDescription)"
        case .status(let code, let msg): return APIError.statusMessage(code: code, rawMessage: msg)
        case .decoding(let err):         return "Bad response: \(err.localizedDescription)"
        }
    }

    private static func statusMessage(code: Int, rawMessage: String) -> String {
        let reason = serverReason(from: rawMessage)
        switch reason {
        case "invalid invite":
            return "Invite code was not found. Check the code and try again."
        case "invite disabled":
            return "This invite has been disabled by the owner."
        case "invite expired":
            return "This invite has expired."
        case "invite device limit reached":
            return "This invite has reached its device limit. Ask the owner to raise the limit or revoke an old device."
        case "owner device cannot be revoked here":
            return "Owner devices are protected and cannot be revoked here."
        default:
            return "Server error \(code): \(reason)"
        }
    }

    private static func serverReason(from rawMessage: String) -> String {
        guard let data = rawMessage.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? String
        else {
            return rawMessage
        }
        return error
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    private var baseURL: URL {
        URL(string: ProcessInfo.processInfo.environment["RFV_API_BASE"] ?? "https://vpn-api.redfluent.com")!
    }

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)
        self.decoder = JSONDecoder()
    }

    func redeemInvite(code: String, devicePublicId: String, deviceName: String, appVersion: String) async throws -> DeviceProfile {
        struct Request: Encodable {
            let inviteCode: String
            let devicePublicId: String
            let deviceName: String
            let appVersion: String
        }
        struct Envelope: Decodable {
            let ok: Bool
            let error: String?
            let profileId: String?
            let token: String?
            let ownerLabel: String?
            let serverRegion: String?
            let configVersion: String?
            let monthlyQuotaGB: Int?
            let expiresAt: String?
        }
        let body = Request(inviteCode: code, devicePublicId: devicePublicId, deviceName: deviceName, appVersion: appVersion)
        let env: Envelope = try await post(path: "/redeem-invite", body: body, token: nil)
        guard env.ok,
              let profileId = env.profileId,
              let token = env.token,
              let ownerLabel = env.ownerLabel,
              let region = env.serverRegion,
              let configVersion = env.configVersion
        else {
            throw APIError.status(403, env.error ?? "redeem rejected")
        }
        return DeviceProfile(
            profileId: profileId,
            token: token,
            ownerLabel: ownerLabel,
            serverRegion: region,
            configVersion: configVersion,
            monthlyQuotaGB: env.monthlyQuotaGB,
            expiresAt: env.expiresAt
        )
    }

    func fetchProfile(token: String) async throws -> ProfileStatus {
        struct Envelope: Decodable {
            let ok: Bool
            let error: String?
            let enabled: Bool?
            let profileId: String?
            let ownerLabel: String?
            let serverRegion: String?
            let routingMode: String?
            let monthlyQuotaGB: Int?
        }
        let env: Envelope = try await get(path: "/profile", token: token)
        guard env.ok,
              let enabled = env.enabled,
              let profileId = env.profileId,
              let ownerLabel = env.ownerLabel,
              let region = env.serverRegion,
              let routing = env.routingMode
        else {
            throw APIError.status(403, env.error ?? "profile rejected")
        }
        return ProfileStatus(
            enabled: enabled,
            profileId: profileId,
            ownerLabel: ownerLabel,
            serverRegion: region,
            routingMode: routing,
            monthlyQuotaGB: env.monthlyQuotaGB
        )
    }

    func fetchQuota(token: String) async throws -> QuotaSnapshot {
        try await get(path: "/device/quota?fresh=1", token: token)
    }

    func createInvite(code: String, label: String?, maxDevices: Int, monthlyQuotaGB: Int, token: String) async throws -> CreatedInvite {
        struct Request: Encodable {
            let code: String
            let label: String?
            let maxDevices: Int
            let monthlyQuotaGB: Int
        }
        struct Envelope: Decodable {
            let ok: Bool
            let error: String?
            let invite: CreatedInvite?
        }
        let env: Envelope = try await post(
            path: "/owner/invites",
            body: Request(code: code, label: label, maxDevices: maxDevices, monthlyQuotaGB: monthlyQuotaGB),
            token: token
        )
        guard env.ok, let invite = env.invite else {
            throw APIError.status(403, env.error ?? "create invite rejected")
        }
        return invite
    }

    func fetchOwnerInvites(token: String) async throws -> [OwnerInvite] {
        struct Envelope: Decodable {
            let ok: Bool
            let error: String?
            let invites: [OwnerInvite]?
        }
        let env: Envelope = try await get(path: "/owner/invites", token: token)
        guard env.ok, let invites = env.invites else {
            throw APIError.status(403, env.error ?? "owner invites rejected")
        }
        return invites
    }

    func updateOwnerInvite(_ invite: OwnerInvite, newCode: String, label: String, maxDevices: Int, monthlyQuotaGB: Int, enabled: Bool, token: String) async throws -> OwnerInvite {
        struct Request: Encodable {
            let code: String
            let newCode: String
            let label: String
            let maxDevices: Int
            let monthlyQuotaGB: Int
            let enabled: Bool
        }
        struct Envelope: Decodable {
            let ok: Bool
            let error: String?
            let invite: OwnerInvite?
        }
        let env: Envelope = try await post(
            path: "/owner/invites/update",
            body: Request(code: invite.code, newCode: newCode, label: label, maxDevices: maxDevices, monthlyQuotaGB: monthlyQuotaGB, enabled: enabled),
            token: token
        )
        guard env.ok, let updated = env.invite else {
            throw APIError.status(403, env.error ?? "update invite rejected")
        }
        return updated
    }

    func deleteOwnerInvite(_ invite: OwnerInvite, token: String) async throws -> Int {
        struct Request: Encodable {
            let code: String
        }
        struct Envelope: Decodable {
            let ok: Bool
            let error: String?
            let revokedDevices: Int?
        }
        let env: Envelope = try await post(
            path: "/owner/invites/delete",
            body: Request(code: invite.code),
            token: token
        )
        guard env.ok else {
            throw APIError.status(403, env.error ?? "delete invite rejected")
        }
        return env.revokedDevices ?? 0
    }

    func fetchOwnerDevices(token: String) async throws -> [OwnerDevice] {
        struct Envelope: Decodable {
            let ok: Bool
            let error: String?
            let devices: [OwnerDevice]?
        }
        let env: Envelope = try await get(path: "/owner/devices", token: token)
        guard env.ok, let devices = env.devices else {
            throw APIError.status(403, env.error ?? "owner devices rejected")
        }
        return devices
    }

    func fetchOwnerActivationEvents(token: String) async throws -> [OwnerActivationEvent] {
        struct Envelope: Decodable {
            let ok: Bool
            let error: String?
            let events: [OwnerActivationEvent]?
        }
        let env: Envelope = try await get(path: "/owner/activation-events?limit=80", token: token)
        guard env.ok, let events = env.events else {
            throw APIError.status(403, env.error ?? "activation events rejected")
        }
        return events
    }

    func renameOwnerDevice(profileId: String, displayName: String, token: String) async throws -> OwnerDevice {
        struct Request: Encodable {
            let profileId: String
            let displayName: String
        }
        struct Envelope: Decodable {
            let ok: Bool
            let error: String?
            let device: OwnerDevice?
        }
        let env: Envelope = try await post(
            path: "/owner/devices/rename",
            body: Request(profileId: profileId, displayName: displayName),
            token: token
        )
        guard env.ok, let device = env.device else {
            throw APIError.status(403, env.error ?? "rename device rejected")
        }
        return device
    }

    func revokeOwnerDevice(profileId: String, token: String) async throws -> OwnerDevice {
        struct Request: Encodable {
            let profileId: String
        }
        struct Envelope: Decodable {
            let ok: Bool
            let error: String?
            let device: OwnerDevice?
        }
        let env: Envelope = try await post(
            path: "/owner/devices/revoke",
            body: Request(profileId: profileId),
            token: token
        )
        guard env.ok, let device = env.device else {
            throw APIError.status(403, env.error ?? "revoke device rejected")
        }
        return device
    }

    func sendHeartbeat(connected: Bool, activeConnections: Int?, totalUp: Int64?, totalDown: Int64?, token: String) async throws {
        struct Request: Encodable {
            let connected: Bool
            let activeConnections: Int?
            let totalUp: Int64?
            let totalDown: Int64?
        }
        struct Envelope: Decodable {
            let ok: Bool
            let error: String?
        }
        let env: Envelope = try await post(
            path: "/device/heartbeat",
            body: Request(connected: connected, activeConnections: activeConnections, totalUp: totalUp, totalDown: totalDown),
            token: token
        )
        guard env.ok else {
            throw APIError.status(403, env.error ?? "heartbeat rejected")
        }
    }

    private func post<B: Encodable, R: Decodable>(path: String, body: B, token: String?) async throws -> R {
        var req = URLRequest(url: try requestURL(path: path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONEncoder().encode(body)
        return try await send(req)
    }

    private func get<R: Decodable>(path: String, token: String?) async throws -> R {
        var req = URLRequest(url: try requestURL(path: path))
        req.httpMethod = "GET"
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return try await send(req)
    }

    private func requestURL(path: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }

        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(pieces.first ?? "")
        let normalizedPath = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
        let basePath = components.path == "/" ? "" : components.path
        components.path = basePath + normalizedPath
        components.percentEncodedQuery = pieces.count > 1 ? String(pieces[1]) : nil

        guard let url = components.url else {
            throw APIError.invalidURL
        }
        return url
    }

    private func send<R: Decodable>(_ request: URLRequest) async throws -> R {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.status(-1, "no http response")
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw APIError.status(http.statusCode, bodyText)
        }
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
