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

    init() {
        if let stored = ProfileStore.load() {
            activation = .activated(stored)
        }
    }

    var currentProfile: DeviceProfile? {
        if case .activated(let p) = activation { return p } else { return nil }
    }

    func redeem(inviteCode: String) async {
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
