import Testing
import Foundation
import Security
@testable import BongoCat

@Suite("DeviceIdentity")
struct DeviceIdentityTests {

    private let udKey = "BongoCatDeviceId"
    private let kcService = "com.leaptech.bongocat"
    private let kcAccount = "BongoCatDeviceId"

    // MARK: - Helpers

    private func clearAll() {
        UserDefaults.standard.removeObject(forKey: udKey)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: kcService,
            kSecAttrAccount: kcAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func keychainRead() -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: kcService,
            kSecAttrAccount: kcAccount,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Tests

    @Test("generates a valid UUID when no ID exists")
    func test_deviceId_whenNoStoredId_generatesValidUUID() {
        clearAll()
        defer { clearAll() }

        let id = DeviceIdentity.deviceId

        #expect(UUID(uuidString: id) != nil)
    }

    @Test("persists the generated ID in the Keychain")
    func test_deviceId_whenFirstCall_storesInKeychain() {
        clearAll()
        defer { clearAll() }

        let id = DeviceIdentity.deviceId

        #expect(keychainRead() == id)
    }

    @Test("returns the same ID on repeated calls")
    func test_deviceId_whenCalledMultipleTimes_returnsSameId() {
        clearAll()
        defer { clearAll() }

        let first  = DeviceIdentity.deviceId
        let second = DeviceIdentity.deviceId
        let third  = DeviceIdentity.deviceId

        #expect(first == second)
        #expect(second == third)
    }

    @Test("migrates a legacy UserDefaults ID to the Keychain")
    func test_deviceId_whenLegacyUserDefaultsId_migratesAndReturnsIt() {
        clearAll()
        defer { clearAll() }

        let legacyId = "LEGACY00-0000-0000-0000-000000000000"
        UserDefaults.standard.set(legacyId, forKey: udKey)

        let id = DeviceIdentity.deviceId

        #expect(id == legacyId)
        #expect(keychainRead() == legacyId)
    }

    @Test("Keychain ID takes precedence over UserDefaults")
    func test_deviceId_whenBothKeychainAndUserDefaultsSet_prefersKeychain() {
        clearAll()
        defer { clearAll() }

        // Seed different values in each store
        let keychainId = "KEYCHAIN0-0000-0000-0000-000000000000"
        if let data = keychainId.data(using: .utf8) {
            let add: [CFString: Any] = [
                kSecClass:          kSecClassGenericPassword,
                kSecAttrService:    kcService,
                kSecAttrAccount:    kcAccount,
                kSecValueData:      data,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            SecItemAdd(add as CFDictionary, nil)
        }
        UserDefaults.standard.set("DEFAULTS0-0000-0000-0000-000000000000", forKey: udKey)

        let id = DeviceIdentity.deviceId

        #expect(id == keychainId)
    }
}
