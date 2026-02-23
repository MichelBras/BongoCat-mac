import Foundation
import Security

/// Single source of truth for the persistent device identifier used across all subsystems
/// (analytics, backend sync, etc.).
///
/// Storage strategy:
/// - Primary: Keychain (encrypted, survives app reinstall if iCloud Keychain is on)
/// - Fallback: UserDefaults (migrates to Keychain automatically on first read)
enum DeviceIdentity {
    private static let udKey = "BongoCatDeviceId"
    private static let kcService = "com.leaptech.bongocat"
    private static let kcAccount = "BongoCatDeviceId"

    static var deviceId: String {
        // 1. Try Keychain
        if let existing = keychainRead() {
            return existing
        }
        // 2. Migrate from UserDefaults if present
        if let legacy = UserDefaults.standard.string(forKey: udKey) {
            keychainWrite(legacy)
            return legacy
        }
        // 3. Generate fresh UUID
        let newId = UUID().uuidString
        keychainWrite(newId)
        UserDefaults.standard.set(newId, forKey: udKey) // keep in sync for legacy readers
        return newId
    }

    // MARK: - Private Keychain helpers

    private static func keychainRead() -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      kcService,
            kSecAttrAccount:      kcAccount,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainWrite(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        // Delete stale entry first
        let delete: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: kcService,
            kSecAttrAccount: kcAccount
        ]
        SecItemDelete(delete as CFDictionary)

        let add: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      kcService,
            kSecAttrAccount:      kcAccount,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(add as CFDictionary, nil)
    }
}
