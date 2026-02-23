//
//  ContentView.swift
//  Back
//
//  Created by Furkan Öztürk on 9/19/25.
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SessionRecord.startedAt, order: .reverse) private var sessionHistory: [SessionRecord]
    @StateObject private var viewModel = SessionViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    sessionControls

                    Group {
                        if let stats = analyticsSummary {
                            analyticsSection(summary: stats)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            analyticsPlaceholder
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.35), value: sessionHistory.count)
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Back Relief")
        }
        .onAppear(perform: configureSessionCallbacks)
        // Keep stage-based animations for subtle layout changes
        .animation(.snappy(duration: 0.35), value: viewModel.stage)
        // Remove phase-wide implicit animations to avoid animating phase text
        // .animation(.snappy(duration: 0.35), value: viewModel.phase) // removed
        .animation(.easeInOut(duration: 0.35), value: viewModel.spokenPrompt)
        .animation(.easeInOut(duration: 0.35), value: viewModel.currentExerciseIndex)
    }

    private func configureSessionCallbacks() {
        viewModel.onSessionCompletion = { summary in
            let record = SessionRecord(startedAt: summary.start,
                                       endedAt: summary.end,
                                       exerciseCount: summary.exerciseCount,
                                       totalReps: summary.totalReps,
                                       autoplayEnabled: summary.autoplayEnabled)
            modelContext.insert(record)
            try? modelContext.save()
        }
    }

    private var sessionControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            sessionCard
            controlsRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Workout Session")
                .font(.title2.weight(.semibold))
            Spacer()

            HStack(spacing: 10) {
                Image(systemName: viewModel.isSilentModeEnabled ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Toggle("Silent Mode", isOn: $viewModel.isSilentModeEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.accentColor)
                    .accessibilityLabel("Silent Mode")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
        }
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    // Keep title transition if desired; no animation on phase text
                    Text(currentExerciseTitle)
                        .id("title-\(currentExerciseTitle)")
                        .font(.title3.weight(.semibold))
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                    Text(phaseDescription)
                        .id("phase-\(phaseDescription)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        // Remove transition/animation on phase text (Get Ready / Hold / Rest)
                }
                Spacer()

                // Countdown now matches elapsed timer animation style
                Text(phaseCountdown)
                    .id("countdown-\(phaseCountdown)")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.2), value: phaseCountdown)
            }

            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .animation(.easeInOut(duration: 0.4), value: viewModel.progress)

            HStack {
                VStack(alignment: .leading) {
                    Text("Rep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.currentRepDisplay)")
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: viewModel.currentRepDisplay)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Elapsed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.totalElapsedDisplay)
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.2), value: viewModel.totalElapsedDisplay)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Next")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(nextExerciseTitle)
                        .id("next-\(nextExerciseTitle)")
                        .font(.headline)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: nextExerciseTitle)
                }
            }

            if !viewModel.spokenPrompt.isEmpty {
                Divider().padding(.top, 6)
                    .transition(.opacity)

                Label(viewModel.spokenPrompt, systemImage: "waveform")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 6)
        // Subtle emphasis when running vs idle/paused
        .scaleEffect(cardScale)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.stage)
        // Removed phase-based animation to avoid animating phase text
    }

    private var controlsRow: some View {
        HStack(spacing: 16) {
            Button(action: primaryButtonAction) {
                controlLabel(text: primaryButtonTitle, symbol: primaryButtonSymbol)
                // Removed symbolEffect animations on the primary button
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive, action: viewModel.stop) {
                controlLabel(text: "Stop", symbol: "stop.fill")
                // Removed symbolEffect and state animations on the stop button
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.stage == .idle)
        }
    }

    private func primaryButtonAction() {
        switch viewModel.stage {
        case .running:
            withAnimation(.snappy(duration: 0.25)) {
                viewModel.pause()
            }
        case .paused, .idle, .completed, .waitingForNextExercise:
            withAnimation(.snappy(duration: 0.25)) {
                viewModel.start()
            }
        }
    }

    private var primaryButtonTitle: String {
        switch viewModel.stage {
        case .running:
            return "Pause"
        case .paused:
            return "Resume"
        case .completed:
            return "Restart"
        case .waitingForNextExercise, .idle:
            return "Start"
        }
    }

    private var primaryButtonSymbol: String {
        switch viewModel.stage {
        case .running:
            return "pause.fill"
        case .paused:
            return "play.fill"
        case .completed:
            return "gobackward"
        case .waitingForNextExercise, .idle:
            return "play.fill"
        }
    }

    private func controlLabel(text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.headline)
            .frame(maxWidth: .infinity)
    }

    private func analyticsSection(summary: AnalyticsSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Progress")
                .font(.title2.weight(.semibold))

            VStack(spacing: 14) {
                analyticsRow(title: "Sessions Today", value: "\(summary.sessionsToday)")
                analyticsRow(title: "Current Streak", value: summary.currentStreakDescription)
                analyticsRow(title: "Longest Streak", value: summary.longestStreakDescription)
                analyticsRow(title: "Last Session", value: summary.lastSessionDescription)
                analyticsRow(title: "Time Spent Today", value: summary.timeSpentTodayDescription)
                analyticsRow(title: "30-Day Avg Sessions/Day", value: summary.last30DaysDailyAverageDescription)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func analyticsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: value)
        }
    }

    private var analyticsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Progress")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                Text("Start a session to unlock your streaks and timing insights.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Your stats will appear here after the first completion.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentExerciseTitle: String {
        if let exercise = viewModel.currentExercise {
            return exercise.title
        }
        return "Ready when you are"
    }

    private var nextExerciseTitle: String {
        if let exercise = viewModel.upcomingExercise {
            return exercise.title
        }
        return "—"
    }

    private var phaseDescription: String {
        switch viewModel.phase {
        case .hold:
            return "Hold"
        case .rest:
            return viewModel.currentExercise?.restDuration == 0 ? "Transition" : "Rest"
        case .cooldown:
            return "Cooldown"
        case .prepare:
            return "Get Ready"
        case .idle:
            switch viewModel.stage {
            case .waitingForNextExercise:
                return "Tap start for the next exercise"
            case .completed:
                return "Session complete!"
            default:
                return ""
            }
        }
    }

    private var phaseCountdown: String {
        guard viewModel.stage != .idle else { return "00" }
        let seconds = max(viewModel.phaseRemaining, 0)
        return String(format: "%02d", seconds)
    }

    // Subtle emphasis on the card while actively running
    private var cardScale: CGFloat {
        switch viewModel.stage {
        case .running: return 1.01
        default: return 1.0
        }
    }

    private var analyticsSummary: AnalyticsSummary? {
        AnalyticsSummary(records: sessionHistory)
    }
}

