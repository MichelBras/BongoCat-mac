import SwiftUI
import Charts

// MARK: - Helper Types

struct DayActivity: Identifiable {
    let date: Date
    let keystrokes: Int
    let mouseClicks: Int
    var id: Date { date }
}

struct PersonalRecords {
    let mostKeystrokesInSession: Int
    let mostClicksInSession: Int
    let longestSessionDuration: TimeInterval?
    let mostActiveDay: (date: Date, total: Int)?
}

// MARK: - StatsViewModel

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var sessions: [SessionRecord] = []
    @Published var isLoading = false

    private let backendSync: BackendSyncManager

    init(backendSync: BackendSyncManager = .shared) {
        self.backendSync = backendSync
    }

    func load() async {
        isLoading = true
        sessions = await backendSync.fetchSessions(limit: 90)
        isLoading = false
    }

    // MARK: Daily Activity (last 30 days, oldest→newest)

    var dailyActivity: [DayActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<30).reversed().compactMap { offset -> DayActivity? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let daySessions = sessions.filter { $0.startDate >= day && $0.startDate < nextDay }
            return DayActivity(
                date: day,
                keystrokes: daySessions.reduce(0) { $0 + $1.keystrokes },
                mouseClicks: daySessions.reduce(0) { $0 + $1.mouse_clicks }
            )
        }
    }

    // MARK: Streaks

    var currentStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay: Date
        if hasActivityOnDay(today) {
            startDay = today
        } else {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  hasActivityOnDay(yesterday) else { return 0 }
            startDay = yesterday
        }
        var streak = 0
        var checkDay = startDay
        while hasActivityOnDay(checkDay) {
            streak += 1
            guard let prevDay = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = prevDay
        }
        return streak
    }

    var longestStreak: Int {
        let calendar = Calendar.current
        guard !sessions.isEmpty else { return 0 }
        let activeDays = Set(sessions.map { calendar.startOfDay(for: $0.startDate) }).sorted()
        guard !activeDays.isEmpty else { return 0 }
        var longest = 1
        var current = 1
        for i in 1..<activeDays.count {
            let prev = activeDays[i - 1]
            let curr = activeDays[i]
            if let expected = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(curr, inSameDayAs: expected) {
                current += 1
            } else {
                longest = max(longest, current)
                current = 1
            }
        }
        return max(longest, current)
    }

    // MARK: Personal Records

    var personalRecords: PersonalRecords {
        let calendar = Calendar.current
        var dailyTotals: [Date: Int] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startDate)
            dailyTotals[day, default: 0] += session.total_strokes
        }
        let mostActiveDay = dailyTotals.max(by: { $0.value < $1.value })
            .map { (date: $0.key, total: $0.value) }
        return PersonalRecords(
            mostKeystrokesInSession: sessions.map(\.keystrokes).max() ?? 0,
            mostClicksInSession: sessions.map(\.mouse_clicks).max() ?? 0,
            longestSessionDuration: sessions.compactMap(\.duration).max(),
            mostActiveDay: mostActiveDay
        )
    }

    var recentSessions: [SessionRecord] {
        Array(sessions.prefix(20))
    }

    // MARK: Private helpers

    private func hasActivityOnDay(_ day: Date) -> Bool {
        let calendar = Calendar.current
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return sessions.contains { $0.startDate >= day && $0.startDate < nextDay }
    }
}

// MARK: - Outer view (holds AppDelegate reference)

struct StatsView: View {
    @ObservedObject var appDelegate: AppDelegate
    @StateObject private var fallbackCounter = StrokeCounter()

    private var strokeCounter: StrokeCounter {
        appDelegate.overlayWindow?.catAnimationController?.strokeCounter ?? fallbackCounter
    }

    var body: some View {
        StatsContent(strokeCounter: strokeCounter)
    }
}

// MARK: - Inner view (owns the view model)

private struct StatsContent: View {
    @ObservedObject var strokeCounter: StrokeCounter
    @StateObject private var viewModel = StatsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                StatsHeaderView(
                    keystrokes: strokeCounter.keystrokes,
                    mouseClicks: strokeCounter.mouseClicks,
                    totalStrokes: strokeCounter.totalStrokes
                )
                ActivityChartSection(viewModel: viewModel)
                PersonalRecordsSection(records: viewModel.personalRecords)
                StreaksSection(current: viewModel.currentStreak, longest: viewModel.longestStreak)
                SessionHistorySection(
                    sessions: viewModel.recentSessions,
                    isLoading: viewModel.isLoading,
                    isConfigured: BackendSyncManager.shared.isConfigured
                )
            }
            .padding(24)
        }
        .navigationTitle("Stats")
        .task { await viewModel.load() }
    }
}

