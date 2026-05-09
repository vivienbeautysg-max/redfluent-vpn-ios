import Foundation

struct DeviceProfile: Codable, Equatable {
    let profileId: String
    let token: String
    let ownerLabel: String
    let serverRegion: String
    let configVersion: String
    let expiresAt: String?
}

struct ProfileStatus: Codable, Equatable {
    let enabled: Bool
    let profileId: String
    let ownerLabel: String
    let serverRegion: String
    let routingMode: String
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
        case .status(let code, let msg): return "Server error \(code): \(msg)"
        case .decoding(let err):         return "Bad response: \(err.localizedDescription)"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    private var baseURL: URL {
        URL(string: ProcessInfo.processInfo.environment["RFV_API_BASE"] ?? "https://api.redfluent.com/vpn")!
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
            routingMode: routing
        )
    }

    private func post<B: Encodable, R: Decodable>(path: String, body: B, token: String?) async throws -> R {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONEncoder().encode(body)
        return try await send(req)
    }

    private func get<R: Decodable>(path: String, token: String?) async throws -> R {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "GET"
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return try await send(req)
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
