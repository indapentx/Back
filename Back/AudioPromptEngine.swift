//
//  AudioPromptEngine.swift
//  Back
//
//  Created by Furkan Öztürk on 9/19/25.
//

import Foundation
import AVFoundation

enum AudioPromptMode: String, CaseIterable, Identifiable, Hashable {
    case auto
    case recordings
    case speech

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .recordings:
            return "Recorded"
        case .speech:
            return "System"
        }
    }

    var description: String {
        switch self {
        case .auto:
            return "Use recordings when available"
        case .recordings:
            return "Use only custom recordings"
        case .speech:
            return "Use built-in speech"
        }
    }
}

enum AudioPromptCue: Equatable {
    case count(Int)
    case rest
    case repComplete(Int)
    case exerciseIntro(index: Int, title: String)
    case cooldown
    case sessionComplete
    case resume
    case paused
    case holdRelease
    case custom(text: String, resource: String? = nil, preferredExtension: String? = nil)

    var spokenText: String {
        switch self {
        case .count(let number):
            return "\(number)"
        case .rest:
            return "Rest"
        case .repComplete(let number):
            // speak "Rep N"
            return "Rep \(number)"
        case .exerciseIntro(let index, let title):
            return "Exercise \(index + 1): \(title)"
        case .cooldown:
            return "Cooldown"
        case .sessionComplete:
            return "Session complete"
        case .resume:
            return "Resuming"
        case .paused:
            return "Paused"
        case .holdRelease:
            return ""
        case .custom(let text, _, _):
            return text
        }
    }

    /// Returns candidate base filenames (without extension) for locating a custom recording.
    /// Provide files such as `count_1.m4a`, `rep_2.m4a`, etc.
    var candidateResourceNames: [String] {
        switch self {
        case .count(let number):
            return ["count_\(number)"]
        case .rest:
            return ["rest"]
        case .repComplete(let number):
            // look for "rep_N" first, fallback to a generic "rep"
            return ["rep_\(number)", "rep"]
        case .exerciseIntro(let index, _):
            // only specific per-exercise intro file
            return ["exercise_\(index + 1)"]
        case .cooldown:
            return ["cooldown"]
        case .sessionComplete:
            return ["session_complete"]
        case .resume:
            return ["resume"]
        case .paused:
            return ["paused"]
        case .holdRelease:
            return ["hold_release_cue"]
        case .custom(_, let resource, _):
            if let resource {
                return [resource]
            }
            return []
        }
    }

    var preferredFileExtension: String? {
        switch self {
        case .custom(_, _, let ext):
            return ext
        default:
            return nil
        }
    }
}

final class AudioPromptEngine {
    var mode: AudioPromptMode = .auto {
        didSet { stop() }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var cachedPlayers: [URL: AVAudioPlayer] = [:]
    private var resolvedResourceURLs: [String: URL] = [:]
    private var missingResourceLog: Set<String> = []
    private var activePlayer: AVAudioPlayer?
    // Search order for audio asset extensions when looking up recordings.
    private let supportedExtensions = ["m4a", "mp3", "wav", "caf", "aif", "aiff"]

    func play(_ cue: AudioPromptCue) {
        stop()

        switch mode {
        case .speech:
            speak(cue.spokenText)
        case .auto:
            if playRecordingIfAvailable(for: cue) {
                return
            }
            speak(cue.spokenText)
        case .recordings:
            _ = playRecordingIfAvailable(for: cue)
        }
    }

    func stop() {
        activePlayer?.stop()
        activePlayer = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    var isBusy: Bool {
        (activePlayer?.isPlaying ?? false) || synthesizer.isSpeaking
    }

    func hasRecording(for cue: AudioPromptCue) -> Bool {
        guard mode != .speech else { return false }
        return resourceURL(for: cue) != nil
    }

    private func playRecordingIfAvailable(for cue: AudioPromptCue) -> Bool {
        guard mode != .speech else { return false }
        guard let resourceURL = resourceURL(for: cue) else {
            return false
        }

        if let player = cachedPlayers[resourceURL] {
            activePlayer = player
            player.currentTime = 0
            player.play()
            return true
        }

        guard let player = makePlayer(forResourceURL: resourceURL) else { return false }
        cachedPlayers[resourceURL] = player
        activePlayer = player
        player.play()
        return true
    }

    private func resourceURL(for cue: AudioPromptCue) -> URL? {
        let names = cue.candidateResourceNames
        guard !names.isEmpty else { return nil }
        guard let baseURL = Bundle.main.resourceURL else { return nil }

        for name in names {
            var extensionsToCheck = supportedExtensions
            if let preferredExt = cue.preferredFileExtension {
                if let existingIndex = extensionsToCheck.firstIndex(of: preferredExt) {
                    extensionsToCheck.remove(at: existingIndex)
                }
                extensionsToCheck.insert(preferredExt, at: 0)
            }

            for ext in extensionsToCheck {
                let cacheKey = "\(name).\(ext)"
                if let cached = resolvedResourceURLs[cacheKey] {
                    return cached
                }
                if let directMatch = Bundle.main.url(forResource: name, withExtension: ext) {
                    resolvedResourceURLs[cacheKey] = directMatch
                    return directMatch
                }
                if let directoryMatch = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "AudioPrompts") {
                    resolvedResourceURLs[cacheKey] = directoryMatch
                    return directoryMatch
                }
                let targetFilename = cacheKey
                if let enumerator = FileManager.default.enumerator(at: baseURL, includingPropertiesForKeys: nil) {
                    for case let url as URL in enumerator where url.lastPathComponent == targetFilename {
                        resolvedResourceURLs[cacheKey] = url
                        return url
                    }
                }
            }
        }
        let key = names.first ?? ""
        if !key.isEmpty, missingResourceLog.insert(key).inserted {
            print("[AudioPromptEngine] Missing recording for cue: \(key)")
        }
        return nil
    }

    private func makePlayer(forResourceURL url: URL) -> AVAudioPlayer? {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            return player
        } catch {
            return nil
        }
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
