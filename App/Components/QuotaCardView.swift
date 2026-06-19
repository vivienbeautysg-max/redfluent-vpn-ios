import SwiftUI

/// Monthly bandwidth quota card. Pulls its data from `QuotaStore` in
/// the environment. Shows a traffic-light progress bar, headline
/// "used / total · N days left", and an outgoing/incoming split.
struct QuotaCardView: View {
    @EnvironmentObject private var quotaStore: QuotaStore
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if !quotaStore.isConfigured {
            // Worker not deployed yet — hide the card entirely rather than
            // surface a misleading error from the placeholder URL.
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
                // Avoid stacking cold-start fetches: only kick a refresh if
                // we have nothing yet AND there isn't one already in flight.
                if quotaStore.snapshot == nil && !quotaStore.isFetching {
                    quotaStore.refresh(token: appState.currentProfile?.token)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(Theme.Color.brandPrimary)
            Text("Monthly Bandwidth")
                .font(Theme.Font.titleLarge)
                .foregroundStyle(Theme.Color.brandPrimary)
            Spacer()
            Button {
                quotaStore.refresh(token: appState.currentProfile?.token)
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

    // MARK: - Content

    @ViewBuilder
    private func content(_ snap: QuotaSnapshot) -> some View {
        let pct = max(0, min(snap.percentUsed, 1))
        let tint = barTint(for: pct)

        ProgressView(value: pct)
            .progressViewStyle(.linear)
            .tint(tint)
            .scaleEffect(x: 1, y: 1.6, anchor: .center)
            .padding(.vertical, Theme.Spacing.xs)

        HStack {
            Text("\(formatGB(snap.usedGB)) / \(formatGB(snap.monthlyQuotaGB))")
                .font(Theme.Font.bodyLarge)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            Text("\(snap.daysUntilReset) day\(snap.daysUntilReset == 1 ? "" : "s") left")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }

        if let selfUsed = snap.selfUsedGB {
            HStack {
                Text("This device")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Text(selfUsageText(used: selfUsed, quota: snap.selfQuotaGB))
                    .font(Theme.Font.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
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

    // MARK: - Empty / error states

    private var loadingState: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text("Fetching quota…")
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

    // MARK: - Helpers

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

    /// Format a GB value with grouped thousands. Two decimals under
    /// 1,000 GB, integer above (matches the spec sample
    /// "1.36 GB" / "2,048 GB").
    private func selfUsageText(used: Double, quota: Double?) -> String {
        if let quota, quota > 0 { return "\(formatGB(used)) / \(formatGB(quota))" }
        return formatGB(used)
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
