import SwiftUI

/// Monthly bandwidth quota card. Owners see global server traffic; invited
/// devices see their own usage against the quota assigned to that invite.
struct QuotaCardView: View {
    let profile: DeviceProfile?

    @EnvironmentObject private var quotaStore: QuotaStore

    var body: some View {
        if profile == nil {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header

                if let snap = quotaStore.snapshot {
                    content(snap)
                } else if quotaStore.lastError != nil {
                    errorState
                } else {
                    loadingState
                }
            }
            .card()
            .onAppear {
                if quotaStore.snapshot == nil && !quotaStore.isFetching {
                    quotaStore.refresh(profile: profile)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(Theme.Color.brandPrimary)
            Text(headerTitle)
                .font(Theme.Font.titleLarge)
                .foregroundStyle(Theme.Color.brandPrimary)
            Spacer()
            Button {
                quotaStore.refresh(profile: profile)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Theme.Color.brandPrimary)
                    .rotationEffect(.degrees(quotaStore.isFetching ? 360 : 0))
                    .animation(
                        quotaStore.isFetching
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: quotaStore.isFetching
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh quota")
        }
    }

    @ViewBuilder
    private func content(_ snap: QuotaSnapshot) -> some View {
        if !(snap.isUnlimited ?? false) {
            let pct = max(0, min(snap.percentUsed, 1))
            ProgressView(value: pct)
                .progressViewStyle(.linear)
                .tint(barTint(for: pct))
                .scaleEffect(x: 1, y: 1.6, anchor: .center)
                .padding(.vertical, Theme.Spacing.xs)
        }

        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headlineText(for: snap))
                    .font(Theme.Font.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(subtitleText(for: snap))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            Text("\(snap.daysUntilReset) day\(snap.daysUntilReset == 1 ? "" : "s") left")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }

        Divider()

        HStack(spacing: Theme.Spacing.lg) {
            trafficBlock(
                arrow: "arrow.up",
                arrowColor: Theme.Color.success,
                title: "Outgoing",
                value: formatBytesGB(snap.outgoingBytes)
            )
            trafficBlock(
                arrow: "arrow.down",
                arrowColor: Theme.Color.brandPrimary,
                title: "Incoming",
                value: formatBytesGB(snap.incomingBytes)
            )
        }

        if let err = quotaStore.lastError {
            Text("Last refresh failed: \(err)")
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.Color.warning)
        }
    }

    private var loadingState: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text("Fetching quota...")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var errorState: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Color.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't fetch quota")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                if let err = quotaStore.lastError {
                    Text(err)
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var headerTitle: String {
        switch quotaScope {
        case "server":
            return "Server Bandwidth"
        default:
            return "My Bandwidth"
        }
    }

    private var quotaScope: String {
        if let scope = quotaStore.snapshot?.scope {
            return scope
        }
        return profile?.ownerLabel == "Owner" ? "server" : "device"
    }

    private func headlineText(for snap: QuotaSnapshot) -> String {
        if snap.isUnlimited ?? false {
            return "\(formatGB(snap.usedGB)) used"
        }
        return "\(formatGB(snap.usedGB)) / \(formatGB(snap.monthlyQuotaGB))"
    }

    private func subtitleText(for snap: QuotaSnapshot) -> String {
        if snap.isUnlimited ?? false {
            return quotaScope == "server"
                ? "Used server traffic with no monthly cap"
                : "My usage with no monthly cap"
        }
        return quotaScope == "server"
            ? "Used / total server traffic"
            : "My usage / assigned monthly quota"
    }

    private func barTint(for percent: Double) -> Color {
        switch percent {
        case ..<0.60:  return Theme.Color.success
        case ..<0.85:  return Theme.Color.warning
        default:       return Theme.Color.danger
        }
    }

    private func trafficBlock(arrow: String, arrowColor: Color,
                              title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: 4) {
                Image(systemName: arrow).foregroundStyle(arrowColor)
                Text(title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Text(value)
                .font(Theme.Font.bodyLarge)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Color.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatGB(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = true
        if value < 1000 {
            nf.minimumFractionDigits = 2
            nf.maximumFractionDigits = 2
        } else {
            nf.maximumFractionDigits = 0
        }
        let s = nf.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(s) GB"
    }

    private func formatBytesGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        return formatGB(gb)
    }
}
