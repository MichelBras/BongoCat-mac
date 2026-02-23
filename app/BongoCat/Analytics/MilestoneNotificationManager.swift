import Foundation
import UserNotifications
import AppKit
import SwiftUI

// MARK: - Achievement Models

struct Achievement: Codable {
    let id: String
    let type: AchievementType
    let threshold: Int
    let title: String
    let icon: String
    let message: String

    enum AchievementType: String, Codable {
        case keystrokes
        case mouseClicks = "mouse_clicks"
        case total
    }
}

private struct AchievementsConfig: Codable {
    let achievements: [Achievement]
}

// MARK: - Manager

class MilestoneNotificationManager: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = MilestoneNotificationManager()

    // Notification toggle
    @Published private var notificationsEnabled: Bool = true
    private let notificationsEnabledKey = "BongoCatMilestoneNotificationsEnabled"

    // Loaded achievements grouped by type
    private var keystrokeAchievements: [Achievement] = []
    private var mouseClickAchievements: [Achievement] = []
    private var totalAchievements: [Achievement] = []

    // Track which achievement IDs have already been notified
    private var notifiedAchievementIds: Set<String> = []
    private let notifiedAchievementIdsKey = "BongoCatNotifiedAchievementIds"

    // Track if notifications have been set up
    private var notificationsSetup: Bool = false

    // Analytics tracking
    private var analytics: PostHogAnalyticsManager {
        return PostHogAnalyticsManager.shared
    }

    override init() {
        super.init()
        loadAchievements()
        loadSettings()
        migrateFromOldTracking()
    }

    // MARK: - Achievement Loading

    private func loadAchievements() {
        guard let url = Bundle.main.url(forResource: "achievements", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AchievementsConfig.self, from: data) else {
            print("⚠️ achievements.json not found or invalid — falling back to defaults")
            loadDefaultAchievements()
            return
        }

        keystrokeAchievements = config.achievements
            .filter { $0.type == .keystrokes }
            .sorted { $0.threshold < $1.threshold }
        mouseClickAchievements = config.achievements
            .filter { $0.type == .mouseClicks }
            .sorted { $0.threshold < $1.threshold }
        totalAchievements = config.achievements
            .filter { $0.type == .total }
            .sorted { $0.threshold < $1.threshold }

        let total = config.achievements.count
        print("🏆 Loaded \(total) achievements from achievements.json (\(keystrokeAchievements.count) keystroke, \(mouseClickAchievements.count) click, \(totalAchievements.count) total)")
    }

    private func loadDefaultAchievements() {
        let defaultThresholds = [100, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 1000000, 10000000]

        keystrokeAchievements = defaultThresholds.map { threshold in
            Achievement(
                id: "keystroke_\(threshold)",
                type: .keystrokes,
                threshold: threshold,
                title: "Keystroke Milestone",
                icon: "⌨️",
                message: "You've typed \(formatCount(threshold)) keystrokes!"
            )
        }
        mouseClickAchievements = defaultThresholds.map { threshold in
            Achievement(
                id: "click_\(threshold)",
                type: .mouseClicks,
                threshold: threshold,
                title: "Mouse Click Milestone",
                icon: "🖱️",
                message: "You've made \(formatCount(threshold)) mouse clicks!"
            )
        }
        totalAchievements = defaultThresholds.map { threshold in
            Achievement(
                id: "total_\(threshold)",
                type: .total,
                threshold: threshold,
                title: "Total Activity Milestone",
                icon: "🎯",
                message: "Amazing! You've reached \(formatCount(threshold)) total actions!"
            )
        }
    }

    // MARK: - Migration from old tracking format

    private func migrateFromOldTracking() {
        guard notifiedAchievementIds.isEmpty else { return }

        let oldLastKeystroke = UserDefaults.standard.integer(forKey: "BongoCatLastKeystrokeMilestone")
        let oldLastClick = UserDefaults.standard.integer(forKey: "BongoCatLastClickMilestone")
        let oldLastTotal = UserDefaults.standard.integer(forKey: "BongoCatLastTotalMilestone")

        guard oldLastKeystroke > 0 || oldLastClick > 0 || oldLastTotal > 0 else { return }

        for achievement in keystrokeAchievements where achievement.threshold <= oldLastKeystroke {
            notifiedAchievementIds.insert(achievement.id)
        }
        for achievement in mouseClickAchievements where achievement.threshold <= oldLastClick {
            notifiedAchievementIds.insert(achievement.id)
        }
        for achievement in totalAchievements where achievement.threshold <= oldLastTotal {
            notifiedAchievementIds.insert(achievement.id)
        }

        if !notifiedAchievementIds.isEmpty {
            saveSettings()
            print("🏆 Migrated \(notifiedAchievementIds.count) achievements from old tracking format")
        }
    }

    // MARK: - Setup and Permissions

    private func setupNotifications() {
        guard !notificationsSetup else { return }

        guard canAccessNotifications() else {
            print("⚠️ UserNotifications not available - running in development mode, notifications disabled")
            notificationsEnabled = false
            return
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        notificationsSetup = true
        print("✅ Notifications setup completed")
    }

    private func canAccessNotifications() -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty else {
            return false
        }
        guard NSRunningApplication.current.activationPolicy != .prohibited else {
            return false
        }
        return true
    }

    func requestNotificationPermission() {
        setupNotifications()

        guard notificationsSetup else {
            print("⚠️ Cannot request notification permission - setup failed")
            return
        }

        analytics.trackNotificationPermissionRequested()

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Notification permission error: \(error.localizedDescription)")
                    self?.analytics.trackError("Notification permission error", context: ["error": error.localizedDescription])
                    self?.analytics.trackNotificationPermissionResult(false)
                } else if granted {
                    print("✅ Notification permission granted")
                    self?.analytics.trackNotificationPermissionResult(true)
                } else {
                    print("⚠️ Notification permission denied")
                    self?.analytics.trackNotificationPermissionResult(false)
                    self?.notificationsEnabled = false
                    self?.saveSettings()
                }
            }
        }
    }

    // MARK: - Settings Management

    private func loadSettings() {
        if UserDefaults.standard.object(forKey: notificationsEnabledKey) != nil {
            notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsEnabledKey)
        }

        if let savedIds = UserDefaults.standard.array(forKey: notifiedAchievementIdsKey) as? [String] {
            notifiedAchievementIds = Set(savedIds)
        }

        analytics.trackConfigurationLoaded("milestone_manager", success: true)

        print("🔔 Loaded milestone settings - enabled: \(notificationsEnabled), notified: \(notifiedAchievementIds.count) achievements")
    }

    private func saveSettings() {
        UserDefaults.standard.set(notificationsEnabled, forKey: notificationsEnabledKey)
        UserDefaults.standard.set(Array(notifiedAchievementIds), forKey: notifiedAchievementIdsKey)
    }

    // MARK: - Public Interface

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        saveSettings()
        analytics.trackSettingToggled("milestone_notifications", enabled: enabled)
        print("🔔 Milestone notifications \(enabled ? "enabled" : "disabled")")
    }

    func isNotificationsEnabled() -> Bool {
        return notificationsEnabled
    }

    func sendTestNotification() {
        let test = Achievement(
            id: "__test__",
            type: .keystrokes,
            threshold: 0,
            title: "Test Achievement",
            icon: "🧪",
            message: "Notifications are working! You'll see these when you hit milestones."
        )
        sendAchievementNotification(test)
    }

    // Returns all loaded achievements (useful for UI display)
    func allAchievements() -> [Achievement] {
        return keystrokeAchievements + mouseClickAchievements + totalAchievements
    }

    // MARK: - Milestone Checking

    func checkKeystrokeMilestone(_ keystrokeCount: Int) {
        guard notificationsEnabled else { return }
        checkAchievements(keystrokeAchievements, count: keystrokeCount, analyticsType: "keystrokes")
    }

    func checkMouseClickMilestone(_ clickCount: Int) {
        guard notificationsEnabled else { return }
        checkAchievements(mouseClickAchievements, count: clickCount, analyticsType: "mouse_clicks")
    }

    func checkTotalStrokeMilestone(_ totalCount: Int) {
        guard notificationsEnabled else { return }
        checkAchievements(totalAchievements, count: totalCount, analyticsType: "total_activity")
    }

    private func checkAchievements(_ achievements: [Achievement], count: Int, analyticsType: String) {
        for achievement in achievements {
            guard count >= achievement.threshold else { break }
            guard !notifiedAchievementIds.contains(achievement.id) else { continue }

            notifiedAchievementIds.insert(achievement.id)
            saveSettings()

            analytics.trackMilestoneReached(achievement.threshold, type: analyticsType)
            sendAchievementNotification(achievement)
            Task { @MainActor in BackendSyncManager.shared.syncAchievement(achievement) }
        }
    }

    // MARK: - Notification Sending

    private func sendAchievementNotification(_ achievement: Achievement) {
        setupNotifications()

        guard notificationsSetup else {
            print("⚠️ Cannot send notification - setup failed")
            return
        }

        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "\(achievement.icon) \(achievement.title)"
        content.body = achievement.message
        content.sound = .default
        content.userInfo = [
            "achievementId": achievement.id,
            "type": achievement.type.rawValue,
            "threshold": achievement.threshold,
            "milestone": true
        ]

        let identifier = "achievement-\(achievement.id)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        analytics.trackNotificationShown("milestone", milestone: achievement.threshold)

        center.add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Failed to send achievement notification: \(error.localizedDescription)")
                    self.analytics.trackError("Failed to send achievement notification", context: [
                        "error": error.localizedDescription,
                        "achievementId": achievement.id
                    ])
                } else {
                    print("🏆 Achievement notification sent: \(achievement.title) (\(achievement.id))")
                }
            }
        }
    }

    // MARK: - Reset Methods

    func resetMilestoneTracking() {
        notifiedAchievementIds.removeAll()
        saveSettings()
        analytics.trackAdvancedFeatureUsage("reset_milestone_tracking", complexity: "basic", success: true)
        print("🔔 Milestone tracking reset")
    }

    // MARK: - Helper Methods

    private func formatCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        if let type = userInfo["type"] as? String {
            if userInfo["milestone"] as? Bool == true {
                analytics.trackNotificationClicked("milestone", action: "tap")
            } else {
                analytics.trackNotificationClicked(type, action: "tap")
            }
        }

        print("🔔 Notification tapped: \(response.notification.request.identifier)")
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
