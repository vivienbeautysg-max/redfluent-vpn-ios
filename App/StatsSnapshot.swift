import Foundation

/// Mirror of the snapshot the packet-tunnel extension serialises into the
/// shared App Group container as `stats.json`. Keep in sync with the
/// extension-side definition.
struct StatsSnapshot: Codable, Equatable {
    var timestamp: Date
    var connected: Bool
    var connectionStartedAt: Date?
    var uplinkBps: Int64
    var downlinkBps: Int64
    var totalUp: Int64
    var totalDown: Int64
    var activeConnections: Int
    var proxyConnections: Int
    var directConnections: Int
    var pingMs: Int?
}
