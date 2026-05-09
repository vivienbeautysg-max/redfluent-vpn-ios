import SwiftUI

/// The central tappable status orb. When connected, it is wreathed by two
/// arc segments rotating proportionally to the current uplink/downlink rate.
/// All non-traffic visuals (gradient, paperplane, pulse, scale, disabled
/// state) match the original inline implementation in MainDashboardView.
struct TrafficOrbRing: View {
    let status: TunnelStatus
    let snapshot: StatsSnapshot?
    let action: () async -> Void

    @State private var pulse = false

    private let orbDiameter: CGFloat = 220
    private let ringDiameter: CGFloat = 250
    private let ringStroke: CGFloat = 6

    var body: some View {
        Button { Task { await action() } } label: {
            ZStack {
                if status == .connected {
                    trafficRing
                        .frame(width: ringDiameter, height: ringDiameter)
                        .transition(.opacity.combined(with: .scale))
                }
                Circle()
                    .fill(orbGradient)
                    .frame(width: orbDiameter, height: orbDiameter)
                    .shadow(color: orbShadowColor, radius: 30, x: 0, y: 12)
                if status == .connecting || status == .disconnecting {
                    Circle()
                        .stroke(Theme.Color.textOnBrand.opacity(0.35), lineWidth: 3)
                        .frame(width: 240, height: 240)
                        .scaleEffect(pulse ? 1.15 : 1.0)
                        .opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
                }
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 88, weight: .light))
                    .foregroundStyle(Theme.Color.textOnBrand)
                    .rotationEffect(.degrees(-30))
                    .offset(x: -4, y: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status.isConnected ? "Disconnect VPN" : "Connect VPN")
        .disabled(status == .connecting || status == .disconnecting)
        .padding(.top, Theme.Spacing.lg)
        .scaleEffect(status.isConnected ? 1.05 : 1.0)
        .animation(.spring(duration: 0.6), value: status)
        .onAppear { pulse = true }
    }

    // MARK: - Traffic ring

    private var trafficRing: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let up = Double(snapshot?.uplinkBps ?? 0)
            let down = Double(snapshot?.downlinkBps ?? 0)

            // Rotation speed: 0 B/s → 6s/rev floor; 10 MB/s → ~0.5s/rev.
            let upPeriod = period(forBps: up)
            let downPeriod = period(forBps: down)
            let upAngle = (t.truncatingRemainder(dividingBy: upPeriod) / upPeriod) * 360.0
            let downAngle = (t.truncatingRemainder(dividingBy: downPeriod) / downPeriod) * -360.0

            ZStack {
                Circle()
                    .stroke(Theme.Color.textOnBrand.opacity(0.10), lineWidth: ringStroke)
                arcSegment(fraction: arcFraction(forBps: up),
                           color: Theme.Color.success)
                    .rotationEffect(.degrees(upAngle))
                arcSegment(fraction: arcFraction(forBps: down),
                           color: Color(red: 0.20, green: 0.75, blue: 0.85))
                    .rotationEffect(.degrees(downAngle - 180))
            }
        }
    }

    private func arcSegment(fraction: Double, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: fraction)
            .stroke(color, style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
    }

    /// Logarithmic 0–10 MB/s → 0–270deg of arc.
    private func arcFraction(forBps bps: Double) -> Double {
        guard bps > 1 else { return 0 }
        let max: Double = 10_000_000
        let scaled = log10(min(bps, max)) / log10(max)   // 0…1
        return min(scaled * 0.75, 0.75)                  // cap 270°
    }

    /// Rotation period seconds. Floors at 6s (idle), accelerates with traffic.
    private func period(forBps bps: Double) -> Double {
        guard bps > 1 else { return 6.0 }
        let max: Double = 10_000_000
        let scaled = log10(min(bps, max)) / log10(max)
        return Swift.max(0.5, 6.0 - scaled * 5.5)
    }

    // MARK: - Visuals (mirrors original inline orb)

    private var orbGradient: LinearGradient {
        switch status {
        case .connected:
            return LinearGradient(colors: [Theme.Color.success, Theme.Color.success.opacity(0.7)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .connecting, .disconnecting:
            return LinearGradient(colors: [Theme.Color.warning, Theme.Color.warning.opacity(0.7)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .failed:
            return LinearGradient(colors: [Theme.Color.danger, Theme.Color.danger.opacity(0.7)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .disconnected:
            return LinearGradient(colors: [Theme.Color.brandPrimary, Theme.Color.brandSecondary],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var orbShadowColor: Color {
        switch status {
        case .connected: return Theme.Color.success.opacity(0.4)
        case .failed:    return Theme.Color.danger.opacity(0.4)
        default:         return Theme.Color.brandPrimary.opacity(0.4)
        }
    }
}
