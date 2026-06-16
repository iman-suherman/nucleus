import AppKit
import Foundation

enum HourlyBeepSound: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case high = "High"
    case low = "Low"
    case doubleBeep = "Double"
    case triple = "Triple"
    case digital = "Digital"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .high: return "High pitch"
        case .low: return "Low pitch"
        case .doubleBeep: return "Double beep"
        case .triple: return "Triple beep"
        case .digital: return "Digital"
        }
    }

    func playAlert() {
        HourlyBeepPlayer.play(sequence: toneSequence)
    }

    private var toneSequence: [HourlyBeepPlayer.Tone] {
        switch self {
        case .classic:
            return [.init(frequency: 880, duration: 0.12)]
        case .high:
            return [.init(frequency: 1_176, duration: 0.12)]
        case .low:
            return [.init(frequency: 659, duration: 0.14)]
        case .doubleBeep:
            return [
                .init(frequency: 880, duration: 0.08, gapAfter: 0.07),
                .init(frequency: 880, duration: 0.08),
            ]
        case .triple:
            return [
                .init(frequency: 988, duration: 0.07, gapAfter: 0.06),
                .init(frequency: 988, duration: 0.07, gapAfter: 0.06),
                .init(frequency: 988, duration: 0.07),
            ]
        case .digital:
            return [.init(frequency: 1_000, duration: 0.1, waveform: .digital)]
        }
    }
}

enum HourlyBeepPlayer {
    struct Tone {
        var frequency: Double
        var duration: TimeInterval
        var gapAfter: TimeInterval = 0
        var waveform: Waveform = .sine

        enum Waveform {
            case sine
            case digital
        }
    }

    private static var activeSound: NSSound?

    static func play(sequence: [Tone]) {
        Task { @MainActor in
            for tone in sequence {
                playTone(tone)
                if tone.gapAfter > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(tone.gapAfter * 1_000_000_000))
                }
            }
        }
    }

    @MainActor
    private static func playTone(_ tone: Tone) {
        activeSound?.stop()
        let data = wavData(for: tone)
        guard let sound = NSSound(data: data) else { return }
        activeSound = sound
        sound.play()
    }

    private static func wavData(for tone: Tone) -> Data {
        let sampleRate = 44_100.0
        let frameCount = max(1, Int(sampleRate * tone.duration))
        var samples = [Int16]()
        samples.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let progress = Double(index) / Double(frameCount)
            let envelope = casioEnvelope(at: progress)

            let wave: Double
            switch tone.waveform {
            case .sine:
                wave = sin(2 * .pi * tone.frequency * time)
            case .digital:
                let phase = tone.frequency * time
                wave = sin(2 * .pi * phase) >= 0 ? 1 : -1
            }

            let sample = wave * envelope * 0.45
            samples.append(clampedSample(sample))
        }

        return makeWAV(samples: samples, sampleRate: Int(sampleRate))
    }

    private static func casioEnvelope(at progress: Double) -> Double {
        if progress < 0.04 {
            return progress / 0.04
        }
        return exp(-10 * (progress - 0.04))
    }

    private static func clampedSample(_ value: Double) -> Int16 {
        Int16(max(-32_767, min(32_767, value * 32_767)))
    }

    private static func makeWAV(samples: [Int16], sampleRate: Int) -> Data {
        let byteRate = sampleRate * 2
        let dataSize = samples.count * 2
        var data = Data(capacity: 44 + dataSize)

        data.append(contentsOf: "RIFF".utf8)
        data.append(littleEndian: UInt32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: UInt32(byteRate))
        data.append(littleEndian: UInt16(2))
        data.append(littleEndian: UInt16(16))
        data.append(contentsOf: "data".utf8)
        data.append(littleEndian: UInt32(dataSize))

        for sample in samples {
            data.append(littleEndian: sample)
        }

        return data
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func append(littleEndian value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func append(littleEndian value: Int16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
