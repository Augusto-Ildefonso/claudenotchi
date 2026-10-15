import Foundation
import Testing
@testable import ClaudenotchiCore

private let soundsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // ClaudenotchiCoreTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // ClaudenotchiCore
    .deletingLastPathComponent() // Packages
    .deletingLastPathComponent() // repo root
    .appendingPathComponent("Claudenotchi/Sounds")

@Suite struct SoundCueTests {
    @Test(arguments: CompanionState.allCases.filter { $0 != .needsInput })
    func enteringNeedsInputPlaysTheAttentionChime(from old: CompanionState) {
        #expect(SoundCue.cue(from: old, to: .needsInput) == .needsInput)
    }

    @Test(arguments: CompanionState.allCases.filter { $0 != .done })
    func enteringDonePlaysTheFinishedChime(from old: CompanionState) {
        #expect(SoundCue.cue(from: old, to: .done) == .done)
    }

    @Test(arguments: CompanionState.allCases)
    func staying(in state: CompanionState) {
        #expect(SoundCue.cue(from: state, to: state) == nil)
    }

    @Test func otherTransitionsAreSilent() {
        let quiet: [CompanionState] = [.waiting, .thinking, .coding, .reading, .bash, .web, .error, .videogame, .tennis, .sleeping]
        for old in CompanionState.allCases {
            for new in quiet where old != new {
                #expect(SoundCue.cue(from: old, to: new) == nil, "\(old) -> \(new)")
            }
        }
    }

    @Test func fileNamesMatchTheBundledSounds() {
        #expect(SoundCue.needsInput.fileName == "needs-input")
        #expect(SoundCue.done.fileName == "done")
    }
}

@Suite struct SoundAssetTests {
    private struct Wave {
        var channels: Int
        var sampleRate: Int
        var bitsPerSample: Int
        var samples: [Int16]
        var duration: Double { Double(samples.count) / Double(sampleRate * channels) }
        var peak: Double { Double(samples.map { abs(Int($0)) }.max() ?? 0) / 32768 }
    }

    private func parse(_ data: Data) throws -> Wave {
        func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        var offset = 12
        var wave = Wave(channels: 0, sampleRate: 0, bitsPerSample: 0, samples: [])
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = u32(offset + 4)
            let body = offset + 8
            if id == "fmt " {
                #expect(u16(body) == 1, "PCM")
                wave.channels = u16(body + 2)
                wave.sampleRate = u32(body + 4)
                wave.bitsPerSample = u16(body + 14)
            } else if id == "data" {
                wave.samples = stride(from: body, to: min(body + size, data.count) - 1, by: 2).map { Int16(bitPattern: UInt16(u16($0))) }
            }
            offset = body + size + (size % 2)
        }
        return wave
    }

    @Test(arguments: [SoundCue.needsInput, .done])
    func theBundledChimeIsAValidShortAudibleWave(cue: SoundCue) throws {
        let url = soundsDirectory.appendingPathComponent("\(cue.fileName).wav")
        let wave = try parse(Data(contentsOf: url))

        #expect(wave.channels == 1)
        #expect(wave.bitsPerSample == 16)
        #expect(wave.sampleRate >= 8_000)
        #expect(wave.duration > 0.15 && wave.duration < 1.5, "duration \(wave.duration)s")
        #expect(wave.peak > 0.05, "too quiet: \(wave.peak)")
        #expect(wave.peak < 0.9, "too loud / clipping: \(wave.peak)")
    }

    @Test func theChimesStartAndEndAtSilenceSoTheyDoNotClick() throws {
        for cue in [SoundCue.needsInput, .done] {
            let wave = try parse(Data(contentsOf: soundsDirectory.appendingPathComponent("\(cue.fileName).wav")))
            #expect(abs(Int(wave.samples.first ?? 0)) < 800, "\(cue) starts abruptly")
            #expect(abs(Int(wave.samples.last ?? 0)) < 800, "\(cue) ends abruptly")
        }
    }
}