// MARK: - Activity Chart Section

private struct ActivityChartSection: View {
    @ObservedObject var viewModel: StatsViewModel
    @State private var range: Int = 7

    private var chartData: [DayActivity] {
        Array(viewModel.dailyActivity.suffix(range))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Activity", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                Picker("Range", selection: $range) {
                    Text("7 Days").tag(7)
                    Text("30 Days").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if !BackendSyncManager.shared.isConfigured {
                UnconfiguredPromptView()
            } else if viewModel.sessions.isEmpty && !viewModel.isLoading {
                EmptyChartView(message: "No sessions recorded yet")
            } else {
                Chart(chartData) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Keys", day.keystrokes)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : 5)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
            }
        }
    }
}

private struct UnconfiguredPromptView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("Sign in to unlock activity history")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

private struct EmptyChartView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
    }
}

// MARK: - Personal Records Section

private struct PersonalRecordsSection: View {
    let records: PersonalRecords

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Personal Records", systemImage: "star.fill")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                RecordCardView(
                    icon: "⌨️",
                    label: "Best Session",
                    subtitle: "Keystrokes",
                    value: records.mostKeystrokesInSession > 0
                        ? formatCount(records.mostKeystrokesInSession) : "—"
                )
                RecordCardView(
                    icon: "🖱️",
                    label: "Best Session",
                    subtitle: "Clicks",
                    value: records.mostClicksInSession > 0
                        ? formatCount(records.mostClicksInSession) : "—"
                )
                RecordCardView(
                    icon: "⏱️",
                    label: "Longest Session",
                    subtitle: "Duration",
                    value: records.longestSessionDuration.map { formatDuration($0) } ?? "—"
                )
                RecordCardView(
                    icon: "🔥",
                    label: "Most Active Day",
                    subtitle: "Total Inputs",
                    value: records.mostActiveDay.map { formatCount($0.total) } ?? "—"
                )
            }
        }
    }
}

private struct RecordCardView: View {
    let icon: String
    let label: String
    let subtitle: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(icon)
                .font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Streaks Section

private struct StreaksSection: View {
    let current: Int
    let longest: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Streaks", systemImage: "flame.fill")
                .font(.headline)
            HStack(spacing: 12) {
                StreakCardView(icon: "🔥", label: "Current Streak", days: current)
                StreakCardView(icon: "🏆", label: "Longest Streak", days: longest)
            }
        }
    }
}

private struct StreakCardView: View {
    let icon: String
    let label: String
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(icon)
                .font(.title2)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(days)")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text("days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Session History Section

private struct SessionHistorySection: View {
    let sessions: [SessionRecord]
    let isLoading: Bool
    let isConfigured: Bool

    var body: some View {
        if isConfigured {
            VStack(alignment: .leading, spacing: 12) {
                Label("Recent Sessions", systemImage: "clock.fill")
                    .font(.headline)
                if sessions.isEmpty && !isLoading {
                    Text("No sessions recorded yet")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(sessions) { session in
                            SessionRowView(session: session)
                            if session.id != sessions.last?.id {
                                Divider()
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
            }
        }
    }
}

private struct SessionRowView: View {
    let session: SessionRecord

    private var dateLabel: String {
        let calendar = Calendar.current
        let date = session.startDate
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var durationLabel: String? {
        guard let duration = session.duration else { return nil }
        return formatDuration(duration)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateLabel)
                    .font(.callout.weight(.medium))
                if let dur = durationLabel {
                    Text(dur)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 16) {
                Label(formatCount(session.keystrokes), systemImage: "keyboard")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label(formatCount(session.mouse_clicks), systemImage: "cursorarrow.click")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dateLabel), \(session.keystrokes) keystrokes, \(session.mouse_clicks) clicks")
    }
}

// MARK: - Formatting helpers

private func formatCount(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let h = Int(seconds) / 3600
    let m = (Int(seconds) % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "<1m"
}
