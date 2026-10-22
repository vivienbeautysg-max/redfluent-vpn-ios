#if DEBUG
import Foundation

/// App Store 截图模式。
///
/// 用固定的演示数据渲染**真实的界面代码** —— 页面本身一行没改，
/// 所以截出来的就是用户真正看到的样子，只是数据是编的。
/// 不联网、不激活真设备、不写 Keychain，也不会在生产库里留下任何记录。
///
/// 整个文件被 #if DEBUG 包住：Release / App Store 构建里这些代码根本不存在。
///
/// 启动参数：
///   -RFVScreenshotMode            非 owner 演示（只有 Tokyo，没有区域选择器）
///   -RFVScreenshotMode member     同上
///   -RFVScreenshotMode owner      owner 演示（Tokyo + Singapore，选中 Singapore，Owner Admin 带用量条）
///   -RFVOpenOwnerAdmin            启动后直接弹出 Owner Admin（免点击截图）
enum ScreenshotMode {
    enum Variant { case member, owner }

    static var isOn: Bool {
        ProcessInfo.processInfo.arguments.contains("-RFVScreenshotMode")
    }

    /// `-RFVScreenshotMode owner` 选 owner 演示；不带值或其它值一律是 member。
    static var variant: Variant {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-RFVScreenshotMode"), i + 1 < args.count else { return .member }
        return args[i + 1].lowercased() == "owner" ? .owner : .member
    }

    /// 传 -RFVOnboardingShot 时停在引导页，用来截第一张图。
    static var wantsOnboardingShot: Bool {
        ProcessInfo.processInfo.arguments.contains("-RFVOnboardingShot")
    }

    static var opensOwnerAdmin: Bool {
        ProcessInfo.processInfo.arguments.contains("-RFVOpenOwnerAdmin")
    }

    static let profile = DeviceProfile(
        profileId: "profile_demo00000000",
        token: "screenshot-mode-not-a-real-token",
        ownerLabel: "Owner",
        serverRegion: "Tokyo",
        configVersion: "2026-05-09.1",
        monthlyQuotaGB: 200,
        expiresAt: nil
    )

    // MARK: - Regions

    static var regions: [VPNRegion] {
        variant == .owner ? [.tokyo, VPNRegion(id: "singapore", name: "Singapore")] : [.tokyo]
    }

    static var selectedRegionID: String {
        variant == .owner ? "singapore" : RegionPolicy.defaultID
    }

    // MARK: - Owner Admin demo (fake labels and codes)

    static let ownerInvites: [OwnerInvite] = [
        OwnerInvite(code: "RF-DEMO-0001", label: "Max", maxDevices: 6, activeDevices: 2,
                    monthlyQuotaGB: 1000, enabled: true, expiresAt: nil, createdAt: "2026-05-09 08:00:00"),
        OwnerInvite(code: "RF-DEMO-0002", label: "Alice", maxDevices: 3, activeDevices: 2,
                    monthlyQuotaGB: 200, enabled: true, expiresAt: nil, createdAt: "2026-06-01 08:00:00"),
        OwnerInvite(code: "RF-DEMO-0003", label: "Ben", maxDevices: 3, activeDevices: 2,
                    monthlyQuotaGB: 200, enabled: true, expiresAt: nil, createdAt: "2026-06-12 08:00:00"),
        OwnerInvite(code: "RF-DEMO-0004", label: "Clara", maxDevices: 2, activeDevices: 1,
                    monthlyQuotaGB: 200, enabled: true, expiresAt: nil, createdAt: "2026-07-03 08:00:00"),
    ]

    private static func device(_ n: Int, invite: Int, label: String, name: String,
                               model: String, app: String, online: Bool = false) -> OwnerDevice {
        OwnerDevice(
            profileId: "profile_demo\(String(format: "%08d", n))",
            inviteCode: "RF-DEMO-000\(invite)",
            inviteLabel: label,
            displayName: name,
            deviceName: model,
            appVersion: app,
            ownerLabel: label,
            enabled: true,
            connected: online,
            inUse: online,
            online: online,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastConnectedAt: nil,
            lastDisconnectedAt: nil,
            lastActiveConnections: nil,
            lastTotalUp: nil,
            lastTotalDown: nil,
            createdAt: "2026-06-01 08:00:00",
            revokedAt: nil
        )
    }

    /// 4 个用户 / 7 台设备，用量从 11% 到 94%，其中一台超过 90%，一台没有配额。
    static let ownerDevices: [OwnerDevice] = [
        device(1, invite: 1, label: "Max", name: "Max iPhone", model: "iPhone 17 Pro Max", app: "1.1 (41)", online: true),
        device(2, invite: 1, label: "Max", name: "Max Desktop", model: "DESKTOP-DEMO", app: "0.1.0"),
        device(3, invite: 2, label: "Alice", name: "Alice iPhone", model: "iPhone 15", app: "1.0 (39)", online: true),
        device(4, invite: 2, label: "Alice", name: "Alice iPad", model: "iPad Air", app: "1.0 (34)"),
        device(5, invite: 3, label: "Ben", name: "Ben iPhone", model: "iPhone 16", app: "1.1 (41)"),
        device(6, invite: 3, label: "Ben", name: "Ben iPad", model: "iPad mini", app: "1.1 (41)"),
        device(7, invite: 4, label: "Clara", name: "Clara iPhone", model: "iPhone 14", app: "1.0 (39)"),
    ]

    private static func usage(_ used: Double, _ quota: Double?) -> DeviceUsage {
        DeviceUsage(
            usedGB: used,
            quotaGB: quota,
            percent: quota.map { (used / $0 * 1000).rounded() / 10 },
            uploadGB: (used * 0.15 * 100).rounded() / 100,
            downloadGB: (used * 0.85 * 100).rounded() / 100
        )
    }

    static let ownerUsage: [String: DeviceUsage] = [
        "profile_demo00000001": usage(312.4, 1000),
        "profile_demo00000002": usage(148.9, nil),
        "profile_demo00000003": usage(187.6, 200),
        "profile_demo00000004": usage(41.2, 200),
        "profile_demo00000005": usage(142.3, 200),
        "profile_demo00000006": usage(22.7, 200),
        "profile_demo00000007": usage(96.0, 200),
    ]

    static let ownerPeriod = UsagePeriod(start: "2026-10-01T00:00:00.000Z", end: "2026-11-01T00:00:00.000Z")

    static func stats(now: Date) -> StatsSnapshot {
        StatsSnapshot(
            timestamp: now,
            connected: true,
            connectionStartedAt: now.addingTimeInterval(-3_720),
            uplinkBps: 1_840_000,
            downlinkBps: 9_620_000,
            totalUp: 486_000_000,
            totalDown: 2_640_000_000,
            activeConnections: 14,
            proxyConnections: 12,
            directConnections: 2,
            pingMs: 38
        )
    }

    static func quota(now: Date) -> QuotaSnapshot {
        QuotaSnapshot(
            monthlyQuotaGB: 200,
            usedGB: 63.4,
            usedBytes: 68_071_000_000,
            remainingGB: 136.6,
            percentUsed: 31.7,
            daysUntilReset: 12,
            billingPeriodStart: "2026-08-01",
            billingPeriodEnd: "2026-08-31",
            incomingBytes: 2_640_000_000,
            outgoingBytes: 486_000_000,
            fetchedAt: now
        )
    }
}
#endif
