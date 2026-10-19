import AVFoundation
import Combine
import Foundation

/// The instrument voice used for root and interval notes. The drone keeps its own warm pad.
enum Timbre: String, CaseIterable, Identifiable {
    case warm = "Warm"
    case pure = "Pure"
    case bell = "Bell"
    case pluck = "Pluck"
    case organ = "Organ"
    case reed = "Reed"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .warm: "flame"
        case .pure: "tuningfork"
        case .bell: "bell"
        case .pluck: "guitars"
        case .organ: "pianokeys"
        case .reed: "wind"
        }
    }

    /// One sample of the voice, including its attack and natural decay; the caller applies the final release.
    func sample(frequency: Double, time t: Double) -> Double {
        let phase = 2 * Double.pi * frequency * t
        switch self {
        case .warm:
            return min(1, t / 0.035) * (sin(phase) + 0.18 * sin(phase * 2) + 0.055 * sin(phase * 3))
        case .pure:
            return min(1, t / 0.03) * sin(phase)
        case .bell:
            // Inharmonic partials, with the upper ones dying away first.
            let partials: [(ratio: Double, amplitude: Double, decay: Double)] = [(1, 1, 1.6), (2, 0.42, 2.4), (2.76, 0.38, 3.2), (5.4, 0.2, 5), (8.93, 0.1, 7)]
            let value = partials.reduce(0) { $0 + $1.amplitude * exp(-t * $1.decay) * sin(phase * $1.ratio) }
            return min(1, t / 0.003) * value * 0.9
        case .pluck:
            let value = (1...8).reduce(0.0) { sum, n in
                let harmonic = Double(n)
                return sum + exp(-t * (1.4 + harmonic * 0.9)) * sin(phase * harmonic) / harmonic
            }
            return min(1, t / 0.004) * value * 0.95
        case .organ:
            let drawbars: [(ratio: Double, amplitude: Double)] = [(1, 1), (2, 0.6), (3, 0.34), (4, 0.24), (6, 0.12), (8, 0.08)]
            let value = drawbars.reduce(0) { $0 + $1.amplitude * sin(phase * $1.ratio) }
            return min(1, t / 0.012) * value * 0.6
        case .reed:
            // Odd harmonics give a hollow, clarinet-like color; a gentle vibrato arrives after the onset.
            let vibrato = 1 + 0.004 * min(1, t / 0.4) * sin(2 * Double.pi * 5.2 * t)
            let reedPhase = phase * vibrato
            let value = sin(reedPhase) + 0.42 * sin(reedPhase * 3) + 0.22 * sin(reedPhase * 5) + 0.11 * sin(reedPhase * 7)
            return min(1, t / 0.05) * value * 0.72
        }
    }
}

@MainActor
final class IntervalAudio: ObservableObject {
    @Published private(set) var isDronePlaying = false

    private let engine = AVAudioEngine()
    private let dronePlayer = AVAudioPlayerNode()
    // A small pool of voices so a new note rings alongside the last one instead of cutting it off.
    private let voices = (0..<8).map { _ in AVAudioPlayerNode() }
    private var nextVoice = 0
    private let sampleRate = 44_100.0
    private var isConfigured = false

    func setDrone(_ enabled: Bool, rootFrequency: Double) {
        if enabled {
            guard startEngine() else { return }
            dronePlayer.stop()
            dronePlayer.scheduleBuffer(makeDroneBuffer(rootFrequency: rootFrequency), at: nil, options: .loops, completionHandler: nil)
            dronePlayer.play()
            isDronePlaying = true
        } else {
            dronePlayer.stop()
            isDronePlaying = false
        }
    }

    func updateDrone(rootFrequency: Double) {
        guard isDronePlaying else { return }
        setDrone(true, rootFrequency: rootFrequency)
    }

    func playRootNote(frequency: Double, timbre: Timbre) {
        play(makeNoteBuffer(frequency: frequency, duration: 1.05, timbre: timbre))
    }

    func playInterval(semitones: Int, rootFrequency: Double, timbre: Timbre) {
        let targetFrequency = rootFrequency * pow(2, Double(semitones) / 12)
        play(makeNoteBuffer(frequency: targetFrequency, duration: 2.15, timbre: timbre))
    }

    func stopAll() {
        dronePlayer.stop()
        voices.forEach { $0.stop() }
        if engine.isRunning { engine.stop() }
        isDronePlaying = false
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard startEngine() else { return }
        // Round-robin through the pool; only the oldest voice is ever reclaimed.
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()
        voice.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        voice.play()
    }

    private func startEngine() -> Bool {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        if !isConfigured {
            for node in [dronePlayer] + voices {
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: audioFormat)
            }
            engine.prepare()
            isConfigured = true
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                return false
            }
        }
        return true
    }

    private var audioFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }

    private func makeDroneBuffer(rootFrequency: Double) -> AVAudioPCMBuffer {
        // The loop is sized to an integer number of cycles at the selected root's lower octave.
        let fundamental = rootFrequency / 2
        let frameCount = AVAudioFrameCount((sampleRate / fundamental * 64).rounded())
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channels = buffer.floatChannelData else { return buffer }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let swell = 0.9 + 0.1 * sin(2 * Double.pi * 4 * Double(frame) / Double(frameCount))
            let bass = warmTone(frequency: fundamental, time: t)
            let root = warmTone(frequency: fundamental * 2, time: t) * 0.52
            let fifth = warmTone(frequency: fundamental * 3, time: t) * 0.34
            let octave = warmTone(frequency: fundamental * 4, time: t) * 0.18
            let value = Float((bass + root + fifth + octave) * 0.075 * swell)
            channels[0][frame] = value
            channels[1][frame] = value * 0.96
        }
        return buffer
    }

    private func makeNoteBuffer(frequency: Double, duration: Double, timbre: Timbre) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channels = buffer.floatChannelData else { return buffer }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let release = max(0, min(1, (duration - t) / 0.26))
            // Slightly below the old single-voice level, leaving headroom for overlapping notes.
            let value = Float(timbre.sample(frequency: frequency, time: t) * 0.21 * release)
            channels[0][frame] = value
            channels[1][frame] = value
        }
        return buffer
    }

    private func warmTone(frequency: Double, time: Double) -> Double {
        let phase = 2 * Double.pi * frequency * time
        return sin(phase) + 0.18 * sin(phase * 2) + 0.055 * sin(phase * 3)
    }
}
