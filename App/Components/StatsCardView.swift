import SwiftUI
import Charts

/// Live traffic stats card. Pulls its data from `StatsStore` in the
/// environment. Renders an empty state when disconnected or before the
/// extension has produced a snapshot.
struct StatsCardView: View {
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var tunnelManager: TunnelManager

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(Theme.Color.brandPrimary)
                Text("Live Traffic")
                    .font(Theme.Font.titleLarge)
                    .foregroundStyle(Theme.Color.brandPrimary)
                Spacer()
            }

            if shouldShowEmpty {
                emptyState
            } else if let snap = statsStore.snapshot {
                content(snap)
            }
        }
        .card()
    }

    private var shouldShowEmpty: Bool {
        guard let snap = statsStore.snapshot else { return true }
        return !snap.connected || tunnelManager.status != .connected
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(Theme.Color.textSecondary)
            Text("Connect to see live traffic stats")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ snap: StatsSnapshot) -> some View {
        speedRow(snap)
        Divider()
        totalRow(snap)
        Divider()
        durationRow(snap)
        Divider()
        pingAndConnectionsRow(snap)
        if snap.activeConnections > 0 {
            connectionMixChart(snap)
        }
    }

    private func speedRow(_ snap: StatsSnapshot) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            metricBlock(arrow: "arrow.up",
                        arrowColor: Theme.Color.success,
                        title: "Upload",
                        value: formatSpeed(snap.uplinkBps))
            metricBlock(arrow: "arrow.down",
                        arrowColor: Theme.Color.success,
                        title: "Download",
                        value: formatSpeed(snap.downlinkBps))
        }
    }

    private func totalRow(_ snap: StatsSnapshot) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            statPair(label: "Total ↑", value: formatBytes(snap.totalUp))
            statPair(label: "Total ↓", value: formatBytes(snap.totalDown))
        }
    }

    private func durationRow(_ snap: StatsSnapshot) -> some View {
        HStack {
            Image(systemName: "clock")
                .foregroundStyle(Theme.Color.brandPrimary)
            Text("Duration").foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            if let started = snap.connectionStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(formatDuration(ctx.date.timeIntervalSince(started)))
                        .font(Theme.Font.monoBody)
                        .fontWeight(.medium)
                }
            } else {
                Text("—").font(Theme.Font.monoBody)
            }
        }
        .font(Theme.Font.body)
    }

    private func pingAndConnectionsRow(_ snap: StatsSnapshot) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            statPair(label: "Ping",
                     value: statsStore.lastPingMs.map { "\($0) ms" } ?? "—")
            statPair(label: "Connections", value: "\(snap.activeConnections)")
        }
    }

    private func connectionMixChart(_ snap: StatsSnapshot) -> some View {
        let data: [ConnectionSlice] = [
            .init(kind: "Proxy",  count: snap.proxyConnections,  color: Theme.Color.brandPrimary),
            .init(kind: "Direct", count: snap.directConnections, color: Theme.Color.success)
        ]
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Routing")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            Chart(data) { slice in
                SectorMark(
                    angle: .value("Count", slice.count),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(slice.color)
            }
            .frame(height: 120)
            // Legend rendered outside the slices so we never rely on
            // text-on-fill contrast (slice colors don't meet WCAG against
            // textOnBrand white).
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(data) { slice in
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(slice.color)
                            .frame(width: 8, height: 8)
                        Text("\(slice.kind): \(slice.count) conns")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Sub-views

    private func metricBlock(arrow: String, arrowColor: Color,
                             title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: 4) {
                Image(systemName: arrow).foregroundStyle(arrowColor)
                Text(title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Text(value)
                .font(Theme.Font.displayMedium)
                .foregroundStyle(Theme.Color.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statPair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            Text(value)
                .font(Theme.Font.bodyLarge)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Formatting

    private func formatSpeed(_ bps: Int) -> String {
        let bcf = ByteCountFormatter()
        bcf.countStyle = .binary
        bcf.allowedUnits = [.useKB, .useMB, .useGB]
        return bcf.string(fromByteCount: Int64(bps)) + "/s"
    }

    private func formatBytes(_ bytes: Int) -> String {
        let bcf = ByteCountFormatter()
        bcf.countStyle = .binary
        bcf.allowedUnits = [.useKB, .useMB, .useGB]
        return bcf.string(fromByteCount: Int64(bytes))
    }

    private func formatDuration(_ secs: TimeInterval) -> String {
        let s = max(0, Int(secs))
        let h = s / 3600
        let m = (s % 3600) / 60
        let r = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, r) }
        return String(format: "%02d:%02d", m, r)
    }
}

private struct ConnectionSlice: Identifiable {
    let id = UUID()
    let kind: String
    let count: Int
    let color: Color
}
