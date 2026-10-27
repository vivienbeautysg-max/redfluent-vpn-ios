#if DEBUG
import Foundation
import UIKit

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
///   -RFVScreenshotMode owner      owner 演示（Tokyo + Singapore，选中 Singapore，Owner Admin 有完整演示数据）
///   -RFVScreenshotMode member-sg       被分配到 Singapore 的普通用户
///   -RFVScreenshotMode member-expired  账号已过期的普通用户（"Expired · 3 Oct 2026"，开关禁用）
///   -RFVScreenshotMode member-soon     账号 5 天后到期的普通用户（"5 days left"）
///   -RFVScreenshotMode member-signedout  被服务器登出的设备（停在激活页，带 "Signed out"）
///   -RFVScreenshotMode activation      未激活（停在激活页，没有登出提示）
///   -RFVDisconnected              主屏未连接形态（默认是已连接）
///   -RFVIPv4OnlyWiFi              当作连在一个没有 IPv6 的 Wi-Fi 上（主屏出现那一行提示）
///   -RFVOpenOwnerAdmin            启动后直接弹出 Owner Admin
///   -RFVOwnerTab events           Owner Admin 打开在 Events 页
///   -RFVOpenPerson <名字>         Owner Admin 里直接进入这个人的个人页（Ben / Alice ...）
///   -RFVEditQuota <文字>          个人页里预填月额度输入框并滚到那里（如 48、48.5）
///   -RFVConfirmDelete             个人页里直接弹出 Delete 确认框
///   -RFVOpenDeleted               Owner Admin 里直接进入 Recently Deleted
///   -RFVOpenCreateInvite          直接打开 New invite
///   -RFVOpenDiagnostics           直接打开 Diagnostics
///   -RFVMarkedText <文字>         配 -RFVOpenCreateInvite：填好表单，Name 里留一段输入法未上屏的文字（检查所见即所存）
///   -RFVPrefillCreate             配 -RFVOpenCreateInvite：同样填好表单、键盘停在 Name，但不预先组字（UI 测试用真拼音键盘打字）
///   -RFVReduceMotion              当作系统开了「减弱动态效果」
///   -rfv.appearance dark          深色（UserDefaults 参数域，不写入设置）
enum ScreenshotMode {
    enum Variant { case member, memberSingapore, memberExpired, memberExpiring, memberSignedOut, activation, owner }

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
        case "member-signedout": return .memberSignedOut
        case "activation":     return .activation
        default:               return .member
        }
    }

    /// member-signedout / activation：不激活，直接停在激活页（前者带登出提示）。
    static var startsNotActivated: Bool { variant == .memberSignedOut || variant == .activation }
    static var startsSignedOut: Bool { variant == .memberSignedOut }

    private static func has(_ flag: String) -> Bool { ProcessInfo.processInfo.arguments.contains(flag) }

    private static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var startsDisconnected: Bool { has("-RFVDisconnected") }
    static var ipv4OnlyWiFi: Bool { has("-RFVIPv4OnlyWiFi") }
    static var opensEvents: Bool { value(after: "-RFVOwnerTab")?.lowercased() == "events" }
    static var openPerson: String? { value(after: "-RFVOpenPerson") }
    static var editQuota: String? { value(after: "-RFVEditQuota") }
    static var confirmsDelete: Bool { has("-RFVConfirmDelete") }
    static var opensDeleted: Bool { has("-RFVOpenDeleted") }
    static var opensDiagnostics: Bool { has("-RFVOpenDiagnostics") }
    /// 传 -RFVOnboardingShot 时停在引导页，用来截第一张图。
    static var wantsOnboardingShot: Bool { has("-RFVOnboardingShot") }
    static var opensOwnerAdmin: Bool { has("-RFVOpenOwnerAdmin") }
    static var opensCreateInvite: Bool { has("-RFVOpenCreateInvite") }

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

    /// Clara 是暂停的（enabled = false），用来截 Paused 的样子。
    static let ownerInvites: [OwnerInvite] = [
        OwnerInvite(code: "RF-DEMO-0001", label: "Max", maxDevices: 6, activeDevices: 2,
                    monthlyQuotaGB: 1000, enabled: true, expiresAt: nil, createdAt: "2026-05-09 08:00:00"),
        OwnerInvite(code: "RF-DEMO-0002", label: "Alice", maxDevices: 3, activeDevices: 2,
                    monthlyQuotaGB: 200, enabled: true, expiresAt: nil, createdAt: "2026-06-01 08:00:00"),
        OwnerInvite(code: "RF-DEMO-0003", label: "Ben", maxDevices: 3, activeDevices: 2,
                    monthlyQuotaGB: 200, enabled: true, expiresAt: nil, createdAt: "2026-06-12 08:00:00"),
        OwnerInvite(code: "RF-DEMO-0004", label: "Clara", maxDevices: 2, activeDevices: 1,
                    monthlyQuotaGB: 200, enabled: false, expiresAt: nil, createdAt: "2026-07-03 08:00:00"),
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

    /// 演示用 IPv6 入口：RFC 3849 文档专用前缀 2001:db8::/32 里编的地址，不是任何真实服务器（仓库源码是公开的）。
    private static let sharedEntry = "2001:db8:1000:5bd7:b463:af04:5e51:58ef"
    private static let ownEntryMax = "2001:db8:1000:5bd7:51e5:d2bf:4175:4529"
    private static let ownEntryBen = "2001:db8:1000:5bd7:9c1e:42aa:7d3:be10"

    private static func device(_ n: Int, invite: Int, label: String, name: String,
                               model: String, app: String, online: Bool = false,
                               enabled: Bool = true, ipv6: String? = nil, dedicated: Bool = false) -> OwnerDevice {
        OwnerDevice(
            profileId: "profile_demo\(String(format: "%08d", n))",
            inviteCode: "RF-DEMO-000\(invite)",
            inviteLabel: label,
            displayName: name,
            deviceName: model,
            appVersion: app,
            ownerLabel: label,
            enabled: enabled,
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
            revokedAt: enabled ? nil : "2026-10-12 08:00:00",
            ipv6Entry: ipv6,
            ipv6EntryDedicated: ipv6 == nil ? nil : dedicated
        )
    }

    /// 6 个人 / 9 台设备：Max（owner）和 Alice 在线；Ben 三台设备分别是专属 IPv6、共用 IPv6（已登出）、只有 IPv4；
    /// Singapore 的 Alice / Clara 没有 IPv6 入口；Dana 从没用过。
    static let ownerDevices: [OwnerDevice] = [
        device(1, invite: 1, label: "Max", name: "Max iPhone", model: "iPhone 17 Pro Max", app: "1.2 (43)", online: true,
               ipv6: ownEntryMax, dedicated: true),
        device(2, invite: 1, label: "Max", name: "Max Desktop", model: "DESKTOP-DEMO", app: "0.1.0", ipv6: sharedEntry),
        device(3, invite: 2, label: "Alice", name: "Alice iPhone", model: "iPhone 15", app: "1.0 (39)", online: true),
        device(4, invite: 2, label: "Alice", name: "Alice iPad", model: "iPad Air", app: "1.0 (34)"),
        device(5, invite: 3, label: "Ben", name: "Ben iPhone", model: "iPhone 16", app: "1.2 (43)",
               ipv6: ownEntryBen, dedicated: true),
        device(6, invite: 3, label: "Ben", name: "Ben iPad", model: "iPad mini", app: "1.1 (41)", enabled: false,
               ipv6: sharedEntry),
        device(7, invite: 4, label: "Clara", name: "Clara iPhone", model: "iPhone 14", app: "1.0 (39)"),
        device(8, invite: 6, label: "Dana", name: "Dana iPhone", model: "iPhone 13", app: "1.1 (41)", ipv6: sharedEntry),
        device(9, invite: 3, label: "Ben", name: "Ben Mac", model: "MacBook Air", app: "1.2 (43)"),
    ]

    /// Recently Deleted：两个人，3 天前和 12 天前删除。
    static func ownerDeleted(now: Date = Date()) -> [DeletedInvite] {
        let formatter = ISO8601DateFormatter()
        return [
            DeletedInvite(code: "RF-DEMO-0007", label: "Evan",
                          deletedAt: formatter.string(from: now.addingTimeInterval(-3 * 86_400)),
                          maxDevices: 2, monthlyQuotaGB: 100, region: "tokyo", deviceCount: 1),
            DeletedInvite(code: "RF-DEMO-0008", label: "Fiona",
                          deletedAt: formatter.string(from: now.addingTimeInterval(-12 * 86_400)),
                          maxDevices: 1, monthlyQuotaGB: 50, region: "singapore", deviceCount: 0),
        ]
    }

    /// Events 页：一次成功、两次失败（编的邀请码）。
    static let ownerEvents: [OwnerActivationEvent] = [
        OwnerActivationEvent(id: "e1", inviteCodeInput: "RF-DEMO-0003", inviteCodeNormalized: "RF-DEMO-0003",
                             matchedInviteCode: "RF-DEMO-0003", devicePublicId: nil, deviceName: "Ben Mac",
                             appVersion: "1.2 (43)", outcome: "success", reason: "activated", httpStatus: 200,
                             profileId: nil, activeDevices: 2, maxDevices: 3, remoteIp: "203.0.113.24", userAgent: nil,
                             createdAt: "2026-10-27 06:12:00", createdAtSgt: "2026-10-27 14:12:00 SGT"),
        OwnerActivationEvent(id: "e2", inviteCodeInput: "rf-demo-0004", inviteCodeNormalized: "RF-DEMO-0004",
                             matchedInviteCode: "RF-DEMO-0004", devicePublicId: nil, deviceName: "Clara iPad",
                             appVersion: "1.2 (43)", outcome: "failed", reason: "invite disabled", httpStatus: 403,
                             profileId: nil, activeDevices: 1, maxDevices: 2, remoteIp: "198.51.100.7", userAgent: nil,
                             createdAt: "2026-10-26 11:40:00", createdAtSgt: "2026-10-26 19:40:00 SGT"),
        OwnerActivationEvent(id: "e3", inviteCodeInput: "RF-DEMO-9999", inviteCodeNormalized: "RF-DEMO-9999",
                             matchedInviteCode: nil, devicePublicId: nil, deviceName: "iPhone",
                             appVersion: "1.1 (41)", outcome: "failed", reason: "invalid invite", httpStatus: 403,
                             profileId: nil, activeDevices: nil, maxDevices: nil, remoteIp: "192.0.2.55", userAgent: nil,
                             createdAt: "2026-10-25 02:03:00", createdAtSgt: "2026-10-25 10:03:00 SGT"),
    ]

    /// 各设备最近一次真实流量，相对于现在，这样截图里永远是「2h ago」这类说法。Dana 的是 null = Never。
    static func ownerLastUsed(now: Date = Date()) -> [String: DeviceLastUsed] {
        let formatter = ISO8601DateFormatter()
        func ago(_ seconds: TimeInterval) -> DeviceLastUsed {
            DeviceLastUsed(iso: formatter.string(from: now.addingTimeInterval(-seconds)))
        }
        return [
            "profile_demo00000001": ago(20),
            "profile_demo00000002": ago(26 * 3_600),
            "profile_demo00000003": ago(20),
            "profile_demo00000004": ago(2 * 86_400),
            "profile_demo00000005": ago(2 * 3_600),
            "profile_demo00000006": ago(9 * 86_400),
            "profile_demo00000007": ago(4 * 86_400),
            "profile_demo00000008": DeviceLastUsed(iso: nil),
            "profile_demo00000009": ago(5 * 3_600),
        ]
    }

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
        "profile_demo00000008": usage(0, 200),
        "profile_demo00000009": usage(18.5, 200),
    ]

    static let ownerPeriod = UsagePeriod(start: "2026-10-01T00:00:00.000Z", end: "2026-11-01T00:00:00.000Z")

    /// `-RFVFailConnect`: the demo Connect fails ("Can't reach server") instead of connecting.
    static var failsConnect: Bool { has("-RFVFailConnect") }

    /// The next reading while the demo is connected: speeds and ping move a little, totals grow.
    static func nextDemoStats(after s: StatsSnapshot) -> StatsSnapshot {
        let down = Int64.random(in: 3_200_000...14_800_000)
        let up = Int64.random(in: 600_000...2_900_000)
        return StatsSnapshot(
            timestamp: Date(),
            connected: true,
            connectionStartedAt: s.connectionStartedAt,
            uplinkBps: up,
            downlinkBps: down,
            totalUp: s.totalUp + up,
            totalDown: s.totalDown + down,
            activeConnections: s.activeConnections,
            proxyConnections: s.proxyConnections,
            directConnections: s.directConnections,
            pingMs: Int.random(in: 31...58)
        )
    }

    static func stats(now: Date, startedAgo: TimeInterval = 3_720) -> StatsSnapshot {
        StatsSnapshot(
            timestamp: now,
            connected: true,
            connectionStartedAt: now.addingTimeInterval(-startedAgo),
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

/// Fake owner API for screenshot / demo runs: nothing leaves the simulator. It answers like the server, refusals
/// included (a code that is already in use -> 409 "invite code already exists"), after a short wait so the busy
/// state shows.
enum DemoAPI {
    static let duplicateCode = APIError.status(409, #"{"ok":false,"error":"invite code already exists"}"#)

    private static func wait() async { try? await Task.sleep(nanoseconds: 700_000_000) }

    private static func string(_ value: JSONValue?) -> String? {
        if case .string(let s) = value { return s } else { return nil }
    }

    private static func int(_ value: JSONValue?) -> Int? {
        if case .int(let i) = value { return i } else { return nil }
    }

    private static func taken(_ code: String, in codes: [String]) -> Bool {
        codes.contains { $0.caseInsensitiveCompare(code) == .orderedSame }
    }

    static func createInvite(body: [String: JSONValue], existing: [String]) async throws -> CreatedInvite {
        await wait()
        let code = string(body["code"]) ?? ""
        if taken(code, in: existing) { throw duplicateCode }
        return CreatedInvite(code: code, label: string(body["label"]) ?? "", maxDevices: int(body["maxDevices"]) ?? 1,
                             monthlyQuotaGB: int(body["monthlyQuotaGB"]) ?? 200, enabled: true, expiresAt: nil)
    }

    static func updateInvite(body: [String: JSONValue], invites: [OwnerInvite]) async throws -> OwnerInvite {
        await wait()
        let code = string(body["code"]) ?? ""
        let newCode = string(body["newCode"]) ?? code
        guard let old = invites.first(where: { $0.code == code }) else { throw APIError.status(404, #"{"ok":false,"error":"invite not found"}"#) }
        if newCode.caseInsensitiveCompare(code) != .orderedSame,
           taken(newCode, in: invites.map(\.code)) { throw duplicateCode }
        var enabled = old.enabled
        if case .bool(let b) = body["enabled"] { enabled = b }
        return OwnerInvite(code: newCode, label: string(body["label"]) ?? old.label,
                           maxDevices: int(body["maxDevices"]) ?? old.maxDevices, activeDevices: old.activeDevices,
                           monthlyQuotaGB: int(body["monthlyQuotaGB"]) ?? old.monthlyQuotaGB, enabled: enabled,
                           expiresAt: old.expiresAt, createdAt: old.createdAt)
    }

    /// Delete, restore, log out, rename: accepted.
    static func accept() async { await wait() }
}

extension ScreenshotMode {
    /// `-RFVMarkedText <text>` (with -RFVOpenCreateInvite): the form is filled in, the keyboard is on Name, and
    /// <text> is left there as marked text, the way a pinyin keyboard holds a letter it has not turned into a
    /// character yet.
    static var markedText: String? { value(after: "-RFVMarkedText") }
    /// `-RFVPrefillCreate` (with -RFVOpenCreateInvite): the same form, the keyboard on Name, nothing composed yet; a
    /// UI test then types through the simulator's own Pinyin keyboard, so the composing text is the IME's.
    static var prefillsCreate: Bool { ProcessInfo.processInfo.arguments.contains("-RFVPrefillCreate") }
    static let markedFormCode = "RF-DEMO-0100"
    static let markedFormLabel = "\u{5F20}\u{4E09}"   // 张三
}

extension ScreenshotMode {
    /// Finds the text field showing `text`, gives it the keyboard and appends `marked` as marked text.
    @MainActor
    static func compose(_ marked: String, inFieldShowing text: String) {
        func field(in view: UIView) -> UITextField? {
            if let f = view as? UITextField, f.text == text { return f }
            for sub in view.subviews { if let f = field(in: sub) { return f } }
            return nil
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let target = windows.lazy.compactMap({ field(in: $0) }).first else { return }
        target.becomeFirstResponder()
        let end = target.endOfDocument
        target.selectedTextRange = target.textRange(from: end, to: end)
        guard !marked.isEmpty else { return }   // -RFVPrefillCreate: the test types through the real keyboard
        target.setMarkedText(marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0))
    }
}

extension ScreenshotMode {
    /// Connected shots: the region a running tunnel would report (the home screen reads it from the App Group);
    /// disconnected shots: none. Written on every launch so one run never leaks into the next.
    static func stageActiveRegion(connected: Bool) {
        let defaults = RegionStore.sharedDefaults()
        guard connected, let region = regions.first(where: { RegionPolicy.matches($0.id, selectedRegionID) }) else {
            defaults?.removeObject(forKey: RegionStore.activeKey)
            return
        }
        defaults?.set(["id": region.id, "name": region.name], forKey: RegionStore.activeKey)
    }
}
#endif
