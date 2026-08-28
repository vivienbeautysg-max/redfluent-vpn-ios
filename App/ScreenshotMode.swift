#if DEBUG
import Foundation

/// App Store 截图模式。
///
/// 用固定的演示数据渲染**真实的界面代码** —— 页面本身一行没改，
/// 所以截出来的就是用户真正看到的样子，只是数据是编的。
/// 不联网、不激活真设备、不写 Keychain，也不会在生产库里留下任何记录。
///
/// 整个文件被 #if DEBUG 包住：Release / App Store 构建里这些代码根本不存在。
enum ScreenshotMode {
    static var isOn: Bool {
        ProcessInfo.processInfo.arguments.contains("-RFVScreenshotMode")
    }

    /// 传 -RFVOnboardingShot 时停在引导页，用来截第一张图。
    static var wantsOnboardingShot: Bool {
        ProcessInfo.processInfo.arguments.contains("-RFVOnboardingShot")
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
