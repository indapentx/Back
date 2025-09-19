//
//  SessionViewModel.swift
//  Back
//
//  Created by Furkan Öztürk on 9/19/25.
//

import Foundation
import SwiftUI
import AVFoundation

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
    @Published private(set) var stage: SessionStage = .idle
    @Published private(set) var phase: ExercisePhase = .idle
    @Published private(set) var currentExerciseIndex: Int? = nil
    @Published private(set) var currentRep: Int = 0
    @Published private(set) var completedReps: Int = 0
    @Published private(set) var totalElapsedSeconds: Int = 0
    @Published var autoplayEnabled: Bool = true
    @Published var spokenPrompt: String = ""

    var onSessionCompletion: ((SessionSummary) -> Void)?

    let exercises: [ExerciseDefinition] = [
        ExerciseDefinition(title: "Pelvic Tilts", holdDuration: 5, restDuration: 2, reps: 10, postExerciseRest: 0),
        ExerciseDefinition(title: "Bridge Hold", holdDuration: 10, restDuration: 2, reps: 10, postExerciseRest: 0),
        ExerciseDefinition(title: "Cat Stretch", holdDuration: 5, restDuration: 2, reps: 10, postExerciseRest: 10)
    ]

    private var timer: Timer?
    private let synthesizer = AVSpeechSynthesizer()
    private var phaseElapsedSeconds: Int = 0
    private var sessionStartDate: Date?

    private var totalRepsRequired: Int {
        exercises.reduce(0) { $0 + $1.reps }
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        switch stage {
        case .idle, .completed:
            resetSession()
            beginSession()
        case .paused:
            resumeTimer()
            stage = .running
            speak("Resuming")
        case .waitingForNextExercise:
            guard let nextIndex = currentExerciseIndex else {
                beginSession()
                return
            }
            beginExercise(at: nextIndex)
        case .running:
            break
        }
    }

    func pause() {
        guard stage == .running else { return }
        timer?.invalidate()
        stage = .paused
        speak("Paused")
    }

    func stop() {
        timer?.invalidate()
        resetSession()
    }

    var progress: Double {
        guard totalRepsRequired > 0 else { return 0 }
        return Double(completedReps) / Double(totalRepsRequired)
    }

    var currentExercise: ExerciseDefinition? {
        guard let index = currentExerciseIndex, exercises.indices.contains(index) else { return nil }
        return exercises[index]
    }

    var upcomingExercise: ExerciseDefinition? {
        guard let index = currentExerciseIndex else {
            return exercises.first
        }
        let nextIndex = stage == .waitingForNextExercise ? index : index + 1
        guard exercises.indices.contains(nextIndex) else { return nil }
        return exercises[nextIndex]
    }

    var phaseRemaining: Int {
        guard let exercise = currentExercise else { return 0 }
        switch phase {
        case .hold:
            return max(exercise.holdDuration - phaseElapsedSeconds, 0)
        case .rest:
            return max(exercise.restDuration - phaseElapsedSeconds, 0)
        case .cooldown:
            return max(exercise.postExerciseRest - phaseElapsedSeconds, 0)
        case .idle:
            return 0
        }
    }

    private func beginSession() {
        sessionStartDate = Date()
        stage = .running
        completedReps = 0
        totalElapsedSeconds = 0
        beginExercise(at: 0)
    }

    private func beginExercise(at index: Int) {
        guard exercises.indices.contains(index) else {
            finishSession()
            return
        }
        stage = .running
        currentExerciseIndex = index
        currentRep = 1
        setPhase(.hold)
        speak("Exercise \(index + 1): \(exercises[index].title)")
        startTimer()
    }

    private func setPhase(_ newPhase: ExercisePhase) {
        phase = newPhase
        phaseElapsedSeconds = 0
        announcePhaseStart()
    }

    private func announcePhaseStart() {
        guard let exercise = currentExercise else { return }
        switch phase {
        case .hold:
            spokenPrompt = "Hold for \(exercise.holdDuration)s"
        case .rest:
            spokenPrompt = exercise.restDuration > 0 ? "Rest \(exercise.restDuration)s" : ""
        case .cooldown:
            spokenPrompt = exercise.postExerciseRest > 0 ? "Cooldown \(exercise.postExerciseRest)s" : ""
        case .idle:
            spokenPrompt = ""
        }
    }

    private func resetSession() {
        stage = .idle
        phase = .idle
        currentExerciseIndex = nil
        currentRep = 0
        completedReps = 0
        totalElapsedSeconds = 0
        sessionStartDate = nil
        phaseElapsedSeconds = 0
        spokenPrompt = ""
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
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
        totalElapsedSeconds += 1
        phaseElapsedSeconds += 1

        switch phase {
        case .hold:
            speakCountIfNeeded()
            guard let exercise = currentExercise else { return }
            if phaseElapsedSeconds >= exercise.holdDuration {
                transitionToRest()
            }
        case .rest:
            guard let exercise = currentExercise else { return }
            if phaseElapsedSeconds >= exercise.restDuration {
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

    private func speakCountIfNeeded() {
        guard phase == .hold else { return }
        speak("\(phaseElapsedSeconds)")
    }

    private func transitionToRest() {
        guard let exercise = currentExercise else { return }
        if exercise.restDuration > 0 {
            setPhase(.rest)
            speak("Rest")
        } else {
            completeRep()
        }
    }

    private func completeRep() {
        guard let exercise = currentExercise else { return }
        completedReps += 1
        speak("Rep \(currentRep) complete")

        if currentRep >= exercise.reps {
            finishExercise()
        } else {
            currentRep += 1
            setPhase(.hold)
            speak("Rep \(currentRep) start")
        }
    }

    private func finishExercise() {
        guard let index = currentExerciseIndex else { return }
        speak("Exercise \(index + 1) done")

        if exercises[index].postExerciseRest > 0 {
            setPhase(.cooldown)
            speak("Cooldown")
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
            if autoplayEnabled {
                beginExercise(at: nextIndex)
            } else {
                timer?.invalidate()
                currentExerciseIndex = nextIndex
                currentRep = 0
                stage = .waitingForNextExercise
                phase = .idle
                spokenPrompt = "Ready for exercise \(nextIndex + 1)"
                speak("Tap start when ready for exercise \(nextIndex + 1)")
            }
        } else {
            finishSession()
        }
    }

    private func finishSession() {
        timer?.invalidate()
        stage = .completed
        phase = .idle
        spokenPrompt = "Session complete"
        speak("Session complete")
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

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }
}
