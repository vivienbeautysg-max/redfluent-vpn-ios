import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tunnelManager: TunnelManager
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var quotaStore: QuotaStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(Appearance.storageKey) private var appearanceRaw = Appearance.light.rawValue
    @StateObject private var wifi = WiFiPathWatcher()
    @State private var showingDiagnostics = false
    @State private var showingCreateInvite = false
    @State private var showingOwnerAdmin = false
    @State private var showingSignOutConfirm = false
    @State private var heartbeatTask: Task<Void, Never>?
    @State private var pingTask: Task<Void, Never>?
    @State private var appleLinkError: String?

    private static let privacyURL = URL(string: "https://www.redfluent.com/privacy")!
    private static let termsURL = URL(string: "https://www.redfluent.com/terms")!
    private static let supportURL = URL(string: "https://www.redfluent.com/support")!

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 700
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navRow
                    DotTitle(text: tunnelManager.status.displayName, size: compact ? 44 : 50, dot: titleDot)
                        .padding(.top, compact ? 6 : 18)
                    metaRow
                        .padding(.top, 12)
                    notices
                    hero(height: compact ? 184 : 236)
                        .padding(.horizontal, -Theme.gutter)
                        .padding(.top, compact ? 4 : 18)
                    statsRow
                    bandwidth
                        .padding(.top, compact ? 18 : 24)
                    profileRow
                        .padding(.top, compact ? 20 : 26)
                    if FeatureFlags.appleSignInEnabled && !appState.appleLinked {
                        appleLinkCard.padding(.top, 24)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .rfPage()
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView()
                .environmentObject(appState)
                .environmentObject(tunnelManager)
                .environmentObject(statsStore)
                .rfSheet()
        }
        .sheet(isPresented: $showingCreateInvite) {
            CreateInviteView()
                .environmentObject(appState)
                .rfSheet()
        }
        .sheet(isPresented: $showingOwnerAdmin) {
            OwnerAdminView()
                .environmentObject(appState)
                .rfSheet()
        }
        .confirmationDialog("Sign out of this device?", isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { appState.signOut() }
            Button("Cancel", role: .cancel) { }
        }
        .task {
            #if DEBUG
            if ScreenshotMode.opensOwnerAdmin { showingOwnerAdmin = true }
            if ScreenshotMode.opensCreateInvite { showingCreateInvite = true }
            if ScreenshotMode.opensDiagnostics { showingDiagnostics = true }
            if ScreenshotMode.isOn {
                wifi.start()   // demo state only; the live refreshes below would overwrite the demo data
                return
            }
            #endif
            wifi.start()
            await tunnelManager.loadStatus()
            await appState.refresh()
            statsStore.refresh()
            quotaStore.refresh(token: appState.currentProfile?.token)
            statsStore.startAutoRefresh()
            startHeartbeat()
            startPingLoop()
        }
        .onDisappear {
            statsStore.stopAutoRefresh()
            stopHeartbeat()
            stopPingLoop()
            wifi.stop()
        }
        .onChange(of: tunnelManager.status) { _, status in
            guard !isScreenshot else { return }
            if status == .connected {
                startPingLoop()
            } else {
                stopPingLoop()
                statsStore.lastPingMs = nil   // a reading from a previous connection must not show on the next one
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isScreenshot else { return }
            if phase == .active {
                wifi.start()
                Task { await appState.refresh() }
                statsStore.refresh()
                quotaStore.refresh(token: appState.currentProfile?.token)
                statsStore.startAutoRefresh()
                startHeartbeat()
                startPingLoop()
            } else {
                statsStore.stopAutoRefresh()
                stopHeartbeat()
                stopPingLoop()
                wifi.stop()
            }
        }
    }

    // MARK: - Top

    private var navRow: some View {
        HStack {
            Wordmark()
            Spacer()
            Menu {
                if isOwner {
                    Section {
                        Button { showingOwnerAdmin = true } label: { Label("Owner Admin", systemImage: "person.2") }
                        Button { showingCreateInvite = true } label: { Label("New invite", systemImage: "plus") }
                    }
                }
                Section {
                    Picker(selection: $appearanceRaw) {
                        ForEach(Appearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.menu)
                    Button { showingDiagnostics = true } label: { Label("Diagnostics", systemImage: "stethoscope") }
                }
                Section {
                    Link(destination: Self.privacyURL) { Label("Privacy", systemImage: "hand.raised") }
                    Link(destination: Self.termsURL) { Label("Terms", systemImage: "doc.text") }
                    Link(destination: Self.supportURL) { Label("Support", systemImage: "questionmark.circle") }
                }
                Section {
                    Button(role: .destructive) { showingSignOutConfirm = true } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                MoreGlyph()
            }
            .accessibilityLabel("More")
        }
        .frame(height: 50)
    }

    private var titleDot: DotStyle {
        switch tunnelManager.status {
        case .connected, .connecting: return .filled
        default:                      return .hollow
        }
    }

    /// Flag · region · connected time.
    private var metaRow: some View {
        HStack(spacing: 10) {
            RegionFlag(regionID: regionID)
            if appState.regions.count > 1 {
                // Owner: several regions, picked here.
                Menu {
                    Picker("Region", selection: regionBinding) {
                        ForEach(appState.regions) { region in
                            Text(region.name).tag(region.id)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(regionName)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Theme.Color.ink)
                }
                .disabled(tunnelManager.status == .connecting || tunnelManager.status == .disconnecting)
            } else {
                Text(regionName).foregroundStyle(Theme.Color.ink)
            }
            Circle().fill(Theme.Color.stone).frame(width: 4, height: 4)
            connectedTime
        }
        .font(Theme.Font.text(16, .medium))
    }

    @ViewBuilder
    private var connectedTime: some View {
        if connected, let started = statsStore.snapshot?.connectionStartedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(HomeFormat.clock(context.date.timeIntervalSince(started)))
                    .font(Theme.Font.text(16))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.stone)
            }
        } else {
            Text(HomeFormat.none).font(Theme.Font.text(16)).foregroundStyle(Theme.Color.stone)
        }
    }

    /// One short line each: account expiry, the IPv4-only Wi-Fi hint, a failed start.
    @ViewBuilder
    private var notices: some View {
        let lines = noticeLines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.text) { line in
                    Label {
                        Text(line.text).lineLimit(2)
                    } icon: {
                        Image(systemName: line.icon).font(.system(size: 12, weight: .semibold))
                    }
                    .font(Theme.Font.text(13.5, .medium))
                    .foregroundStyle(Theme.Color.red)
                }
            }
            .padding(.top, 12)
        }
    }

    private struct NoticeLine { let icon: String; let text: String }

    private var noticeLines: [NoticeLine] {
        var out: [NoticeLine] = []
        if let expired = ExpiryDisplay.expiredText(appState.expiry) {
            out.append(NoticeLine(icon: "calendar.badge.exclamationmark", text: expired))
        } else if let left = ExpiryDisplay.daysLeftText(appState.expiry) {
            out.append(NoticeLine(icon: "calendar", text: left))
        }
        if IPv6Hint.shows(onWiFi: wifi.onWiFi, wifiHasIPv6: wifi.wifiHasIPv6, regionID: regionID) {
            out.append(NoticeLine(icon: "wifi.exclamationmark", text: IPv6Hint.text))
        }
        if tunnelManager.status == .failed, let error = tunnelManager.lastError, !error.isEmpty {
            out.append(NoticeLine(icon: "exclamationmark.circle", text: error))
        }
        return out
    }

    // MARK: - The switch

    private func hero(height: CGFloat) -> some View {
        let status = tunnelManager.status
        let enabled = !appState.expiry.expired || status.isConnected
        return Button {
            Task { await tunnelManager.toggle() }
        } label: {
            LandingArt(landed: status == .connected || status == .connecting,
                       glowing: status == .connected,
                       pulsing: status == .connecting || status == .disconnecting,
                       height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(status == .connecting || status == .disconnecting || !enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(status.isConnected ? "Disconnect" : "Connect")
    }

    // MARK: - Down / Up / Ping

    private var statsRow: some View {
        let live = connected ? statsStore.snapshot.flatMap { $0.connected ? $0 : nil } : nil
        let ping: Int? = connected ? (statsStore.snapshot?.pingMs ?? statsStore.lastPingMs) : nil
        return HStack(spacing: 0) {
            statCell(HomeFormat.megabytesPerSecond(live?.downlinkBps), "Down MB/s", first: true)
            statCell(HomeFormat.megabytesPerSecond(live?.uplinkBps), "Up MB/s")
            statCell(HomeFormat.ping(ping), "Ping ms")
        }
        .overlay(alignment: .top) { Rule() }
        .overlay(alignment: .bottom) { Rule() }
    }

    private func statCell(_ value: String, _ label: String, first: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(Theme.Font.display(32))
                .tracking(-0.02 * 32)
                .monospacedDigit()
                .foregroundStyle(value == HomeFormat.none ? Theme.Color.stone : Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).rfLabelStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, first ? 0 : 14)
        .padding(.vertical, 16)
        .overlay(alignment: .leading) {
            if !first { Rectangle().fill(Theme.Color.rule).frame(width: 1) }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Bandwidth

    private var bandwidth: some View {
        let snap = quotaStore.snapshot
        let fraction = snap.flatMap { HomeFormat.fraction(used: $0.usedGB, quota: $0.monthlyQuotaGB) } ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bandwidth").rfLabelStyle()
                Spacer()
                if let snap {
                    Text(ISODate.daysPhrase(snap.daysUntilReset))
                        .font(Theme.Font.text(13, .medium))
                        .foregroundStyle(Theme.Color.ink)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(HomeFormat.gigabytes(snap?.usedGB))
                    .font(Theme.Font.display(60))
                    .tracking(-0.035 * 60)
                    .foregroundStyle(snap == nil ? Theme.Color.stone : Theme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let snap {
                    Text("/ \(HomeFormat.quota(snap.monthlyQuotaGB)) GB")
                        .font(Theme.Font.text(17, .medium))
                        .foregroundStyle(Theme.Color.stone)
                }
            }
            .padding(.top, 12)
            UsageLine(fraction: fraction)
                .padding(.top, 18)
            HStack(spacing: 26) {
                ioText("Out", snap.map { HomeFormat.bytesAsGB($0.outgoingBytes) })
                ioText("In", snap.map { HomeFormat.bytesAsGB($0.incomingBytes) })
            }
            .padding(.top, 14)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isScreenshot else { return }
            quotaStore.refresh(token: appState.currentProfile?.token)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Refresh")
    }

    private func ioText(_ label: String, _ value: String?) -> some View {
        (Text(label + " ").foregroundStyle(Theme.Color.stone)
            + Text(value ?? HomeFormat.none).font(Theme.Font.text(13.5, .semibold)).foregroundStyle(Theme.Color.ink))
            .font(Theme.Font.text(13.5))
    }

    // MARK: - Profile

    private var profileRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.Color.soft).frame(width: 30, height: 30)
                    Circle().fill(Theme.Color.red).frame(width: 9, height: 9)
                }
                Text(appState.currentProfile?.ownerLabel ?? HomeFormat.none)
                    .font(Theme.Font.text(15, .semibold))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ViewThatFits(in: .horizontal) {
                Text("Profile \(shortProfileId) \u{00B7} Config v\(configVersion)").lineLimit(1)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Profile \(shortProfileId)")
                    Text("Config v\(configVersion)")
                }
            }
            .font(Theme.Font.mono(12))
            .foregroundStyle(Theme.Color.stone)
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rule() }
    }

    private var shortProfileId: String {
        guard let id = appState.currentProfile?.profileId else { return HomeFormat.none }
        return String(id.suffix(8))
    }

    private var configVersion: String { appState.currentProfile?.configVersion ?? HomeFormat.none }

    // Only until the invite is linked to an Apple ID; behind FeatureFlags.appleSignInEnabled.
    private var appleLinkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Restore on a new phone").rfLabelStyle()
            AppleRecoverButton(
                onLightBackground: colorScheme != .dark,
                onToken: { token in
                    appleLinkError = nil
                    Task { await appState.linkApple(identityToken: token) }
                },
                onError: { message in appleLinkError = message }
            )
            if let appleLinkError {
                Text(appleLinkError)
                    .font(Theme.Font.text(12.5, .medium))
                    .foregroundStyle(Theme.Color.red)
            }
        }
    }

    // MARK: - State

    private var isOwner: Bool { appState.currentProfile?.ownerLabel == "Owner" }
    private var connected: Bool { tunnelManager.status == .connected }

    private var isScreenshot: Bool {
        #if DEBUG
        return ScreenshotMode.isOn
        #else
        return false
        #endif
    }

    /// The region in use: what the tunnel started with while connected, otherwise the selection.
    private var regionID: String? {
        if connected, let active = RegionStore.active() { return active.id }
        return appState.selectedRegionID
    }

    private var regionName: String {
        appState.serverDisplayName(connected: connected) ?? "Tokyo"
    }

    private var regionBinding: Binding<String> {
        Binding(get: { appState.selectedRegionID }, set: { appState.selectRegion($0) })
    }

    // MARK: - Ping / heartbeat

    /// While connected: measure the round trip every 15 s, so "Ping" is a current reading through the tunnel.
    private func startPingLoop() {
        pingTask?.cancel()
        guard connected else { pingTask = nil; return }
        pingTask = Task {
            while !Task.isCancelled {
                await statsStore.ping()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private func stopPingLoop() {
        pingTask?.cancel()
        pingTask = nil
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                await sendHeartbeat()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        Task { await sendHeartbeat(forceDisconnected: true) }
    }

    private func sendHeartbeat(forceDisconnected: Bool = false) async {
        // Screenshot mode never talks to the real backend (its token is fake).
        guard !isScreenshot, let token = appState.currentProfile?.token else { return }
        let snap = statsStore.snapshot
        let connected = forceDisconnected ? false : (tunnelManager.status == .connected && (snap?.connected ?? false))
        try? await APIClient.shared.sendHeartbeat(
            connected: connected,
            activeConnections: snap?.activeConnections,
            totalUp: snap?.totalUp,
            totalDown: snap?.totalDown,
            token: token
        )
    }
}

/// Thin bar: the used part in Ink, the red dot where it ends.
struct UsageLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = w * CGFloat(min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Color.soft).frame(height: 2)
                Capsule().fill(Theme.Color.ink).frame(width: x, height: 2)
                Circle().fill(Theme.Color.red).frame(width: 14, height: 14)
                    .offset(x: min(max(x - 7, 0), max(w - 14, 0)))
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

/// A small flag for the region: Japan for Tokyo, Singapore for Singapore, a plain chip otherwise.
struct RegionFlag: View {
    let regionID: String?

    var body: some View {
        ZStack {
            switch regionID?.lowercased() {
            case "tokyo":
                Rectangle().fill(Color.white)
                Circle().fill(Color(uiColor: UIColor(rgb: 0xBC002D))).frame(width: 8, height: 8)
            case "singapore":
                VStack(spacing: 0) {
                    Rectangle().fill(Color(uiColor: UIColor(rgb: 0xEF3340)))
                    Rectangle().fill(Color.white)
                }
            default:
                Rectangle().fill(Theme.Color.soft)
            }
        }
        .frame(width: 22, height: 15)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Theme.Color.rule, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

#Preview {
    MainDashboardView()
        .environmentObject(AppState())
        .environmentObject(TunnelManager())
        .environmentObject(StatsStore())
        .environmentObject(QuotaStore())
}
