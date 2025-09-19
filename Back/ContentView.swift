//
//  ContentView.swift
//  Back
//
//  Created by Furkan Öztürk on 9/19/25.
//

import SwiftUI
import SwiftData
import AVFoundation

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SessionRecord.startedAt, order: .reverse) private var sessionHistory: [SessionRecord]
    @StateObject private var viewModel = SessionViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    sessionControls
                    if let stats = analyticsSummary {
                        analyticsSection(summary: stats)
                    }
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Back Relief")
        }
        .onAppear(perform: configureSessionCallbacks)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Session")
                .font(.title2.weight(.semibold))

            Toggle(isOn: $viewModel.autoplayEnabled) {
                Label("Autoplay", systemImage: viewModel.autoplayEnabled ? "play.circle.fill" : "play.circle")
                    .font(.headline)
            }
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        }
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentExerciseTitle)
                        .font(.title3.weight(.semibold))
                    Text(phaseDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(phaseCountdown)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            HStack {
                VStack(alignment: .leading) {
                    Text("Rep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.currentRepDisplay)")
                        .font(.headline)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Elapsed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.totalElapsedDisplay)
                        .font(.headline)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Next")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(nextExerciseTitle)
                        .font(.headline)
                }
            }

            if !viewModel.spokenPrompt.isEmpty {
                Divider().padding(.top, 6)
                Label(viewModel.spokenPrompt, systemImage: "waveform")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 6)
    }

    private var controlsRow: some View {
        HStack(spacing: 16) {
            Button(action: viewModel.start) {
                controlLabel(text: startButtonTitle, symbol: "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button(action: viewModel.pause) {
                controlLabel(text: "Pause", symbol: "pause.fill")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.stage != .running)

            Button(role: .destructive, action: viewModel.stop) {
                controlLabel(text: "Stop", symbol: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.stage == .idle)
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
                analyticsRow(title: "Average Duration", value: summary.averageDurationDescription)
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
        }
    }

    private var startButtonTitle: String {
        switch viewModel.stage {
        case .running:
            return "Running"
        case .paused:
            return "Resume"
        case .waitingForNextExercise:
            return "Next"
        case .completed:
            return "Restart"
        case .idle:
            return "Start"
        }
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
        return seconds.formatted(.number.precision(.integerLength(2)))
    }

    private var analyticsSummary: AnalyticsSummary? {
        AnalyticsSummary(records: sessionHistory)
    }
}

private extension SessionViewModel {
    var currentRepDisplay: String {
        guard stage != .idle else { return "–" }
        return "\(max(currentRep, 0))/\(currentExercise?.reps ?? 0)"
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
    let averageDuration: TimeInterval

    init?(records: [SessionRecord]) {
        guard !records.isEmpty else { return nil }
        let calendar = Calendar.current
        sessionsToday = records.filter { calendar.isDateInToday($0.startedAt) }.count
        averageDuration = records.map { $0.duration }.reduce(0, +) / Double(records.count)

        let uniqueDays = Array(Set(records.map { calendar.startOfDay(for: $0.startedAt) })).sorted()
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
                }
            }

            longestStreak = longest

            if let mostRecent = uniqueDays.last {
                var streak = 1
                var cursor = mostRecent
                while let previous = calendar.date(byAdding: .day, value: -1, to: cursor), uniqueDays.contains(previous) {
                    streak += 1
                    cursor = previous
                }
                currentStreak = calendar.isDateInToday(mostRecent) || calendar.isDateInYesterday(mostRecent) ? streak : 0
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

    var averageDurationDescription: String {
        guard averageDuration.isFinite else { return "—" }
        let minutes = Int(averageDuration) / 60
        let seconds = Int(averageDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SessionRecord.self, inMemory: true)
}
