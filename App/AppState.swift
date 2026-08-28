import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum ActivationState: Equatable {
        case notActivated
        case activating
        case activated(DeviceProfile)
        case revoked
        case error(String)
    }

    @Published var activation: ActivationState = .notActivated
    @Published var lastActivationError: String?

    private let api = APIClient.shared

    /// 已经把邀请码绑到 Apple ID 了吗（本机视角）。用来决定要不要提示绑定。
    @Published var appleLinked: Bool = UserDefaults.standard.bool(forKey: "rfv.appleLinked")

    init() {
        #if DEBUG
        if ScreenshotMode.isOn {
            activation = .activated(ScreenshotMode.profile)
            appleLinked = true          // 截图里不出现绑定卡片
            return
        }
        #endif
        if let stored = ProfileStore.load() {
            activation = .activated(stored)
        }
        // 后端会在 token 快过期时顺带发回新的，这里静默换掉。
        // 用户不该因为「90 天没打开过」就被登出。
        Task { [weak self] in
            await APIClient.shared.setTokenRenewalHandler { newToken in
                await self?.applyRenewedToken(newToken)
            }
        }
    }

    /// 用续期得到的新 token 替换掉旧的，其余资料不动。
    func applyRenewedToken(_ newToken: String) {
        guard case .activated(let profile) = activation, profile.token != newToken else { return }
        let updated = profile.withToken(newToken)
        try? ProfileStore.save(updated)
        activation = .activated(updated)
    }

    /// 把当前邀请码绑到 Apple ID。失败不影响已经能用的 VPN，只是没绑上。
    func linkApple(identityToken: String) async {
        guard case .activated(let profile) = activation else { return }
        do {
            try await api.linkApple(identityToken: identityToken, token: profile.token)
            appleLinked = true
            UserDefaults.standard.set(true, forKey: "rfv.appleLinked")
        } catch {
            lastActivationError = error.localizedDescription
        }
    }

    /// 换机 / 重装：不输邀请码，直接用 Apple ID 找回。
    func recoverWithApple(identityToken: String) async {
        activation = .activating
        lastActivationError = nil
        do {
            let profile = try await api.authApple(
                identityToken: identityToken,
                devicePublicId: DeviceIdentity.publicId,
                deviceName: DeviceIdentity.deviceName,
                appVersion: DeviceIdentity.appVersion
            )
            try ProfileStore.save(profile)
            activation = .activated(profile)
            appleLinked = true
            UserDefaults.standard.set(true, forKey: "rfv.appleLinked")
        } catch {
            lastActivationError = error.localizedDescription
            // 回到「可以再试」的状态，而不是 .error —— 多半只是这个 Apple ID 没绑过，
            // 用户下一步该做的是改用邀请码，而不是盯着一个红色错误屏。
            activation = .notActivated
        }
    }

    var currentProfile: DeviceProfile? {
        if case .activated(let p) = activation { return p } else { return nil }
    }

    func redeem(inviteCode: String) async {
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastActivationError = "Invite code is empty"
            return
        }
        activation = .activating
        lastActivationError = nil
        do {
            let profile = try await api.redeemInvite(
                code: trimmed,
                devicePublicId: DeviceIdentity.publicId,
                deviceName: DeviceIdentity.deviceName,
                appVersion: DeviceIdentity.appVersion
            )
            try ProfileStore.save(profile)
            activation = .activated(profile)
        } catch {
            lastActivationError = error.localizedDescription
            activation = .error(error.localizedDescription)
        }
    }

    func refresh() async {
        #if DEBUG
        if ScreenshotMode.isOn { return }   // 演示资料不该被真实后端覆盖
        #endif
        guard case .activated(let profile) = activation else { return }
        do {
            let status = try await api.fetchProfile(token: profile.token)
            if !status.enabled {
                ProfileStore.clear()
                activation = .revoked
            }
        } catch {
            // Network failure during refresh is non-fatal — we keep the cached profile.
            // Don't downgrade activation just because we lost connectivity.
        }
    }

    func signOut() {
        ProfileStore.clear()
        activation = .notActivated
        lastActivationError = nil
    }
}
