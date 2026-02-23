import Testing
import Foundation
@testable import BongoCat

@Suite("SupabaseConfig")
struct SupabaseConfigTests {

    // MARK: - Tests

    @Test("returns nil when no credentials are configured")
    func test_load_whenNoCredentials_returnsNil() {
        // In the test environment there is no supabase-config.plist, no relevant
        // environment variables, and no SUPABASE_URL key in Info.plist — so load()
        // must return nil and the app runs in offline-only mode.
        let config = SupabaseConfig.load()

        #expect(config == nil)
    }

    @Test("struct stores url, anonKey and source correctly")
    func test_init_storesAllFields() {
        let config = SupabaseConfig(
            url: "https://test.supabase.co",
            anonKey: "test-anon-key",
            source: "unit test"
        )

        #expect(config.url == "https://test.supabase.co")
        #expect(config.anonKey == "test-anon-key")
        #expect(config.source == "unit test")
    }
}
