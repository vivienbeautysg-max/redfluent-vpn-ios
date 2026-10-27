import Foundation
import Security

/// The device profile (Keychain). Also the only place that keeps the tunnel's copy of the device token
/// (DeviceTokenMirror) in step: every save writes it, every clear removes it.
enum ProfileStore {
    private static let service = "com.redfluent.vpn.profile"
    private static let account = "deviceProfile"

    static func save(_ profile: DeviceProfile) throws {
        let data = try JSONEncoder().encode(profile)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            DeviceTokenMirror.clear()   // the old profile was deleted above, so its token goes too
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        DeviceTokenMirror.write(profile.token)
    }

    /// At launch: give the tunnel the stored token (an app updated from 1.2 has no copy until it runs once).
    static func syncTokenMirror() {
        if let profile = load() { DeviceTokenMirror.write(profile.token) }
    }

    static func load() -> DeviceProfile? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(DeviceProfile.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        DeviceTokenMirror.clear()
    }
}
