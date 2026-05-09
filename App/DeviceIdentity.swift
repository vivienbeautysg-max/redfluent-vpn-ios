import Foundation
import UIKit

enum DeviceIdentity {
    private static let publicIdKey = "rfv.devicePublicId"

    static var publicId: String {
        if let existing = UserDefaults.standard.string(forKey: publicIdKey) {
            return existing
        }
        let new = UUID().uuidString.lowercased()
        UserDefaults.standard.set(new, forKey: publicIdKey)
        return new
    }

    static var deviceName: String {
        UIDevice.current.name
    }

    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
