import AVFoundation
import Foundation

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let capacity = AVAudioFrameCount(file.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
        fatalError("Could not allocate buffer for \(path)")
    }
    try file.read(into: buffer)
    guard let channels = buffer.floatChannelData else { fatalError("No float data") }

    let frames = Int(buffer.frameLength)
    let sampleRate = format.sampleRate
    var peak = 0.0
    var sumSquares = 0.0
    var nonFinite = 0
    var zeroRun = 0
    var longestZeroRun = 0
    var correlations: [Double: (sin: Double, cos: Double)] = [330: (0, 0), 550: (0, 0), 770: (0, 0)]

    for frame in 0..<frames {
        let sample = Double(channels[0][frame])
        if !sample.isFinite { nonFinite += 1; continue }
        peak = max(peak, abs(sample))
        sumSquares += sample * sample
        if abs(sample) < 1e-8 {
            zeroRun += 1
            longestZeroRun = max(longestZeroRun, zeroRun)
        } else {
            zeroRun = 0
        }
        for frequency in correlations.keys {
            let angle = 2 * Double.pi * frequency * Double(frame) / sampleRate
            correlations[frequency]!.sin += sample * sin(angle)
            correlations[frequency]!.cos += sample * cos(angle)
        }
    }

    var amplitudes: [String: Double] = [:]
    for (frequency, pair) in correlations {
        amplitudes[String(Int(frequency))] = 2 * hypot(pair.sin, pair.cos) / Double(frames)
    }
    let result: [String: Any] = [
        "file": url.lastPathComponent,
        "sampleRate": sampleRate,
        "channels": format.channelCount,
        "frames": frames,
        "durationSeconds": Double(frames) / sampleRate,
        "peak": peak,
        "rms": sqrt(sumSquares / Double(max(frames, 1))),
        "nonFiniteSamples": nonFinite,
        "longestNearZeroRunFrames": longestZeroRun,
        "toneAmplitudes": amplitudes
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}
