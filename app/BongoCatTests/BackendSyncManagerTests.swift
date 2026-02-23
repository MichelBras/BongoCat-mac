import Testing
import Foundation
@testable import BongoCat

@Suite("BackendSyncManager")
struct BackendSyncManagerTests {

    // MARK: - Initial state

    @Test("isConfigured is false when no Supabase credentials are present")
    @MainActor
    func test_isConfigured_whenNoCredentials_returnsFalse() {
        // SupabaseConfig.load() returns nil in the test environment (no plist, no env vars),
        // so BackendSyncManager should remain unconfigured.
        #expect(BackendSyncManager.shared.isConfigured == false)
    }

    @Test("authState starts as signedOut")
    @MainActor
    func test_authState_onInit_isSignedOut() {
        #expect(BackendSyncManager.shared.authState == .signedOut)
    }

    @Test("syncStatus starts as idle")
    @MainActor
    func test_syncStatus_onInit_isIdle() {
        #expect(BackendSyncManager.shared.syncStatus == .idle)
    }

    // MARK: - No-op behaviour when unconfigured

    @Test("scheduleStatsSync is a no-op when not configured")
    @MainActor
    func test_scheduleStatsSync_whenNotConfigured_statusRemainsIdle() {
        BackendSyncManager.shared.scheduleStatsSync(
            keystrokes: 100,
            mouseClicks: 50,
            totalStrokes: 150
        )
        // Status must stay idle — no network call should be attempted.
        #expect(BackendSyncManager.shared.syncStatus == .idle)
    }

    @Test("flushPendingSync is a no-op when not configured")
    @MainActor
    func test_flushPendingSync_whenNotConfigured_statusRemainsIdle() {
        BackendSyncManager.shared.flushPendingSync()
        #expect(BackendSyncManager.shared.syncStatus == .idle)
    }

    @Test("beginSession is a no-op when not configured")
    @MainActor
    func test_beginSession_whenNotConfigured_statusRemainsIdle() {
        BackendSyncManager.shared.beginSession(appVersion: "1.0.0")
        #expect(BackendSyncManager.shared.syncStatus == .idle)
    }

    @Test("endSession is a no-op when not configured")
    @MainActor
    func test_endSession_whenNotConfigured_statusRemainsIdle() {
        BackendSyncManager.shared.endSession(
            keystrokes: 100,
            mouseClicks: 50,
            totalStrokes: 150
        )
        #expect(BackendSyncManager.shared.syncStatus == .idle)
    }

    // MARK: - BackendSyncStatus equality

    @Test("BackendSyncStatus idle equals idle")
    func test_syncStatus_idle_equalsIdle() {
        #expect(BackendSyncStatus.idle == .idle)
    }

    @Test("BackendSyncStatus syncing equals syncing")
    func test_syncStatus_syncing_equalsSyncing() {
        #expect(BackendSyncStatus.syncing == .syncing)
    }

    @Test("BackendSyncStatus success equals success with same date")
    func test_syncStatus_success_equalsSuccessWithSameDate() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        #expect(BackendSyncStatus.success(date) == .success(date))
    }

    @Test("BackendSyncStatus failed equals failed with same message")
    func test_syncStatus_failed_equalsFailedWithSameMessage() {
        #expect(BackendSyncStatus.failed("timeout") == .failed("timeout"))
    }

    @Test("BackendSyncStatus idle does not equal syncing")
    func test_syncStatus_idle_doesNotEqualSyncing() {
        #expect(BackendSyncStatus.idle != .syncing)
    }

    // MARK: - BackendAuthState equality

    @Test("BackendAuthState signedOut equals signedOut")
    func test_authState_signedOut_equalsSignedOut() {
        #expect(BackendAuthState.signedOut == .signedOut)
    }

    @Test("BackendAuthState signedIn with same email equals signedIn")
    func test_authState_signedIn_equalsSignedInWithSameEmail() {
        #expect(BackendAuthState.signedIn(email: "a@b.com") == .signedIn(email: "a@b.com"))
    }

    @Test("BackendAuthState signedIn with nil email equals signedIn with nil")
    func test_authState_signedIn_nilEmail_equalsNilEmail() {
        #expect(BackendAuthState.signedIn(email: nil) == .signedIn(email: nil))
    }

    @Test("BackendAuthState signedOut does not equal signedIn")
    func test_authState_signedOut_doesNotEqualSignedIn() {
        #expect(BackendAuthState.signedOut != .signedIn(email: nil))
    }
}
