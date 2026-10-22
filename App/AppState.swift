import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum ActivationState: Equatable {
        case notActivated
        case activating
        case activated(DeviceProfile)
        case error(String)
    }

    @Published var activation: ActivationState = .notActivated
    @Published var lastActivationError: String?
    /// Regions the server offers this device (Tokyo only unless the backend says more) and the chosen one.
    @Published private(set) var regions: [VPNRegion] = [.tokyo]
    @Published private(set) var selectedRegionID: String = RegionPolicy.defaultID
    /// Account expiry from the last /profile (1.2 backends): drives the Expired state on the dashboard.
    @Published private(set) var expiry: ExpiryInfo = .none
    /// The server signed this device out: the activation screen shows a short notice until the next activation.
    @Published private(set) var signedOut = false
    /// Owner Admin: is the Invites section open? Collapsed by default, remembered while the app runs.
    @Published var ownerInvitesExpanded = false

    private let api = APIClient.shared

    /// 已经把邀请码绑到 Apple ID 了吗（本机视角）。用来决定要不要提示绑定。
    @Published var appleLinked: Bool = UserDefaults.standard.bool(forKey: "rfv.appleLinked")

    init() {
        regions = RegionStore.offered()
        selectedRegionID = RegionPolicy.resolveSelection(stored: RegionStore.selectedID(), offered: regions)
        expiry = ExpiryStore.load()
        #if DEBUG
        if ScreenshotMode.isOn {
            activation = ScreenshotMode.startsSignedOut ? .notActivated : .activated(ScreenshotMode.profile)
            signedOut = ScreenshotMode.startsSignedOut
            appleLinked = true          // 截图里不出现绑定卡片
            regions = ScreenshotMode.regions
            selectedRegionID = ScreenshotMode.selectedRegionID
            expiry = ScreenshotMode.expiry
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

    /// Adopt the region list from /profile. A selection the server no longer offers falls back to the
    /// server's default region (else the first one), so the picker always has a selection.
    func applyOfferedRegions(_ offered: [VPNRegion]) {
        let offered = RegionPolicy.offered(from: offered)
        regions = offered
        RegionStore.saveOffered(offered)
        let resolved = RegionPolicy.resolveSelection(stored: selectedRegionID, offered: offered)
        if resolved != selectedRegionID {
            selectedRegionID = resolved
            RegionStore.saveSelected(resolved)
        }
    }

    func selectRegion(_ id: String) {
        guard let region = regions.first(where: { RegionPolicy.matches($0.id, id) }),
              region.id != selectedRegionID else { return }
        selectedRegionID = region.id
        RegionStore.saveSelected(region.id)
    }

    /// Region name for the Server row: what the tunnel really started with while connected ("—" when
    /// that is unknown), otherwise the selection. A single-region device keeps showing its profile's region.
    func serverDisplayName(connected: Bool) -> String? {
        RegionPolicy.serverDisplayName(
            regions: regions, selectedID: selectedRegionID, connected: connected,
            active: RegionStore.active(), profileRegion: currentProfile?.serverRegion)
    }

    /// Back to Tokyo only (sign-out / revoked): the next activation may be a different invite.
    private func resetRegions() {
        applyOfferedRegions([.tokyo])
        applyExpiry(.none)
    }

    private func applyExpiry(_ info: ExpiryInfo) {
        guard info != expiry else { return }
        expiry = info
        ExpiryStore.save(info)
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
            signedOut = false
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
            signedOut = false
            activation = .activated(profile)
        } catch {
            lastActivationError = error.localizedDescription
            activation = .error(error.localizedDescription)
        }
    }

    /// Asks /profile. True when it answered, i.e. what the state now says is current.
    @discardableResult
    func refresh() async -> Bool {
        #if DEBUG
        if ScreenshotMode.isOn { return false }   // 演示资料不该被真实后端覆盖
        #endif
        guard case .activated(let profile) = activation else { return false }
        do {
            let status = try await api.fetchProfile(token: profile.token)
            if !status.enabled {
                // The server signed this device out (Log out / revoke): back to the activation screen with a short
                // notice. The invite code stays valid; entering it again re-activates.
                ProfileStore.clear()
                resetRegions()
                signedOut = true
                activation = .notActivated
            } else {
                applyOfferedRegions(status.regions)
                applyExpiry(ExpiryInfo(expired: status.expired, expiresAt: status.expiresAt, daysLeft: status.daysLeft))
                // Not revoked and not expired: lift a server stop the tunnel left behind, so it may start on its own again.
                if !status.expired, TunnelStartError.readStandingStop() != nil { TunnelStartError.clear() }
            }
            return true
        } catch {
            // Network failure during refresh is non-fatal — we keep the cached profile.
            // Don't downgrade activation just because we lost connectivity.
            return false
        }
    }

    func signOut() {
        ProfileStore.clear()
        resetRegions()
        signedOut = false
        activation = .notActivated
        lastActivationError = nil
    }
}
