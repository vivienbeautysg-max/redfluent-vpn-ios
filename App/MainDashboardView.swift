import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tunnelManager: TunnelManager
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var quotaStore: QuotaStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.rfReduceMotion) private var reduceMotion
    @AppStorage(Appearance.storageKey) private var appearanceRaw = Appearance.light.rawValue
    @StateObject private var wifi = WiFiPathWatcher()
    @State private var showingDiagnostics = false
    @State private var showingCreateInvite = false
    @State private var showingOwnerAdmin = false
    @State private var showingSignOutConfirm = false
    @State private var heartbeatTask: Task<Void, Never>?
    @State private var pingTask: Task<Void, Never>?
    /// The answer to linking the Apple ID (the only server action on this page).
    @State private var feedback: ActionFeedback?

    private static let privacyURL = URL(string: "https://www.redfluent.com/privacy")!
    private static let termsURL = URL(string: "https://www.redfluent.com/terms")!
    private static let supportURL = URL(string: "https://www.redfluent.com/support")!

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 700
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navRow
                        .entrance(0)
                    statusTitle(size: compact ? 44 : 50)
                        .padding(.top, compact ? 6 : 18)
                        .entrance(1)
                    VStack(alignment: .leading, spacing: 0) {
                        metaRow
                            .padding(.top, 12)
                        notices
                    }
                    .entrance(2)
                    hero(height: compact ? 184 : 236)
                        .padding(.horizontal, -Theme.gutter)
                        .padding(.top, compact ? 4 : 18)
                        .entrance(3)
                    statsRow
                        .entrance(4)
                    VStack(alignment: .leading, spacing: 0) {
                        bandwidth
                            .padding(.top, compact ? 18 : 24)
                        profileRow
                            .padding(.top, compact ? 20 : 26)
                        if FeatureFlags.appleSignInEnabled && !appState.appleLinked {
                            appleLinkCard.padding(.top, 24)
                        }
                    }
                    .entrance(5)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .actionBanner($feedback)   // inside the reader: the banner's space never flips the compact layout
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
        .onAppear { Haptics.prepare() }
        .onChange(of: tunnelManager.status) { old, status in
            switch Self.statusHaptic(from: old, to: status) {
            case .success?: Haptics.success()
            case .failure?: Haptics.failure()
            case .off?:     Haptics.off()
            case nil:       break
            }
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
                    Picker(selection: appearanceBinding) {
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
            .menuStyle(.button)
            .buttonStyle(PressStyle())
            .accessibilityLabel("More")
        }
        .frame(height: 50)
    }

    /// Light / dark from the menu: a selection tick, and the whole UI cross-fades to the other colours.
    private var appearanceBinding: Binding<String> {
        Binding(get: { appearanceRaw }, set: { raw in
            guard raw != appearanceRaw else { return }
            Haptics.select()
            ThemeFade.apply { appearanceRaw = raw }
        })
    }

    private var titleDot: DotStyle {
        switch tunnelManager.status {
        case .connected, .connecting: return .filled
        default:                      return .hollow
        }
    }

    /// "Connected." / "Disconnected.": the new title cross-fades in, rising 4 pt out of a slight blur, over the old
    /// one (both in one ZStack, so nothing below moves). Reduce Motion: a plain cross-fade.
    private func statusTitle(size: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            DotTitle(text: tunnelManager.status.displayName, size: size, dot: titleDot)
                .id(tunnelManager.status.displayName)
                .transition(reduceMotion ? .opacity : .titleSwap)
        }
        .animation(.easeInOut(duration: 0.3), value: tunnelManager.status)
    }

    enum StatusHaptic { case success, failure, off }

    /// Haptic for a tunnel status change: connected after connecting = success; a start or stop that failed = error;
    /// down after being up or going down = soft. Nothing for states reported at launch (disconnected -> connected).
    static func statusHaptic(from old: TunnelStatus, to new: TunnelStatus) -> StatusHaptic? {
        switch (old, new) {
        case (.connecting, .connected):                      return .success
        case (.connecting, .failed), (.disconnecting, .failed): return .failure
        case (.connected, .disconnected), (.disconnecting, .disconnected): return .off
        default:                                             return nil
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
                    .touchTarget(height: 20)
                }
                .menuStyle(.button)
                .buttonStyle(PressStyle())
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
                let clock = HomeFormat.clock(context.date.timeIntervalSince(started))
                Text(clock)
                    .font(Theme.Font.text(16))
                    .foregroundStyle(Theme.Color.stone)
                    .rollingNumber(clock)
            }
        } else {
            Text(HomeFormat.none).font(Theme.Font.text(16)).foregroundStyle(Theme.Color.stone)
        }
    }

    /// One short line each: account expiry, the IPv4-only Wi-Fi hint, a failed start.
    /// Lines come and go with a fade and a 6 pt drop instead of popping in.
    private var notices: some View {
        let lines = noticeLines
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.text) { line in
                Label {
                    Text(line.text).lineLimit(2)
                } icon: {
                    Image(systemName: line.icon).font(.system(size: 12, weight: .semibold))
                }
                .font(Theme.Font.text(13.5, .medium))
                .foregroundStyle(Theme.Color.red)
                .transition(reduceMotion ? .opacity : .notice)
            }
        }
        .padding(.top, lines.isEmpty ? 0 : 12)
        .animation(reduceMotion ? Motion.fade : .easeOut(duration: 0.25), value: lines.map(\.text))
    }

    private struct NoticeLine { let icon: String; let text: String }

    private var noticeLines: [NoticeLine] {
        var out: [NoticeLine] = []
        if let expired = ExpiryDisplay.expiredText(appState.expiry) {
            out.append(NoticeLine(icon: "calendar.badge.exclamationmark", text: expired))
        } else if let left = ExpiryDisplay.daysLeftText(appState.expiry) {
            out.append(NoticeLine(icon: "calendar", text: left))
        }
        if IPv6Hint.shows(onWiFi: wifi.onWiFi, wifiHasIPv6: wifi.wifiHasIPv6, regionID: regionID,
                          ipv4Blocked: isScreenshot ? nil : RegionStore.ipv4Blocked(regionID: regionID)) {
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
            Haptics.tap()
            toggle()
        } label: {
            // Connecting: the dot still hovers and the glow breathes; it lands (and the line dips) once connected.
            LandingArt(landed: status == .connected,
                       glowing: status == .connected,
                       pulsing: status == .connecting || status == .disconnecting,
                       height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(PowerPressStyle())
        .disabled(status == .connecting || status == .disconnecting || !enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(status.isConnected ? "Disconnect" : "Connect")
    }

    private func toggle() {
        #if DEBUG
        if isScreenshot { demoToggle(); return }
        #endif
        Task { await tunnelManager.toggle() }
    }

    #if DEBUG
    /// Screenshot / demo runs (no VPN on the simulator): the states the tunnel goes through, with real-ish timing and
    /// moving numbers once connected. `-RFVFailConnect`: the start fails instead.
    private func demoToggle() {
        if tunnelManager.status.isConnected {
            tunnelManager.status = .disconnecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                tunnelManager.status = .disconnected
                statsStore.snapshot = nil
                ScreenshotMode.stageActiveRegion(connected: false)
            }
            return
        }
        tunnelManager.lastError = nil
        tunnelManager.status = .connecting
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard tunnelManager.status == .connecting else { return }
            if ScreenshotMode.failsConnect {
                tunnelManager.lastError = "Can't reach server"
                tunnelManager.status = .failed
                return
            }
            ScreenshotMode.stageActiveRegion(connected: true)
            statsStore.snapshot = ScreenshotMode.stats(now: Date(), startedAgo: 0)
            tunnelManager.status = .connected
            tickDemoNumbers()
        }
    }

    /// While the demo is connected, new speeds and pings every 1.2 s, so the figures can be seen rolling.
    private func tickDemoNumbers() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard tunnelManager.status == .connected, let snap = statsStore.snapshot else { return }
            statsStore.snapshot = ScreenshotMode.nextDemoStats(after: snap)
            tickDemoNumbers()
        }
    }
    #endif

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
                .foregroundStyle(value == HomeFormat.none ? Theme.Color.stone : Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .rollingNumber(value)
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
        // The whole block is a quiet Refresh: it gets the row highlight when pressed.
        return Button {
            guard !isScreenshot else { return }
            quotaStore.refresh(token: appState.currentProfile?.token)
        } label: {
            bandwidthBody(snap: snap, fraction: fraction)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Refresh")
    }

    private func bandwidthBody(snap: QuotaSnapshot?, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    .rollingNumber(snap?.usedGB)
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
    }

    private func ioText(_ label: String, _ value: String?) -> some View {
        (Text(label + " ").foregroundStyle(Theme.Color.stone)
            + Text(value ?? HomeFormat.none).font(Theme.Font.text(13.5, .semibold)).foregroundStyle(Theme.Color.ink))
            .font(Theme.Font.text(13.5))
            .rollingNumber(value)
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
                    feedback = nil
                    Task {
                        appState.lastActivationError = nil
                        await appState.linkApple(identityToken: token)
                        feedback = appState.appleLinked ? .success("Linked to your Apple ID")
                            : .failure(appState.lastActivationError ?? "Not linked")
                    }
                },
                onError: { message in feedback = .failure(message) }
            )
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
        Binding(get: { appState.selectedRegionID }, set: { id in
            if id != appState.selectedRegionID { Haptics.select() }
            appState.selectRegion(id)
        })
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
        .animation(Motion.numbers, value: fraction)
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
