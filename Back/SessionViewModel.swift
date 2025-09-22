//
//  SessionViewModel.swift
//  Back
//
//  Created by Furkan Öztürk on 9/19/25.
//

import Foundation
import SwiftUI
import Combine

struct ExerciseDefinition: Identifiable, Equatable {
    let id: UUID = UUID()
    let title: String
    let holdDuration: Int
    let restDuration: Int
    let reps: Int
    let postExerciseRest: Int
}

enum SessionStage: Equatable {
    case idle
    case running
    case paused
    case waitingForNextExercise
    case completed
}

enum ExercisePhase: Equatable {
    case idle
    case prepare
    case hold
    case rest
    case cooldown
}

struct SessionSummary {
    let start: Date
    let end: Date
    let exerciseCount: Int
    let totalReps: Int
    let autoplayEnabled: Bool
}

@MainActor
final class SessionViewModel: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()

    @Published private(set) var stage: SessionStage = .idle
    @Published private(set) var phase: ExercisePhase = .idle
    @Published private(set) var currentExerciseIndex: Int? = nil
    @Published private(set) var currentRep: Int = 0
    @Published private(set) var completedReps: Int = 0
    @Published private(set) var totalElapsedSeconds: Int = 0
    @Published var spokenPrompt: String = ""

    // Voice mode is fixed to Auto
    private let audioMode: AudioPromptMode = .auto

    // Autoplay is always enabled and not user-changeable
    private let autoplayEnabled: Bool = true

    var onSessionCompletion: ((SessionSummary) -> Void)?

    // Rest durations reduced from 5 to 3 seconds
    // First exercise is 10 reps; each rep = two 5s holds (handled by halfRep logic).
    let exercises: [ExerciseDefinition] = [
        ExerciseDefinition(title: "Single Knee-to-Chest", holdDuration: 5, restDuration: 3, reps: 10, postExerciseRest: 10),
        ExerciseDefinition(title: "Double Knee-to-Chest", holdDuration: 10, restDuration: 3, reps: 10, postExerciseRest: 10),
        ExerciseDefinition(title: "Hamstring Stretch (Left)", holdDuration: 10, restDuration: 3, reps: 10, postExerciseRest: 10),
        ExerciseDefinition(title: "Hamstring Stretch (Right)", holdDuration: 10, restDuration: 3, reps: 10, postExerciseRest: 0)
    ]

    private var timer: Timer?
    private let promptEngine = AudioPromptEngine()
    private var phaseElapsedSeconds: Int = 0
    private var sessionStartDate: Date?
    private var isSequenceCountingActive = false
    private var pendingSequenceCountDuration: Int? = nil

    private let prepareDuration: Int = 10

    // Pause advancement of time/phase while non-count audio is playing
    private var pauseWhileAudio: Bool = false

    // Special handling: for the first exercise, two holds make one rep
    private var halfRepPending: Bool = false

    private var totalRepsRequired: Int {
        exercises.reduce(0) { $0 + $1.reps }
    }

    init() {
        promptEngine.mode = audioMode
    }

    deinit {
        timer?.invalidate()
        let engine = promptEngine
        Task { @MainActor in engine.stop() }
    }

    func start() {
        switch stage {
        case .idle, .completed:
            resetSession()
            beginSession()
        case .paused:
            publishChange()
            resumeTimer()
            stage = .running
            playCue(.resume)
        case .waitingForNextExercise:
            // Advance to the next exercise if possible
            if let idx = currentExerciseIndex {
                let next = idx + 1
                beginExercise(at: next)
            } else {
                beginSession()
            }
        case .running:
            break
        }
    }

    func pause() {
        guard stage == .running else { return }
        publishChange()
        timer?.invalidate()
        stage = .paused
        playCue(.paused)
    }

    func stop() {
        timer?.invalidate()
        resetSession()
    }

    // Skip to the next rep; if no rep to skip, skip to the next exercise (or finish).
    func skip() {
        // Only meaningful during an active/paused session
        guard stage == .running || stage == .paused else { return }

        publishChange()

        // Stop any currently playing audio to avoid overlap when skipping
        promptEngine.stop()
        pauseWhileAudio = false
        isSequenceCountingActive = false
        pendingSequenceCountDuration = nil

        // If still in prepare, start the first exercise
        if phase == .prepare {
            beginExercise(at: 0)
            return
        }

        guard let index = currentExerciseIndex,
              exercises.indices.contains(index),
              let exercise = currentExercise else {
            return
        }

        // If there are remaining reps, jump to the next rep (do not count as completed)
        if currentRep < exercise.reps {
            halfRepPending = false
            currentRep += 1
            setPhase(.hold)
            return
        }

        // Otherwise skip to the next exercise (or finish)
        halfRepPending = false
        advanceToNextExercise(from: index)
    }

    var progress: Double {
        let total = totalRepsRequired
        guard total > 0 else { return 0 }
        return Double(completedReps) / Double(total)
    }

    var currentExercise: ExerciseDefinition? {
        guard let index = currentExerciseIndex, exercises.indices.contains(index) else { return nil }
        return exercises[index]
    }

    var upcomingExercise: ExerciseDefinition? {
        guard let index = currentExerciseIndex else { return exercises.first }
        let nextIndex = index + 1
        guard exercises.indices.contains(nextIndex) else { return nil }
        return exercises[nextIndex]
    }

    var phaseRemaining: Int {
        switch phase {
        case .prepare:
            return max(prepareDuration - phaseElapsedSeconds, 0)
        case .hold:
            guard let exercise = currentExercise else { return 0 }
            return max(exercise.holdDuration - phaseElapsedSeconds, 0)
        case .rest:
            return max(currentRestDuration() - phaseElapsedSeconds, 0)
        case .cooldown:
            guard let exercise = currentExercise else { return 0 }
            return max(exercise.postExerciseRest - phaseElapsedSeconds, 0)
        case .idle:
            return 0
        }
    }

    private func beginSession() {
        publishChange()
        sessionStartDate = Date()
        stage = .running
        completedReps = 0
        totalElapsedSeconds = 0
        setPhase(.prepare)
        startTimer()
    }

    private func beginExercise(at index: Int) {
        guard exercises.indices.contains(index) else {
            finishSession()
            return
        }
        publishChange()
        stage = .running
        currentExerciseIndex = index
        currentRep = 1
        halfRepPending = false
        setPhase(.hold)
        playCue(.exerciseIntro(index: index, title: exercises[index].title))
        startTimer()
    }

    private func setPhase(_ newPhase: ExercisePhase) {
        publishChange()
        phase = newPhase
        phaseElapsedSeconds = 0
        configurePhaseAudio(for: newPhase)
        announcePhaseStart()
    }

    private func configurePhaseAudio(for phase: ExercisePhase) {
        switch phase {
        case .hold:
            if let exercise = currentExercise {
                if exercise.holdDuration >= 10, promptEngine.hasRecording(for: .count(10)) {
                    pendingSequenceCountDuration = 10
                    isSequenceCountingActive = false
                } else if exercise.holdDuration >= 5, promptEngine.hasRecording(for: .count(5)) {
                    pendingSequenceCountDuration = 5
                    isSequenceCountingActive = false
                } else {
                    isSequenceCountingActive = false
                    pendingSequenceCountDuration = nil
                }
            } else {
                isSequenceCountingActive = false
                pendingSequenceCountDuration = nil
            }
        case .prepare, .rest, .cooldown, .idle:
            isSequenceCountingActive = false
            pendingSequenceCountDuration = nil
        }
    }

    private func announcePhaseStart() {
        switch phase {
        case .prepare:
            spokenPrompt = "Get ready \(prepareDuration)s"
        case .hold:
            if let exercise = currentExercise {
                spokenPrompt = "Hold for \(exercise.holdDuration)s"
            } else {
                spokenPrompt = ""
            }
        case .rest:
            let dur = currentRestDuration()
            spokenPrompt = dur > 0 ? "Rest \(dur)s" : ""
        case .cooldown:
            if let exercise = currentExercise {
                spokenPrompt = exercise.postExerciseRest > 0 ? "Cooldown \(exercise.postExerciseRest)s" : ""
            } else {
                spokenPrompt = ""
            }
        case .idle:
            spokenPrompt = ""
        }
    }

    private func resetSession() {
        publishChange()
        promptEngine.stop()
        stage = .idle
        phase = .idle
        currentExerciseIndex = nil
        currentRep = 0
        completedReps = 0
        totalElapsedSeconds = 0
        sessionStartDate = nil
        phaseElapsedSeconds = 0
        spokenPrompt = ""
        pendingSequenceCountDuration = nil
        isSequenceCountingActive = false
        pauseWhileAudio = false
        halfRepPending = false
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func resumeTimer() {
        guard timer == nil || !(timer?.isValid ?? false) else { return }
        startTimer()
    }

    private func tick() {
        guard stage == .running else { return }

        if pauseWhileAudio {
            if promptEngine.isBusy {
                return
            } else {
                pauseWhileAudio = false
            }
        }

        publishChange()
        totalElapsedSeconds += 1
        phaseElapsedSeconds += 1

        switch phase {
        case .prepare:
            if phaseElapsedSeconds >= prepareDuration {
                beginExercise(at: 0)
            }
        case .hold:
            startSequenceCountingIfNeeded()
            guard let exercise = currentExercise else { return }
            if phaseElapsedSeconds >= exercise.holdDuration {
                transitionToRest()
            }
        case .rest:
            if phaseElapsedSeconds >= currentRestDuration() {
                completeRep()
            }
        case .cooldown:
            guard let exercise = currentExercise else { return }
            if phaseElapsedSeconds >= exercise.postExerciseRest {
                advanceAfterCooldown()
            }
        case .idle:
            break
        }
    }

    private func startSequenceCountingIfNeeded() {
        guard phase == .hold else { return }
        guard !isSequenceCountingActive else { return }
        guard let duration = pendingSequenceCountDuration else { return }
        guard !promptEngine.isBusy else { return }
        isSequenceCountingActive = true
        pendingSequenceCountDuration = nil
        if promptEngine.hasRecording(for: .count(duration)) {
            playCue(.count(duration))
        }
    }

    private func currentRestDuration() -> Int {
        return currentExercise?.restDuration ?? 0
    }

    private func transitionToRest() {
        let rest = currentRestDuration()
        if rest > 0 {
            setPhase(.rest)
        } else {
            completeRep()
        }
    }

    private func completeRep() {
        guard let exercise = currentExercise else { return }
        publishChange()

        if currentExerciseIndex == 0 {
            if !halfRepPending {
                halfRepPending = true
                setPhase(.hold)
                return
            } else {
                halfRepPending = false
                completedReps += 1
                playCue(.repComplete(currentRep))
                if currentRep >= exercise.reps {
                    finishExercise()
                } else {
                    currentRep += 1
                    setPhase(.hold)
                }
                return
            }
        }

        completedReps += 1
        playCue(.repComplete(currentRep))

        if currentRep >= exercise.reps {
            finishExercise()
        } else {
            currentRep += 1
            setPhase(.hold)
        }
    }

    private func finishExercise() {
        guard let index = currentExerciseIndex else { return }
        // Removed exercise complete cue as requested
        halfRepPending = false

        if exercises[index].postExerciseRest > 0 {
            setPhase(.cooldown)
            playCue(.cooldown)
            return
        }
        advanceToNextExercise(from: index)
    }

    private func advanceAfterCooldown() {
        guard let index = currentExerciseIndex else { return }
        advanceToNextExercise(from: index)
    }

    private func advanceToNextExercise(from index: Int) {
        let nextIndex = index + 1
        if exercises.indices.contains(nextIndex) {
            // Always autoplay since it's fixed to true
            beginExercise(at: nextIndex)
        } else {
            finishSession()
        }
    }

    private func finishSession() {
        timer?.invalidate()
        publishChange()
        stage = .completed
        phase = .idle
        spokenPrompt = "Session complete"
        playCue(.sessionComplete)
        guard let start = sessionStartDate else { return }
        let end = Date()
        let summary = SessionSummary(start: start,
                                     end: end,
                                     exerciseCount: exercises.count,
                                     totalReps: totalRepsRequired,
                                     autoplayEnabled: autoplayEnabled)
        onSessionCompletion?(summary)
        sessionStartDate = nil
    }

    private func playCue(_ cue: AudioPromptCue) {
        switch cue {
        case .count(let n):
            guard promptEngine.hasRecording(for: .count(n)) else { return }
            promptEngine.play(cue)
        default:
            pauseWhileAudio = true
            promptEngine.play(cue)
        }
    }

    private func publishChange() {
        objectWillChange.send()
    }
}