private extension SessionViewModel {
    var currentRepDisplay: String {
        guard stage != .idle else { return "–" }
        let targetReps = currentExercise?.reps ?? exercises.first?.reps ?? 0
        return "\(max(currentRep, 0))/\(targetReps)"
    }

    var totalElapsedDisplay: String {
        guard totalElapsedSeconds > 0 else { return "00:00" }
        let minutes = totalElapsedSeconds / 60
        let seconds = totalElapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct AnalyticsSummary {
    let sessionsToday: Int
    let currentStreak: Int
    let longestStreak: Int
    let lastSessionDuration: TimeInterval
    let todayTotalDuration: TimeInterval
    let last30DaysDailySessionsAverage: Double

    private static let dayBoundaryHour = 4

    init?(records: [SessionRecord]) {
        guard !records.isEmpty else { return nil }
        let calendar = Calendar.current
        let todayActivityDay = Self.activityDay(for: Date(), calendar: calendar)
        let sessionsWithDay = records.map { record in
            (record: record, day: Self.activityDay(for: record.startedAt, calendar: calendar))
        }

        sessionsToday = sessionsWithDay.filter { calendar.isDate($0.day, inSameDayAs: todayActivityDay) }.count
        todayTotalDuration = sessionsWithDay
            .filter { calendar.isDate($0.day, inSameDayAs: todayActivityDay) }
            .reduce(0) { partial, item in
                partial + max(item.record.duration, 0)
            }
        lastSessionDuration = max(records.first?.duration ?? 0, 0)

        let trailing30DayStart = calendar.date(byAdding: .day, value: -29, to: todayActivityDay) ?? todayActivityDay
        let sessionsInTrailing30Days = sessionsWithDay.filter { $0.day >= trailing30DayStart && $0.day <= todayActivityDay }.count
        last30DaysDailySessionsAverage = Double(sessionsInTrailing30Days) / 30.0

        let uniqueDays = Array(Set(sessionsWithDay.map { $0.day })).sorted()
        let daySet = Set(uniqueDays)
        if uniqueDays.isEmpty {
            currentStreak = 0
            longestStreak = 0
        } else {
            var longest = 1
            var current = 1
            for pair in zip(uniqueDays.dropFirst(), uniqueDays) {
                if let diff = calendar.dateComponents([.day], from: pair.1, to: pair.0).day, diff == 1 {
                    current += 1
                    longest = max(longest, current)
                } else {
                    current = 1
                    longest = max(longest, current)
                }
            }

            longestStreak = longest

            if let mostRecent = uniqueDays.last {
                var streak = 1
                var cursor = mostRecent
                while let previous = calendar.date(byAdding: .day, value: -1, to: cursor), daySet.contains(previous) {
                    streak += 1
                    cursor = previous
                }
                let yesterdayActivityDay = calendar.date(byAdding: .day, value: -1, to: todayActivityDay) ?? todayActivityDay
                let isRecentEnough = calendar.isDate(mostRecent, inSameDayAs: todayActivityDay)
                    || calendar.isDate(mostRecent, inSameDayAs: yesterdayActivityDay)
                currentStreak = isRecentEnough ? streak : 0
            } else {
                currentStreak = 0
            }
        }
    }

    var currentStreakDescription: String {
        currentStreak > 0 ? "\(currentStreak) days" : "Start today"
    }

    var longestStreakDescription: String {
        longestStreak > 0 ? "\(longestStreak) days" : "—"
    }

    var timeSpentTodayDescription: String {
        formatDuration(todayTotalDuration)
    }

    var last30DaysDailyAverageDescription: String {
        guard last30DaysDailySessionsAverage.isFinite else { return "—" }
        return String(format: "%.2f", last30DaysDailySessionsAverage)
    }

    var lastSessionDescription: String {
        guard lastSessionDuration > 0 else { return "—" }
        return formatDuration(lastSessionDuration)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let safeDuration = max(duration, 0)
        let totalSeconds = Int(safeDuration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func activityDay(for date: Date, calendar: Calendar) -> Date {
        let shiftedDate = calendar.date(byAdding: .hour, value: -dayBoundaryHour, to: date) ?? date
        return calendar.startOfDay(for: shiftedDate)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SessionRecord.self, inMemory: true)
}
