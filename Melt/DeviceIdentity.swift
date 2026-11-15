import Foundation
import Security

enum DeviceIdentity {
    static func current() -> String {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "melt.device-id",
            kSecAttrAccount as String: "device",
        ]
        var found: AnyObject?
        let lookup = item.merging([kSecReturnData as String: true]) { $1 }
        if SecItemCopyMatching(lookup as CFDictionary, &found) == errSecSuccess,
           let data = found as? Data,
           let id = String(data: data, encoding: .utf8) {
            return id
        }
        let id = UUID().uuidString
        SecItemAdd(item.merging([kSecValueData as String: Data(id.utf8)]) { $1 } as CFDictionary, nil)
        return id
    }
}
