import Testing
import Foundation
@testable import BongoCat

@Suite("DeviceIdentity")
struct DeviceIdentityTests {

    private let key = "BongoCatDeviceId"

    // MARK: - Helpers

    private func clearStoredId() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Tests

    @Test("generates a valid UUID on first call")
    func test_deviceId_whenNoStoredId_generatesValidUUID() {
        clearStoredId()
        defer { clearStoredId() }

        let id = DeviceIdentity.deviceId

        #expect(UUID(uuidString: id) != nil)
    }

    @Test("persists the generated ID to UserDefaults")
    func test_deviceId_whenFirstCall_storesInUserDefaults() {
        clearStoredId()
        defer { clearStoredId() }

        let id = DeviceIdentity.deviceId

        #expect(UserDefaults.standard.string(forKey: key) == id)
    }

    @Test("returns the same ID on repeated calls")
    func test_deviceId_whenCalledMultipleTimes_returnsSameId() {
        clearStoredId()
        defer { clearStoredId() }

        let first = DeviceIdentity.deviceId
        let second = DeviceIdentity.deviceId
        let third = DeviceIdentity.deviceId

        #expect(first == second)
        #expect(second == third)
    }

    @Test("returns existing stored ID without generating a new one")
    func test_deviceId_whenStoredIdExists_returnsStoredId() {
        let storedId = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        UserDefaults.standard.set(storedId, forKey: key)
        defer { clearStoredId() }

        let id = DeviceIdentity.deviceId

        #expect(id == storedId)
    }
}
