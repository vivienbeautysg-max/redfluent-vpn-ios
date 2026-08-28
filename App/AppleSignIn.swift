import SwiftUI
import AuthenticationServices

extension DeviceProfile {
    /// 滑动续期只换 token，其余资料原样保留。
    func withToken(_ newToken: String) -> DeviceProfile {
        DeviceProfile(
            profileId: profileId,
            token: newToken,
            ownerLabel: ownerLabel,
            serverRegion: serverRegion,
            configVersion: configVersion,
            monthlyQuotaGB: monthlyQuotaGB,
            expiresAt: expiresAt
        )
    }
}

/// 「用 Apple ID 恢复」按钮。
/// 只取 identity token，不要姓名和邮箱 —— 这个 app 不需要知道你是谁，
/// 只需要认出「还是同一个人」，好把原来那个邀请码还给你。
struct AppleRecoverButton: View {
    /// 卡片是浅色底吗。Apple 的规范：浅底配黑按钮、深底配白按钮。
    var onLightBackground: Bool = true
    var onToken: (String) -> Void
    var onError: (String) -> Void

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = []
        } onCompletion: { result in
            switch result {
            case .success(let auth):
                guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                      let data = credential.identityToken,
                      let token = String(data: data, encoding: .utf8)
                else {
                    onError("Apple 没有返回身份凭证，请再试一次")
                    return
                }
                onToken(token)
            case .failure(let error):
                // 用户自己取消不是错误，不要弹提示打扰他。
                if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
                onError(error.localizedDescription)
            }
        }
        .signInWithAppleButtonStyle(onLightBackground ? .black : .white)
        .frame(height: 46)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}
