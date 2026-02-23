import Foundation

/// Single source of truth for the persistent device identifier used across all subsystems
/// (analytics, backend sync, etc.). The ID is created on first launch and stored in UserDefaults.
enum DeviceIdentity {
    private static let key = "BongoCatDeviceId"

    static var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}
