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
///   -RFVScreenshotMode owner      owner 演示（Tokyo + Singapore，选中 Singapore，Owner Admin 带用量条和邀请的区域/期限）
///   -RFVScreenshotMode member-sg       被分配到 Singapore 的普通用户（没有选择器，Server 显示 Singapore）
///   -RFVScreenshotMode member-expired  账号已过期的普通用户（"Expired · 3 Oct 2026"，连接按钮禁用）
///   -RFVScreenshotMode member-soon     账号 5 天后到期的普通用户（"5 days left"）
///   -RFVOpenOwnerAdmin            启动后直接弹出 Owner Admin（免点击截图）
///   -RFVOpenEditInvite <序号>     Owner Admin 里直接打开第 N 个邀请的编辑页（1 起）
///   -RFVOpenCreateInvite          直接打开 Create Invite
///   -RFVHideUsage                 Owner Admin 演示不带用量
enum ScreenshotMode {
    enum Variant { case member, memberSingapore, memberExpired, memberExpiring, owner }

    static var isOn: Bool {
        ProcessInfo.processInfo.arguments.contains("-RFVScreenshotMode")
    }

    /// `-RFVScreenshotMode owner` 等选演示；不带值或其它值一律是 member。
    static var variant: Variant {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-RFVScreenshotMode"), i + 1 < args.count else { return .member }
        switch args[i + 1].lowercased() {
        case "owner":          return .owner
        case "member-sg":      return .memberSingapore
        case "member-expired": return .memberExpired
        case "member-soon":    return .memberExpiring
        default:               return .member
        }
    }

    /// 传 -RFVOpenEditInvite 3 时，Owner Admin 一出来就打开第 3 个邀请的编辑页。
    static var editInviteIndex: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-RFVOpenEditInvite"), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }

    /// 传 -RFVOnboardingShot 时停在引导页，用来截第一张图。
    static var wantsOnboardingShot: Bool {
        ProcessInfo.processInfo.arguments.contains("-RFVOnboardingShot")
    }

    static var opensOwnerAdmin: Bool {
        ProcessInfo.processInfo.arguments.contains("-RFVOpenOwnerAdmin")
    }

    /// 传 -RFVOpenCreateInvite 时启动后直接打开 Create Invite。
    static var opensCreateInvite: Bool {
        ProcessInfo.processInfo.arguments.contains("-RFVOpenCreateInvite")
    }

    /// 传 -RFVHideUsage 时 Owner Admin 演示不带用量（Usage 区自己隐藏），邀请列表就在第一屏。
    static var hidesUsage: Bool {
        ProcessInfo.processInfo.arguments.contains("-RFVHideUsage")
    }

    /// 演示用设备资料。owner 演示用第 1 台演示设备的 id，这样 Owner Admin 能认出哪个邀请是 owner 自己的。
    static var profile: DeviceProfile {
        DeviceProfile(
            profileId: variant == .owner ? "profile_demo00000001" : "profile_demo00000000",
            token: "screenshot-mode-not-a-real-token",
            ownerLabel: "Owner",
            serverRegion: variant == .memberSingapore ? "Singapore" : "Tokyo",
            configVersion: "2026-05-09.1",
            monthlyQuotaGB: 200,
            expiresAt: nil
        )
    }

    // MARK: - Regions and expiry

    static var regions: [VPNRegion] {
        switch variant {
        case .owner:           return [.tokyo, VPNRegion(id: "singapore", name: "Singapore")]
        case .memberSingapore: return [VPNRegion(id: "singapore", name: "Singapore", isDefault: true)]
        default:               return [.tokyo]
        }
    }

    static var selectedRegionID: String {
        switch variant {
        case .owner, .memberSingapore: return "singapore"
        default:                       return RegionPolicy.defaultID
        }
    }

    static var expiry: ExpiryInfo {
        switch variant {
        case .memberExpired:  return ExpiryInfo(expired: true, expiresAt: "2026-10-03T04:00:00.000Z", daysLeft: nil)
        case .memberExpiring: return ExpiryInfo(expired: false, expiresAt: "2026-10-27T04:00:00.000Z", daysLeft: 5)
        default:              return .none
        }
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
        OwnerInvite(code: "RF-DEMO-0006", label: "Dana", maxDevices: 1, activeDevices: 1,
                    monthlyQuotaGB: 200, enabled: true, expiresAt: nil, createdAt: "2026-07-30 08:00:00"),
        OwnerInvite(code: "RF-DEMO-0005", label: "Apple Review", maxDevices: 3, activeDevices: 0,
                    monthlyQuotaGB: 200, enabled: true, expiresAt: nil, createdAt: "2026-08-28 08:00:00"),
    ]

    /// 区域 + 期限：Max 是 owner 邀请（不显示 Access）；Alice 已过期；Ben 剩 29 天；Clara 激活后才开始计时；
    /// Dana 剩 6 天（琥珀色）；Apple Review 邀请不显示 Access。
    static let ownerInviteAccess: [String: InviteAccess] = [
        "RF-DEMO-0001": InviteAccess(region: "tokyo", activatedAt: "2026-05-09T01:00:00.000Z", expired: false),
        "RF-DEMO-0002": InviteAccess(region: "singapore", durationDays: 30, activatedAt: "2026-09-20T01:00:00.000Z",
                                     effectiveExpiresAt: "2026-10-20T01:00:00.000Z", expired: true),
        "RF-DEMO-0003": InviteAccess(region: "tokyo", durationDays: 30, activatedAt: "2026-10-22T01:00:00.000Z",
                                     effectiveExpiresAt: "2026-11-21T01:00:00.000Z", daysLeft: 29, expired: false),
        "RF-DEMO-0004": InviteAccess(region: "singapore", durationDays: 60, expired: false),
        "RF-DEMO-0006": InviteAccess(region: "tokyo", durationDays: 90, activatedAt: "2026-07-30T01:00:00.000Z",
                                     effectiveExpiresAt: "2026-10-28T01:00:00.000Z", daysLeft: 6, expired: false),
        "RF-DEMO-0005": InviteAccess(region: "tokyo", expired: false),
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
