import Accelerate
import Foundation

extension AudioEngine {
    func processManualGraph(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameLength: Int,
        channelCount: Int,
        sampleRate: Double,
        snapshot: ProcessingSnapshot
    ) -> [Float] {
        let inputBuffer = deinterleavedInput(channelData: channelData, frameLength: frameLength, channelCount: channelCount)
        let (processed, levelSnapshot) = processGraph(
            inputBuffer: inputBuffer,
            channelCount: channelCount,
            sampleRate: sampleRate,
            plan: snapshot.manualRoutingPlan,
            snapshot: snapshot
        )
        updateEffectLevelsIfNeeded(levelSnapshot)
        return interleaveBuffer(processed, frameLength: frameLength, channelCount: channelCount)
    }

    func processGraph(
        inputBuffer: [[Float]],
        channelCount: Int,
        sampleRate: Double,
        plan: GraphRoutingPlan,
        snapshot: ProcessingSnapshot
    ) -> ([[Float]], [UUID: Float]) {
        guard plan.mode != .passthrough, let startID = plan.startID else { return (inputBuffer, [:]) }
        if plan.mode == .empty {
            return (snapshot.limiterEnabled ? applySoftLimiter(inputBuffer) : inputBuffer, [:])
        }

        // Routing was prepared with this immutable snapshot. Only sample
        // buffers and existing DSP state change on the processing worker.
        graphOutputBuffers.removeAll(keepingCapacity: true)
        var levelSnapshot: [UUID: Float] = [:]
        for step in plan.steps {
            let merged = mergeInputs(
                inputs: step.inputs,
                startID: startID,
                inputBuffer: inputBuffer,
                outputBuffers: graphOutputBuffers,
                frameLength: inputBuffer.first?.count ?? 0,
                channelCount: channelCount
            )

            var processed = merged
            applyEffect(
                step.type,
                to: &processed,
                sampleRate: sampleRate,
                channelCount: channelCount,
                frameLength: inputBuffer.first?.count ?? 0,
                nodeId: step.id,
                levelSnapshot: &levelSnapshot,
                snapshot: snapshot
            )
            sanitizeEffectOutput(
                &processed,
                effect: step.type,
                nodeId: step.id,
                frameLength: inputBuffer.first?.count ?? 0,
                channelCount: channelCount
            )
            graphOutputBuffers[step.id] = processed
        }

        let mixed = mergeInputs(
            inputs: plan.endInputs,
            startID: startID,
            inputBuffer: inputBuffer,
            outputBuffers: graphOutputBuffers,
            frameLength: inputBuffer.first?.count ?? 0,
            channelCount: channelCount
        )
        let limited = snapshot.limiterEnabled ? applySoftLimiter(mixed) : mixed

        return (limited, levelSnapshot)
    }

    func updateEffectLevelsIfNeeded(_ levelSnapshot: [UUID: Float]) {
        guard !levelSnapshot.isEmpty else { return }
        levelUpdateCounter += 1
        if levelUpdateCounter % 8 == 0 {
            let snapshot = levelSnapshot
            DispatchQueue.main.async {
                self.effectLevels = snapshot
            }
        }
    }

    private func mergeInputs(
        inputs: [(UUID, Double)],
        startID: UUID,
        inputBuffer: [[Float]],
        outputBuffers: [UUID: [[Float]]],
        frameLength: Int,
        channelCount: Int
    ) -> [[Float]] {
        var merged = [[Float]](repeating: [Float](repeating: 0, count: frameLength), count: channelCount)
        guard !inputs.isEmpty else { return merged }

        for (source, gain) in inputs {
            let sourceBuffer: [[Float]]?
            if source == startID {
                sourceBuffer = inputBuffer
            } else {
                sourceBuffer = outputBuffers[source]
            }

            guard let buffer = sourceBuffer else { continue }
            var gainValue = Float(gain)
            for channel in 0..<channelCount {
                // vDSP_vsma: merged = merged + (buffer * gain)
                vDSP_vsma(buffer[channel], 1, &gainValue, merged[channel], 1, &merged[channel], 1, vDSP_Length(frameLength))
            }
        }
        return merged
    }
}
