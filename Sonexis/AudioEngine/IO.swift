import Accelerate
import AVFoundation
import Foundation

extension AudioGraphProcessor {
    func processTapBuffer(
        frameCount: Int,
        channelCount: Int,
        sampleRate: Double
    ) -> AVAudioPCMBuffer? {
        let needsNewBuffer = processTapPCMBuffer == nil
            || processTapPCMBufferFrameCapacity < frameCount
            || processTapPCMBufferChannelCount != channelCount
            || processTapPCMBufferSampleRate != sampleRate

        if needsNewBuffer {
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
            ) else {
                return nil
            }
            processTapPCMBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
            processTapPCMBufferFrameCapacity = frameCount
            processTapPCMBufferChannelCount = channelCount
            processTapPCMBufferSampleRate = sampleRate
        }
        return processTapPCMBuffer
    }

    func deinterleavedInput(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameLength: Int,
        channelCount: Int
    ) -> [[Float]] {
        ensureDeinterleavedCapacity(frameLength: frameLength, channelCount: channelCount)
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                deinterleavedInputBuffer[channel][frame] = channelData[channel][frame]
            }
        }
        return deinterleavedInputBuffer
    }

    func ensureDeinterleavedCapacity(frameLength: Int, channelCount: Int) {
        if deinterleavedInputCapacity != frameLength || deinterleavedInputBuffer.count != channelCount {
            deinterleavedInputBuffer = [[Float]](
                repeating: [Float](repeating: 0, count: frameLength),
                count: channelCount
            )
            deinterleavedInputCapacity = frameLength
        }
    }

    func interleaveBuffer(_ buffer: [[Float]], frameLength: Int, channelCount: Int) -> [Float] {
        ensureInterleavedCapacity(frameLength: frameLength, channelCount: channelCount)
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                interleavedOutputBuffer[frame * channelCount + channel] = buffer[channel][frame]
            }
        }
        return interleavedOutputBuffer
    }

    func interleavedData(from buffer: AVAudioPCMBuffer) -> [Float] {
        let snapshot = currentSnapshot()
        var output = renderGraphAudio(from: buffer, snapshot: snapshot)
        graphOutputTransition.process(&output, frames: Int(buffer.frameLength),
            channels: Int(buffer.format.channelCount), sampleRate: buffer.format.sampleRate,
            identity: GraphOutputTransition.Identity(signature: snapshot.graphSignature,
                manual: snapshot.useManualGraph, split: snapshot.useSplitGraph,
                bypass: !snapshot.processingEnabled || snapshot.isReconfiguring,
                autoConnect: snapshot.manualGraphAutoConnectEnd,
                splitAutoConnect: snapshot.splitAutoConnectEnd))
        return output
    }

    private func renderGraphAudio(from buffer: AVAudioPCMBuffer, snapshot: ProcessingSnapshot) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        applyPendingResets()
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate

        if snapshot.isReconfiguring {
            ensureInterleavedCapacity(frameLength: frameLength, channelCount: channelCount)
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    interleavedOutputBuffer[frame * channelCount + channel] = channelData[channel][frame]
                }
            }
            return interleavedOutputBuffer
        }

        if !snapshot.processingEnabled {
            ensureInterleavedCapacity(frameLength: frameLength, channelCount: channelCount)
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    interleavedOutputBuffer[frame * channelCount + channel] = channelData[channel][frame]
                }
            }
            return interleavedOutputBuffer
        }

        // Initialize effect states
        initializeEffectStates(channelCount: channelCount)

        if snapshot.useSplitGraph {
            let inputBuffer = deinterleavedInput(
                channelData: channelData,
                frameLength: frameLength,
                channelCount: channelCount
            )

            if channelCount < 2 {
                let (processed, levelSnapshot) = processGraph(
                    inputBuffer: inputBuffer,
                    channelCount: channelCount,
                    sampleRate: sampleRate,
                    plan: snapshot.splitLeftRoutingPlan,
                    snapshot: snapshot
                )
                updateEffectLevelsIfNeeded(levelSnapshot)
                return interleaveBuffer(processed, frameLength: frameLength, channelCount: channelCount)
            }

            let leftInput = [inputBuffer[0]]
            let rightInput = [inputBuffer[1]]

            let (leftProcessed, leftSnapshot) = processGraph(
                inputBuffer: leftInput,
                channelCount: 1,
                sampleRate: sampleRate,
                plan: snapshot.splitLeftRoutingPlan,
                snapshot: snapshot
            )
            let (rightProcessed, rightSnapshot) = processGraph(
                inputBuffer: rightInput,
                channelCount: 1,
                sampleRate: sampleRate,
                plan: snapshot.splitRightRoutingPlan,
                snapshot: snapshot
            )

            var combined = inputBuffer
            if let leftChannel = leftProcessed.first {
                combined[0] = leftChannel
            }
            if combined.count > 1, let rightChannel = rightProcessed.first {
                combined[1] = rightChannel
            }

            var mergedSnapshot = leftSnapshot
            for (key, value) in rightSnapshot {
                mergedSnapshot[key] = value
            }
            updateEffectLevelsIfNeeded(mergedSnapshot)

            return interleaveBuffer(combined, frameLength: frameLength, channelCount: channelCount)
        }

        func renderManualGraph(inputBuffer: [[Float]]) -> ([[Float]], [UUID: Float]) {
            return processGraph(
                inputBuffer: inputBuffer,
                channelCount: channelCount,
                sampleRate: sampleRate,
                plan: snapshot.manualRoutingPlan,
                snapshot: snapshot
            )
        }

        func renderAutomaticGraph() -> ([[Float]], [UUID: Float]) {
            // Process audio through effect chain (reused buffer)
            ensureProcessingCapacity(frameLength: frameLength, channelCount: channelCount)
            var processedAudio = processingBuffer

            // Copy input to processed audio
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    processedAudio[channel][frame] = channelData[channel][frame]
                }
            }

            let orderedNodes: [EffectNode]
            if snapshot.effectChainOrder.isEmpty {
                orderedNodes = defaultEffectOrder.map { EffectNode(id: nil, type: $0) }
            } else {
                orderedNodes = snapshot.effectChainOrder
            }

            var levelSnapshot: [UUID: Float] = [:]
            for node in orderedNodes {
                applyEffect(
                    node.type,
                    to: &processedAudio,
                    sampleRate: sampleRate,
                    channelCount: channelCount,
                    frameLength: frameLength,
                    nodeId: node.id,
                    levelSnapshot: &levelSnapshot,
                    snapshot: snapshot
                )
                sanitizeEffectOutput(
                    &processedAudio,
                    effect: node.type,
                    nodeId: node.id,
                    frameLength: frameLength,
                    channelCount: channelCount
                )
            }

            let limited = snapshot.limiterEnabled ? applySoftLimiter(processedAudio) : processedAudio
            return (limited, levelSnapshot)
        }

        let useManual = snapshot.useManualGraph
        if useManual {
            let inputBuffer = deinterleavedInput(
                channelData: channelData,
                frameLength: frameLength,
                channelCount: channelCount
            )
            let (processed, levelSnapshot) = renderManualGraph(inputBuffer: inputBuffer)
            updateEffectLevelsIfNeeded(levelSnapshot)
            return interleaveBuffer(processed, frameLength: frameLength, channelCount: channelCount)
        }

        let (processedAudio, levelSnapshot) = renderAutomaticGraph()
        updateEffectLevelsIfNeeded(levelSnapshot)
        return interleaveBuffer(processedAudio, frameLength: frameLength, channelCount: channelCount)
    }

    func ensureInterleavedCapacity(frameLength: Int, channelCount: Int) {
        let required = frameLength * channelCount
        if interleavedOutputCapacity < required {
            interleavedOutputBuffer = [Float](repeating: 0, count: required)
            interleavedOutputCapacity = required
        }
    }

    func ensureProcessingCapacity(frameLength: Int, channelCount: Int) {
        if processingFrameCapacity != frameLength || processingBuffer.count != channelCount {
            processingBuffer = [[Float]](
                repeating: [Float](repeating: 0, count: frameLength),
                count: channelCount
            )
            processingFrameCapacity = frameLength
        }
    }

}
