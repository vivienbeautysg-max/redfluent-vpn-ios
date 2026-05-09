import Foundation

/// Mirror of the snapshot the packet-tunnel extension serialises into the
/// shared App Group container as `stats.json`. Keep in sync with the
/// extension-side definition.
struct StatsSnapshot: Codable, Equatable {
    var timestamp: Date
    var connected: Bool
    var connectionStartedAt: Date?
    var uplinkBps: Int
    var downlinkBps: Int
    var totalUp: Int
    var totalDown: Int
    var activeConnections: Int
    var proxyConnections: Int
    var directConnections: Int
    var pingMs: Int?
}
