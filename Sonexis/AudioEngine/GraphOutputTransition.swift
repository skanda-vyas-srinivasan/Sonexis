import Foundation

/// Worker-owned de-click ramp. Only the selected graph renders, so shared DSP
/// and AU instances advance once per input block. No old graph is replayed.
final class GraphOutputTransition {
    struct Identity: Equatable {
        let signature: Int
        let manual: Bool
        let split: Bool
        let bypass: Bool
        let autoConnect: Bool
        let splitAutoConnect: Bool
    }

    private var identity: Identity?
    private var sampleRate: Double = 0
    private var lastSamples: [Float] = []
    private var anchors: [Float] = []
    private var position = 0
    private var duration = 0

    /// Call only while the worker is stopped.
    func reset() {
        identity = nil
        lastSamples.removeAll(keepingCapacity: true)
        anchors.removeAll(keepingCapacity: true)
        position = 0
        duration = 0
    }

    func process(_ samples: inout [Float], frames: Int, channels: Int,
                 sampleRate: Double, identity next: Identity) {
        guard frames > 0, channels > 0, samples.count >= frames * channels else { return }
        if lastSamples.count != channels || self.sampleRate != sampleRate || identity == nil {
            lastSamples = [Float](repeating: 0, count: channels)
            anchors = [Float](repeating: 0, count: channels)
            self.sampleRate = sampleRate
            identity = next
            duration = 0
            position = 0
        } else if identity != next {
            // Restart from the actual last emitted sample, including during
            // rapid edits. Five milliseconds replaces the former 140 ms dip.
            for channel in 0..<channels { anchors[channel] = lastSamples[channel] }
            duration = max(2, Int(sampleRate * 0.005))
            position = 0
            identity = next
        }

        for frame in 0..<frames {
            if position < duration {
                let t = Float(position) / Float(duration - 1)
                let weight = t * t * (3 - 2 * t)
                for channel in 0..<channels {
                    let index = frame * channels + channel
                    // Convex weights avoid the correlated-signal gain boost
                    // of an equal-power mix. No forced zero or added latency.
                    samples[index] = anchors[channel] * (1 - weight) + samples[index] * weight
                }
                position += 1
            }
        }
        for channel in 0..<channels {
            lastSamples[channel] = samples[(frames - 1) * channels + channel]
        }
    }
}
