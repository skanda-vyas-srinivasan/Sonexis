import Foundation

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func key(_ value: Int, manual: Bool = false, split: Bool = false, bypass: Bool = false) -> GraphOutputTransition.Identity {
    .init(signature: value, manual: manual, split: split, bypass: bypass, autoConnect: true, splitAutoConnect: true)
}
func render(_ transition: GraphOutputTransition, _ input: [Float], key identity: GraphOutputTransition.Identity,
            channels: Int = 1, rate: Double = 48_000) -> [Float] {
    var output = input
    transition.process(&output, frames: input.count / channels, channels: channels, sampleRate: rate, identity: identity)
    return output
}

// No-edit audio is bit-for-bit unchanged, including startup and zero crossings.
let plain = GraphOutputTransition()
let tone = (0..<2048).map { Float(sin(Double($0) * 2 * .pi * 440 / 48_000)) * 0.7 }
expect(render(plain, tone, key: key(0)) == tone, "Startup changed audio")
expect(render(plain, tone, key: key(0)) == tone, "Stable graph changed audio")

// Same-signal topology edits must not introduce silence or correlated gain.
for rate in [44_100.0, 48_000.0, 96_000.0] {
    let t = GraphOutputTransition()
    _ = render(t, [Float](repeating: 0.7, count: 1024), key: key(1), rate: rate)
    let result = render(t, [Float](repeating: 0.7, count: 2048), key: key(2), rate: rate)
    expect(result.allSatisfy { abs($0 - 0.7) < 0.000001 }, "Same-signal edit dipped or boosted")
}

// A hard polarity change starts at the last emitted sample, stays bounded,
// reaches the target, and behaves identically across arbitrary block sizes.
func changed(blocks: [Int]) -> [Float] {
    let t = GraphOutputTransition()
    _ = render(t, [0.8, -0.4], key: key(1), channels: 2)
    var output: [Float] = []
    for size in blocks {
        output += render(t, Array(repeating: [Float]([-0.6, 0.9]), count: size).flatMap { $0 }, key: key(2), channels: 2)
    }
    return output
}
let whole = changed(blocks: [512])
expect(changed(blocks: [1, 7, 63, 128, 2, 311]) == whole, "Ramp depends on block boundaries")
expect(whole[0] == 0.8 && whole[1] == -0.4, "Edit boundary discontinuity")
for frame in 0..<512 {
    expect((-0.600001...0.800001).contains(Double(whole[frame * 2])), "Left overshoot")
    expect((-0.400001...0.900001).contains(Double(whole[frame * 2 + 1])), "Right overshoot")
}
expect(whole[478] == -0.6 && whole[479] == 0.9, "Ramp did not finish at five milliseconds")
let maxStep = (1..<512).map { abs(whole[$0 * 2] - whole[($0 - 1) * 2]) }.max()!
expect(maxStep < 0.01, "Abrupt polarity step")

// Mode/bypass changes and edits arriving mid-ramp use the current output.
let rapid = GraphOutputTransition()
var last: Float = 0.4
_ = render(rapid, [last], key: key(1))
for id in 2..<100 {
    let identity = key(id, manual: id % 2 == 0, split: id % 3 == 0, bypass: id % 4 == 0)
    let output = render(rapid, [Float](repeating: id % 2 == 0 ? -0.8 : 0.8, count: 17), key: identity)
    expect(output.first == last, "Rapid edit jumped")
    expect(output.allSatisfy { $0.isFinite && abs($0) <= 0.800001 }, "Rapid edit overshoot")
    last = output.last!
}
let mode = GraphOutputTransition()
_ = render(mode, [0.5], key: key(1))
expect(render(mode, [-0.5], key: key(1, manual: true)) == [0.5], "Mode-only change missed")
_ = render(mode, [0.5], key: key(1, manual: true))
expect(render(mode, [-0.5], key: key(1, manual: true, bypass: true)).first! > 0, "Bypass-only change missed")

// Format changes and restarts cannot leak previous channel samples.
expect(render(rapid, [-0.2, 0.3], key: key(100), channels: 2) == [-0.2, 0.3], "Stale channel history")
expect(render(rapid, [0.1, -0.1], key: key(101), channels: 2, rate: 96_000) == [0.1, -0.1], "Stale rate history")
rapid.reset()
expect(render(rapid, [-0.9], key: key(102)) == [-0.9], "Stale restart history")

// Continuous tone through an edit has no inserted silent run and remains bounded.
let wave = GraphOutputTransition()
_ = render(wave, Array(tone.prefix(512)), key: key(1))
let edited = render(wave, Array(tone.dropFirst(512)), key: key(2))
var silentRun = 0
for sample in edited {
    silentRun = abs(sample) < 0.000001 ? silentRun + 1 : 0
    expect(silentRun < 2, "Inserted silence in sustained tone")
    expect(abs(sample) <= 0.700001, "Tone gain spike")
}
expect(Array(edited.dropFirst(240)) == Array(tone.dropFirst(752)), "Ramp altered steady-state tone")
print("PASS: unchanged audio, no mute/gain boost, bounded polarity changes, variable blocks, rapid edits, mode/bypass changes, format/reset isolation, sustained tone")
