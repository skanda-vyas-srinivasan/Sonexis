import Foundation
@testable import Sonexis

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
func input(frames: Int, channels: Int, rate: Double, offset: Int) -> [Float] {
    (0..<frames * channels).map { i in
        let hz = i % channels == 0 ? 997.0 : 173.0
        return Float(0.1 * sin(2 * .pi * hz * Double(offset + i / channels) / rate))
    }
}
func render(_ engine: AudioEngine, _ samples: [Float], channels: Int, rate: Double) -> [Float] {
    var output = [Float](repeating: .nan, count: samples.count)
    samples.withUnsafeBufferPointer { source in output.withUnsafeMutableBufferPointer { destination in
        engine.processSystemAudio(input: source.baseAddress!, output: destination.baseAddress!,
            frameCount: samples.count / channels, channelCount: channels, sampleRate: rate)
    } }
    expect(output.allSatisfy(\.isFinite), "Pitch returned invalid samples")
    return output
}
func verify(_ samples: [Float], channels: Int, rate: Double, semitones: Double) {
    var longest = 0, run = 0
    for frame in 0..<samples.count / channels {
        let silent = (0..<channels).allSatisfy { abs(samples[frame * channels + $0]) < 1e-8 }
        run = silent ? run + 1 : 0
        longest = max(longest, run)
    }
    expect(longest <= 2, "Pitch activation inserted \(longest) silent frames")
    // A continuity fix must still produce the requested pitch, not stay dry.
    let start = samples.count / channels - Int(rate)
    for channel in 0..<channels {
        let expectedHz = (channel == 0 ? 997.0 : 173.0) * pow(2, semitones / 12)
        // Spectral energy avoids counting small high-frequency artifacts as
        // extra zero crossings. Decimation is adequate for these test tones.
        let tone = stride(from: start, to: samples.count / channels, by: 8).map { Double(samples[$0 * channels + channel]) }
        func power(at hz: Double) -> Double {
            let coefficient = 2 * cos(2 * .pi * hz / (rate / 8))
            var previous = 0.0, previous2 = 0.0
            for sample in tone {
                let value = sample + coefficient * previous - previous2
                previous2 = previous; previous = value
            }
            return previous * previous + previous2 * previous2 - coefficient * previous * previous2
        }
        let candidates = (-12...12).map { expectedHz + Double($0) }
        let best = candidates.max { power(at: $0) < power(at: $1) }!
        let dryHz = channel == 0 ? 997.0 : 173.0
        expect(abs(best - expectedHz) <= 2 && power(at: best) > 4 * power(at: dryHz),
               "Pitch did not settle at the requested frequency: \(best) vs \(expectedHz)")
    }
    expect(samples.map { abs($0) }.max()! < 0.2, "Activation unexpectedly amplified the signal")
    print("PASS: rate=\(rate), channels=\(channels), semitones=\(semitones), longestSilentFrames=\(longest), shifted frequency verified")
    fflush(stdout)
}

for rate in [44_100.0, 48_000.0, 96_000.0] {
    for channels in [1, 2] {
        for semitones in [7.0, -7.0, 12.0, -12.0] {
            let engine = AudioEngine(observeSystemLifecycle: false)
            engine.processTapInputTrimDB = -15
            engine.processTapOutputMakeupDB = 15
            engine.processTapOutputCeilingEnabled = false
            var node = BeginnerNode(type: .rubberBandPitch)
            engine.updateEffectChain([node]); engine.publishProcessingState()
            var offset = 0
            for _ in 0..<40 {
                _ = render(engine, input(frames: 1024, channels: channels, rate: rate, offset: offset), channels: channels, rate: rate)
                offset += 1024
            }
            // Exercise reactivation as well as first activation, keeping node ID.
            for activation in 0..<3 {
                node.isEnabled = true
                node.parameters.rubberBandPitchSemitones = semitones
                engine.updateEffectChain([node]); engine.publishProcessingState()
                var output: [Float] = []
                var block = 0
                while output.count / channels < Int(rate * 2.5) {
                    let frames = activation == 0 ? 1024 : [17, 128, 4096, 31, 1024][block % 5]
                    let dry = input(frames: frames, channels: channels, rate: rate, offset: offset)
                    let wet = render(engine, dry, channels: channels, rate: rate)
                    if block == 0 && activation < 2 {
                        expect(zip(dry, wet).allSatisfy { abs($0 - $1) < 1e-6 }, "Warm-up must retain current audio")
                    }
                    output += wet; offset += frames; block += 1
                }
                verify(output, channels: channels, rate: rate, semitones: semitones)
                if activation == 1 { node.isEnabled = false }
                else { node.parameters.rubberBandPitchSemitones = 0 }
                engine.updateEffectChain([node]); engine.publishProcessingState()
                for bypassBlock in 0..<8 {
                    let dry = input(frames: 1024, channels: channels, rate: rate, offset: offset)
                    let out = render(engine, dry, channels: channels, rate: rate)
                    // Node bypass changes graph identity and uses the existing
                    // five-millisecond de-click ramp. Check transparency after it.
                    let skip = activation == 1 && bypassBlock == 0 ? Int(rate * 0.005) * channels : 0
                    expect(zip(dry.dropFirst(skip), out.dropFirst(skip)).allSatisfy { abs($0 - $1) < 1e-6 },
                           "Zero pitch and bypass must stay transparent after the graph ramp")
                    offset += 1024
                }
            }
        }
    }
}

// Readiness must be independent of signal level: silence stays silent, then a
// later tone must be pitched once it travels through the existing reservoir.
let quiet = AudioEngine(observeSystemLifecycle: false)
var shifted = BeginnerNode(type: .rubberBandPitch)
shifted.parameters.rubberBandPitchSemitones = 7
quiet.updateEffectChain([shifted]); quiet.publishProcessingState()
for _ in 0..<80 {
    expect(render(quiet, [Float](repeating: 0, count: 2048), channels: 2, rate: 48_000).allSatisfy { $0 == 0 }, "Pitch generated audio during silence")
}
var later: [Float] = []
for block in 0..<150 {
    later += render(quiet, input(frames: 1024, channels: 2, rate: 48_000, offset: block * 1024), channels: 2, rate: 48_000)
}
verify(Array(later.suffix(48_000 * 2)), channels: 2, rate: 48_000, semitones: 7)
print("PASS: silent startup followed by pitched audio")
