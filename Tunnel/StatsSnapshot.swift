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

    /// Current throughput, bytes per second (computed as differential of /connections totals).
    var uplinkBps: Int64
    var downlinkBps: Int64

    /// Cumulative session totals, bytes (from clash /connections uploadTotal/downloadTotal).
    /// Int64 — these routinely exceed Int32 on a multi-GB session.
    var totalUp: Int64
    var totalDown: Int64

    var activeConnections: Int
    var proxyConnections: Int
    var directConnections: Int

    /// Latest measured RTT in milliseconds; `nil` if not yet measured.
    var pingMs: Int?

    init(timestamp: Date = Date(),
         connected: Bool = false,
         connectionStartedAt: Date? = nil,
         uplinkBps: Int64 = 0,
         downlinkBps: Int64 = 0,
         totalUp: Int64 = 0,
         totalDown: Int64 = 0,
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
