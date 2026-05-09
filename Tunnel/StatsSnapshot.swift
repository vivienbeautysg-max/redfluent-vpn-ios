import Foundation

/// Snapshot of tunnel statistics shared between the Packet Tunnel extension
/// and the main app via the App Group container.
///
/// Intentionally framework-clean (Foundation only) so the same source file
/// can be linked into multiple targets if desired.
struct StatsSnapshot: Codable, Equatable {
    var timestamp: Date
    var connected: Bool
    var connectionStartedAt: Date?

    /// Current throughput, bytes per second (instantaneous, from clash /traffic).
    var uplinkBps: Int
    var downlinkBps: Int

    /// Cumulative session totals, bytes (from clash /connections uploadTotal/downloadTotal).
    var totalUp: Int
    var totalDown: Int

    var activeConnections: Int
    var proxyConnections: Int
    var directConnections: Int

    /// Latest measured RTT in milliseconds; `nil` if not yet measured.
    var pingMs: Int?

    init(timestamp: Date = Date(),
         connected: Bool = false,
         connectionStartedAt: Date? = nil,
         uplinkBps: Int = 0,
         downlinkBps: Int = 0,
         totalUp: Int = 0,
         totalDown: Int = 0,
         activeConnections: Int = 0,
         proxyConnections: Int = 0,
         directConnections: Int = 0,
         pingMs: Int? = nil) {
        self.timestamp = timestamp
        self.connected = connected
        self.connectionStartedAt = connectionStartedAt
        self.uplinkBps = uplinkBps
        self.downlinkBps = downlinkBps
        self.totalUp = totalUp
        self.totalDown = totalDown
        self.activeConnections = activeConnections
        self.proxyConnections = proxyConnections
        self.directConnections = directConnections
        self.pingMs = pingMs
    }
}
