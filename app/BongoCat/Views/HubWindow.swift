import SwiftUI
import Cocoa

// MARK: - Navigation

enum HubNavigationItem: String, CaseIterable, Hashable {
    case achievements = "Achievements"

    var systemImage: String {
        switch self {
        case .achievements: return "trophy.fill"
        }
    }
}

// MARK: - Window Controller

class HubWindowController: NSWindowController, NSWindowDelegate {
    init(appDelegate: AppDelegate) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "BongoCat"
        window.center()
        window.setFrameAutosaveName("HubWindow")
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        window.contentView = NSHostingView(rootView: HubView(appDelegate: appDelegate))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Hub View

struct HubView: View {
    @ObservedObject var appDelegate: AppDelegate
    @State private var selectedItem: HubNavigationItem? = .achievements

    var body: some View {
        NavigationSplitView {
            List(HubNavigationItem.allCases, id: \.self, selection: $selectedItem) { item in
                Label(item.rawValue, systemImage: item.systemImage)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        } detail: {
            switch selectedItem {
            case .achievements:
                AchievementsView(appDelegate: appDelegate)
            case nil:
                Text("Select a section")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 700, minHeight: 480)
    }
}

// MARK: - Achievements View

private struct AchievementsView: View {
    @ObservedObject var appDelegate: AppDelegate
    @StateObject private var fallbackCounter = StrokeCounter()

    private var strokeCounter: StrokeCounter {
        appDelegate.overlayWindow?.catAnimationController?.strokeCounter ?? fallbackCounter
    }

    var body: some View {
        AchievementsContent(
            strokeCounter: strokeCounter,
            milestoneManager: appDelegate.milestoneManager
        )
    }
}

private struct AchievementsContent: View {
    @ObservedObject var strokeCounter: StrokeCounter
    @ObservedObject var milestoneManager: MilestoneNotificationManager

    private var keystrokeAchievements: [Achievement] {
        milestoneManager.allAchievements().filter { $0.type == .keystrokes }
    }

    private var clickAchievements: [Achievement] {
        milestoneManager.allAchievements().filter { $0.type == .mouseClicks }
    }

    private var totalAchievements: [Achievement] {
        milestoneManager.allAchievements().filter { $0.type == .total }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                StatsHeaderView(
                    keystrokes: strokeCounter.keystrokes,
                    mouseClicks: strokeCounter.mouseClicks,
                    totalStrokes: strokeCounter.totalStrokes
                )

                AchievementSectionView(
                    title: "Keystrokes",
                    systemImage: "keyboard",
                    achievements: keystrokeAchievements,
                    currentCount: strokeCounter.keystrokes
                )

                AchievementSectionView(
                    title: "Mouse Clicks",
                    systemImage: "cursorarrow.click",
                    achievements: clickAchievements,
                    currentCount: strokeCounter.mouseClicks
                )

                AchievementSectionView(
                    title: "Total Activity",
                    systemImage: "bolt.fill",
                    achievements: totalAchievements,
                    currentCount: strokeCounter.totalStrokes
                )
            }
            .padding(24)
        }
        .navigationTitle("Achievements")
    }
}

// MARK: - Stats Header

private struct StatsHeaderView: View {
    let keystrokes: Int
    let mouseClicks: Int
    let totalStrokes: Int

    var body: some View {
        HStack(spacing: 12) {
            StatCardView(value: keystrokes, label: "Keystrokes", systemImage: "keyboard")
            StatCardView(value: mouseClicks, label: "Mouse Clicks", systemImage: "cursorarrow.click")
            StatCardView(value: totalStrokes, label: "Total Actions", systemImage: "bolt.fill")
        }
    }
}

private struct StatCardView: View {
    let value: Int
    let label: String
    let systemImage: String

    private var formattedValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(formattedValue)
                .font(.system(.title2, design: .rounded).weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Achievement Section

private struct AchievementSectionView: View {
    let title: String
    let systemImage: String
    let achievements: [Achievement]
    let currentCount: Int

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200))]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(achievements, id: \.id) { achievement in
                    AchievementCardView(
                        achievement: achievement,
                        currentCount: currentCount
                    )
                }
            }
        }
    }
}

// MARK: - Achievement Card

private struct AchievementCardView: View {
    let achievement: Achievement
    let currentCount: Int

    private var isUnlocked: Bool {
        currentCount >= achievement.threshold
    }

    private var progress: Double {
        min(1.0, Double(currentCount) / Double(achievement.threshold))
    }

    private var formattedThreshold: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: achievement.threshold)) ?? "\(achievement.threshold)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(achievement.icon)
                    .font(.system(size: 28))
                    .grayscale(isUnlocked ? 0 : 1)
                Spacer()
                if isUnlocked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .imageScale(.medium)
                }
            }

            Text(achievement.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .foregroundColor(isUnlocked ? .primary : .secondary)

            Text(formattedThreshold)
                .font(.caption2)
                .foregroundColor(.secondary)

            if !isUnlocked {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isUnlocked
                    ? Color.accentColor.opacity(0.08)
                    : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isUnlocked ? Color.accentColor.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
        .opacity(isUnlocked ? 1.0 : 0.75)
    }
}
