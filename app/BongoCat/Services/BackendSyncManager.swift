import Foundation
import AuthenticationServices

#if canImport(Supabase)
import Supabase
#endif

// MARK: - Sync Status

enum BackendSyncStatus: Equatable {
    case idle
    case syncing
    case success(Date)
    case failed(String)

    static func == (lhs: BackendSyncStatus, rhs: BackendSyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing): return true
        case (.success(let a), .success(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Auth State

enum BackendAuthState: Equatable {
    case signedOut
    case signedIn(email: String?)
}

// MARK: - BackendSyncManager

/// Central coordinator for Supabase backend sync.
/// All methods are safe to call regardless of whether the Supabase package is present —
/// they are no-ops when `canImport(Supabase)` is false or credentials are not configured.
@MainActor
final class BackendSyncManager: NSObject, ObservableObject {
    static let shared = BackendSyncManager()

    // MARK: Published state

    @Published private(set) var syncStatus: BackendSyncStatus = .idle
    @Published private(set) var authState: BackendAuthState = .signedOut
    @Published private(set) var isConfigured: Bool = false

    // MARK: Private state

    private var debounceTask: Task<Void, Never>?
    private var sessionId: UUID?
    private var sessionStartedAt: Date?

    // Pending counts (flushed on debounce or resign-active)
    private var pendingKeystrokes: Int = 0
    private var pendingMouseClicks: Int = 0
    private var pendingTotalStrokes: Int = 0

    // UserDefaults keys for offline recovery
    private let pendingSyncFlagKey = "BongoCatPendingStatsSync"
    private let pendingSessionKey = "BongoCatPendingSession"

    // MARK: Init

    private override init() {
        super.init()
        #if canImport(Supabase)
        setupClient()
        #endif
    }

    // MARK: - Session Lifecycle

    /// Call from `applicationDidFinishLaunching`. Registers the device and starts a session.
    func beginSession(appVersion: String) {
        #if canImport(Supabase)
        guard isConfigured else { return }
        sessionId = UUID()
        sessionStartedAt = Date()

        Task {
            await recoverPendingSession()
            await registerDeviceIfNeeded(appVersion: appVersion)
        }
        #endif
    }

    /// Call from `applicationWillTerminate`. Ends the current session.
    func endSession(keystrokes: Int, mouseClicks: Int, totalStrokes: Int) {
        #if canImport(Supabase)
        guard isConfigured, let sid = sessionId, let startedAt = sessionStartedAt else { return }

        // Cancel any pending debounce — we flush immediately
        debounceTask?.cancel()
        debounceTask = nil

        // Persist session to UserDefaults first so it can be recovered if upload fails
        let pendingSession: [String: Any] = [
            "session_id": sid.uuidString,
            "started_at": startedAt.timeIntervalSince1970,
            "ended_at": Date().timeIntervalSince1970,
            "keystrokes": keystrokes,
            "mouse_clicks": mouseClicks,
            "total_strokes": totalStrokes
        ]
        UserDefaults.standard.set(pendingSession, forKey: pendingSessionKey)
        UserDefaults.standard.set(true, forKey: pendingSyncFlagKey)

        Task {
            await syncStatsNow(keystrokes: keystrokes, mouseClicks: mouseClicks, totalStrokes: totalStrokes)
            await uploadSession(
                id: sid,
                startedAt: startedAt,
                endedAt: Date(),
                keystrokes: keystrokes,
                mouseClicks: mouseClicks,
                totalStrokes: totalStrokes
            )
            UserDefaults.standard.removeObject(forKey: pendingSessionKey)
            UserDefaults.standard.set(false, forKey: pendingSyncFlagKey)
        }
        #endif
    }

    // MARK: - Stats Sync

    /// Schedules a debounced stats sync (30 seconds). Cancels any previous pending sync.
    func scheduleStatsSync(keystrokes: Int, mouseClicks: Int, totalStrokes: Int) {
        #if canImport(Supabase)
        guard isConfigured else { return }

        pendingKeystrokes = keystrokes
        pendingMouseClicks = mouseClicks
        pendingTotalStrokes = totalStrokes

        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            guard !Task.isCancelled else { return }
            await syncStatsNow(keystrokes: pendingKeystrokes, mouseClicks: pendingMouseClicks, totalStrokes: pendingTotalStrokes)
        }
        #endif
    }

    /// Flushes any pending stats sync immediately (call on app resign-active).
    func flushPendingSync() {
        #if canImport(Supabase)
        guard isConfigured else { return }
        guard pendingTotalStrokes > 0 else { return }

        debounceTask?.cancel()
        debounceTask = nil

        let k = pendingKeystrokes
        let m = pendingMouseClicks
        let t = pendingTotalStrokes

        Task {
            await syncStatsNow(keystrokes: k, mouseClicks: m, totalStrokes: t)
        }
        #endif
    }

    // MARK: - Achievement Sync

    /// Syncs a newly unlocked achievement to the backend. Fires instantly (low frequency).
    func syncAchievement(_ achievement: Achievement) {
        #if canImport(Supabase)
        guard isConfigured, let client = supabaseClient else { return }
        Task {
            await uploadAchievement(achievement, client: client)
        }
        #endif
    }

    // MARK: - Authentication

    /// Initiates Sign in with Apple. The result is handled asynchronously.
    func signInWithApple(presentationAnchor: ASPresentationAnchor) {
        #if canImport(Supabase)
        guard isConfigured else { return }
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = appleSignInDelegate
        controller.presentationContextProvider = ApplePresentationProvider(anchor: presentationAnchor)
        controller.performRequests()
        #endif
    }

    /// Signs in with email and password.
    func signIn(email: String, password: String) async throws {
        #if canImport(Supabase)
        guard isConfigured, let client = supabaseClient else { return }
        syncStatus = .syncing
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            await handleAuthSuccess()
        } catch {
            syncStatus = .failed(error.localizedDescription)
            throw error
        }
        #endif
    }

    /// Signs up with email and password.
    func signUp(email: String, password: String) async throws {
        #if canImport(Supabase)
        guard isConfigured, let client = supabaseClient else { return }
        syncStatus = .syncing
        do {
            _ = try await client.auth.signUp(email: email, password: password)
            await handleAuthSuccess()
        } catch {
            syncStatus = .failed(error.localizedDescription)
            throw error
        }
        #endif
    }

    /// Completes an Apple Sign In using the raw identity token string.
    /// Called from AccountView after extracting the token from ASAuthorizationAppleIDCredential.
    func completeAppleSignIn(token: String) async {
        #if canImport(Supabase)
        await completeAppleSignIn(identityToken: token)
        #endif
    }

    /// Signs out the current user.
    func signOut() async {
        #if canImport(Supabase)
        guard isConfigured, let client = supabaseClient else { return }
        try? await client.auth.signOut()
        authState = .signedOut
        #endif
    }

    // MARK: - Private (Supabase-specific)

#if canImport(Supabase)
    private var supabaseClient: SupabaseClient?
    private var appleSignInDelegate: AppleSignInDelegate?

    // MARK: Row types

    private struct DeviceUpsertRow: Encodable {
        let device_id: String
        let last_seen_at: String
        let app_version: String?
        let user_id: String?
    }

    private struct StatsUpsertRow: Encodable {
        let device_id: String
        let user_id: String?
        let total_strokes: Int
        let keystrokes: Int
        let mouse_clicks: Int
        let updated_at: String
    }

    private struct SessionInsertRow: Encodable {
        let id: String
        let device_id: String
        let user_id: String?
        let started_at: String
        let ended_at: String?
        let keystrokes: Int
        let mouse_clicks: Int
        let total_strokes: Int
        let app_version: String?
    }

    private struct AchievementUpsertRow: Encodable {
        let device_id: String
        let user_id: String?
        let achievement_id: String
        let achievement_type: String
        let threshold: Int
        let unlocked_at: String
    }

    private struct DeviceRow: Decodable {
        let id: String
    }

    // MARK: Setup

    private func setupClient() {
        guard let config = SupabaseConfig.load() else {
            print("⚠️ Supabase not configured — backend sync disabled.")
            return
        }

        guard let url = URL(string: config.url) else {
            print("❌ Supabase URL invalid: \(config.url)")
            return
        }

        supabaseClient = SupabaseClient(supabaseURL: url, supabaseKey: config.anonKey)
        isConfigured = true
        print("✅ Supabase configured from \(config.source)")

        appleSignInDelegate = AppleSignInDelegate { [weak self] identityToken in
            Task { [weak self] in
                await self?.completeAppleSignIn(identityToken: identityToken)
            }
        }

        // Restore auth session if one exists
        Task {
            await restoreAuthSession()
        }
    }

    private func restoreAuthSession() async {
        guard let client = supabaseClient else { return }
        do {
            let session = try await client.auth.session
            let email = session.user.email
            authState = .signedIn(email: email)
            print("✅ Supabase session restored for \(email ?? "user")")
        } catch {
            authState = .signedOut
        }
    }

    // MARK: Device registration

    private func registerDeviceIfNeeded(appVersion: String) async {
        guard let client = supabaseClient else { return }
        let deviceId = DeviceIdentity.deviceId
        let userId = currentUserId(client: client)
        let now = ISO8601DateFormatter().string(from: Date())

        do {
            try await client
                .from("devices")
                .upsert(
                    DeviceUpsertRow(
                        device_id: deviceId,
                        last_seen_at: now,
                        app_version: appVersion,
                        user_id: userId
                    ),
                    onConflict: "device_id"
                )
                .execute()
            print("✅ Device registered/updated in Supabase")

            // Catch-up: recover stats sync flag
            if UserDefaults.standard.bool(forKey: pendingSyncFlagKey) {
                print("🔄 Recovering pending stats sync from previous session")
            }
        } catch {
            print("⚠️ Failed to register device: \(error.localizedDescription)")
        }
    }

    // MARK: Stats sync

    private func syncStatsNow(keystrokes: Int, mouseClicks: Int, totalStrokes: Int) async {
        guard let client = supabaseClient else { return }
        let deviceId = DeviceIdentity.deviceId
        let userId = currentUserId(client: client)
        let now = ISO8601DateFormatter().string(from: Date())

        syncStatus = .syncing
        do {
            // Resolve device UUID
            guard let deviceUUID = await resolveDeviceUUID(deviceId: deviceId, client: client) else {
                syncStatus = .failed("Device not registered")
                return
            }

            try await client
                .from("stats")
                .upsert(
                    StatsUpsertRow(
                        device_id: deviceUUID,
                        user_id: userId,
                        total_strokes: totalStrokes,
                        keystrokes: keystrokes,
                        mouse_clicks: mouseClicks,
                        updated_at: now
                    ),
                    onConflict: "device_id"
                )
                .execute()

            syncStatus = .success(Date())
            UserDefaults.standard.set(false, forKey: pendingSyncFlagKey)
            print("✅ Stats synced — total: \(totalStrokes), keys: \(keystrokes), clicks: \(mouseClicks)")
        } catch {
            syncStatus = .failed(error.localizedDescription)
            UserDefaults.standard.set(true, forKey: pendingSyncFlagKey)
            print("⚠️ Stats sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: Session upload

    private func uploadSession(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        keystrokes: Int,
        mouseClicks: Int,
        totalStrokes: Int
    ) async {
        guard let client = supabaseClient else { return }
        let deviceId = DeviceIdentity.deviceId
        let userId = currentUserId(client: client)
        let fmt = ISO8601DateFormatter()

        guard let deviceUUID = await resolveDeviceUUID(deviceId: deviceId, client: client) else { return }

        let row = SessionInsertRow(
            id: id.uuidString,
            device_id: deviceUUID,
            user_id: userId,
            started_at: fmt.string(from: startedAt),
            ended_at: fmt.string(from: endedAt),
            keystrokes: keystrokes,
            mouse_clicks: mouseClicks,
            total_strokes: totalStrokes,
            app_version: appVersionString()
        )

        do {
            try await client.from("sessions").insert(row).execute()
            UserDefaults.standard.removeObject(forKey: pendingSessionKey)
            print("✅ Session uploaded")
        } catch {
            print("⚠️ Session upload failed: \(error.localizedDescription)")
        }
    }

    // MARK: Achievement upload

    private func uploadAchievement(_ achievement: Achievement, client: SupabaseClient) async {
        let deviceId = DeviceIdentity.deviceId
        let userId = currentUserId(client: client)
        let fmt = ISO8601DateFormatter()

        guard let deviceUUID = await resolveDeviceUUID(deviceId: deviceId, client: client) else { return }

        let row = AchievementUpsertRow(
            device_id: deviceUUID,
            user_id: userId,
            achievement_id: achievement.id,
            achievement_type: achievement.type.rawValue,
            threshold: achievement.threshold,
            unlocked_at: fmt.string(from: Date())
        )

        do {
            try await client
                .from("achievements")
                .upsert(row, onConflict: "device_id,achievement_id")
                .execute()
            print("✅ Achievement synced: \(achievement.id)")
        } catch {
            print("⚠️ Achievement sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: Auth helpers

    private func handleAuthSuccess() async {
        guard let client = supabaseClient else { return }
        do {
            let session = try await client.auth.session
            let email = session.user.email
            authState = .signedIn(email: email)
            syncStatus = .success(Date())

            // Link all existing anonymous rows to this user
            let userId = session.user.id.uuidString
            try? await client
                .rpc("link_device_to_user", params: [
                    "p_device_id": AnyJSON.string(DeviceIdentity.deviceId),
                    "p_user_id": AnyJSON.string(userId)
                ])
                .execute()
            print("✅ Signed in as \(email ?? "user"), device linked")
        } catch {
            syncStatus = .failed(error.localizedDescription)
        }
    }

    private func completeAppleSignIn(identityToken: String) async {
        guard let client = supabaseClient else { return }
        syncStatus = .syncing
        do {
            _ = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: identityToken)
            )
            await handleAuthSuccess()
        } catch {
            syncStatus = .failed(error.localizedDescription)
            print("⚠️ Apple sign-in failed: \(error.localizedDescription)")
        }
    }

    // MARK: Pending session recovery

    private func recoverPendingSession() async {
        guard let pending = UserDefaults.standard.dictionary(forKey: pendingSessionKey),
              let idString = pending["session_id"] as? String,
              let id = UUID(uuidString: idString),
              let startTs = pending["started_at"] as? Double,
              let endTs = pending["ended_at"] as? Double,
              let keystrokes = pending["keystrokes"] as? Int,
              let mouseClicks = pending["mouse_clicks"] as? Int,
              let totalStrokes = pending["total_strokes"] as? Int
        else { return }

        print("🔄 Recovering pending session from previous launch")
        await uploadSession(
            id: id,
            startedAt: Date(timeIntervalSince1970: startTs),
            endedAt: Date(timeIntervalSince1970: endTs),
            keystrokes: keystrokes,
            mouseClicks: mouseClicks,
            totalStrokes: totalStrokes
        )
    }

    // MARK: Utilities

    private func resolveDeviceUUID(deviceId: String, client: SupabaseClient) async -> String? {
        do {
            let response = try await client
                .from("devices")
                .select("id")
                .eq("device_id", value: deviceId)
                .single()
                .execute()

            let decoder = JSONDecoder()
            let row = try decoder.decode(DeviceRow.self, from: response.data)
            return row.id
        } catch {
            print("⚠️ Could not resolve device UUID: \(error.localizedDescription)")
            return nil
        }
    }

    private func currentUserId(client: SupabaseClient) -> String? {
        return try? client.auth.currentUser?.id.uuidString
    }

    private func appVersionString() -> String? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        return version
    }
#endif
}

// MARK: - Apple Sign-In Delegate

#if canImport(Supabase)
private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let onToken: (String) -> Void

    init(onToken: @escaping (String) -> Void) {
        self.onToken = onToken
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8)
        else {
            print("⚠️ Apple Sign In: could not extract identity token")
            return
        }
        onToken(token)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        print("⚠️ Apple Sign In failed: \(error.localizedDescription)")
    }
}

private final class ApplePresentationProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return anchor
    }
}
#endif
