import Accelerate
import AVFoundation
import AudioToolbox
import Foundation
import os

extension AudioEngine {
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

    private func ensureGraphOutputBuffer(_ buffer: inout [[Float]], channelCount: Int, frameLength: Int) {
        if buffer.count != channelCount {
            buffer = [[Float]](repeating: [Float](repeating: 0, count: frameLength), count: channelCount)
            return
        }
        let currentLength = buffer.first?.count ?? 0
        guard currentLength < frameLength else { return }
        let extra = frameLength - currentLength
        for index in 0..<channelCount {
            buffer[index].append(contentsOf: repeatElement(0, count: extra))
        }
    }

    private func applyGraphChangeCrossfade(
        _ processed: inout [[Float]],
        frameLength: Int,
        channelCount: Int,
        sampleRate: Double,
        signature: Int
    ) {
        if lastGraphSignature != signature {
            if lastGraphSignature != 0 {
                ensureGraphOutputBuffer(&graphChangePrevOutput, channelCount: channelCount, frameLength: frameLength)
                ensureGraphOutputBuffer(&lastOutputBuffer, channelCount: channelCount, frameLength: frameLength)
                for channel in 0..<channelCount {
                    for frame in 0..<frameLength {
                        graphChangePrevOutput[channel][frame] = lastOutputBuffer[channel][frame]
                    }
                }
                let total = max(1, Int(sampleRate * 0.2))
                graphChangeSamplesTotal = total
                graphChangeSamplesRemaining = total
            }
            lastGraphSignature = signature
        }

        if graphChangeSamplesRemaining > 0 {
            let total = max(graphChangeSamplesTotal, 1)
            let start = max(0, total - graphChangeSamplesRemaining)
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    let pos = min(total, start + frame)
                    let t = Float(pos) / Float(total)
                    processed[channel][frame] = graphChangePrevOutput[channel][frame] * (1 - t)
                        + processed[channel][frame] * t
                }
            }
            graphChangeSamplesRemaining = max(0, graphChangeSamplesRemaining - frameLength)
        }

        ensureGraphOutputBuffer(&lastOutputBuffer, channelCount: channelCount, frameLength: frameLength)
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                lastOutputBuffer[channel][frame] = processed[channel][frame]
            }
        }
    }

    private func interleaveInput(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameLength: Int,
        channelCount: Int
    ) -> [Float] {
        ensureInterleavedCapacity(frameLength: frameLength, channelCount: channelCount)
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                interleavedOutputBuffer[frame * channelCount + channel] = channelData[channel][frame]
            }
        }
        return interleavedOutputBuffer
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

    func enqueueAudioData(_ data: [Float], queue: AudioQueueRef) {
        os_unfair_lock_lock(&ringBufferLock)
        defer { os_unfair_lock_unlock(&ringBufferLock) }

        guard let buffer = ringBuffer else { return }

        let available = (ringReadIndex - ringWriteIndex - 1 + ringBufferCapacity) % ringBufferCapacity
        if available <= 0 {
            ringReadIndex = (ringReadIndex + 1) % ringBufferCapacity
        }

        let offset = ringWriteIndex * ringBufferFrameSize
        data.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            buffer.advanced(by: offset).assign(from: base, count: min(data.count, ringBufferFrameSize))
        }

        ringWriteIndex = (ringWriteIndex + 1) % ringBufferCapacity
    }

    fileprivate func getAudioDataForOutput(into destination: UnsafeMutablePointer<Float>, count: Int) -> Bool {
        os_unfair_lock_lock(&ringBufferLock)
        defer { os_unfair_lock_unlock(&ringBufferLock) }

        guard let buffer = ringBuffer else { return false }
        guard ringReadIndex != ringWriteIndex else { return false }

        let offset = ringReadIndex * ringBufferFrameSize
        destination.assign(from: buffer.advanced(by: offset), count: min(count, ringBufferFrameSize))
        ringReadIndex = (ringReadIndex + 1) % ringBufferCapacity
        return true
    }

    func interleavedData(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        // Lock-free: snapshot has its own lock, pendingResets has its own lock
        let snapshot = currentProcessingSnapshot()
        applyPendingResets()
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate

        let recordingActive = isRecordingActive()

        if snapshot.isReconfiguring {
            if recordingActive {
                let inputBuffer = deinterleavedInput(
                    channelData: channelData,
                    frameLength: frameLength,
                    channelCount: channelCount
                )
                recordIfNeeded(
                    inputBuffer,
                    frameLength: frameLength,
                    channelCount: channelCount,
                    sampleRate: sampleRate
                )
            }
            ensureInterleavedCapacity(frameLength: frameLength, channelCount: channelCount)
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    interleavedOutputBuffer[frame * channelCount + channel] = channelData[channel][frame]
                }
            }
            return interleavedOutputBuffer
        }

        if !snapshot.processingEnabled {
            if recordingActive {
                let inputBuffer = deinterleavedInput(
                    channelData: channelData,
                    frameLength: frameLength,
                    channelCount: channelCount
                )
                recordIfNeeded(
                    inputBuffer,
                    frameLength: frameLength,
                    channelCount: channelCount,
                    sampleRate: sampleRate
                )
            }
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

            let autoConnect = snapshot.splitAutoConnectEnd
            if channelCount < 2 {
            let (processed, levelSnapshot) = processGraph(
                inputBuffer: inputBuffer,
                channelCount: channelCount,
                sampleRate: sampleRate,
                nodes: snapshot.splitLeftNodes,
                    connections: snapshot.splitLeftConnections,
                    startID: snapshot.splitLeftStartID,
                    endID: snapshot.splitLeftEndID,
                autoConnectEnd: autoConnect,
                snapshot: snapshot
            )
            var output = processed
            applyGraphChangeCrossfade(
                &output,
                frameLength: frameLength,
                channelCount: channelCount,
                sampleRate: sampleRate,
                signature: snapshot.graphSignature
            )
            updateEffectLevelsIfNeeded(levelSnapshot)
            recordIfNeeded(
                output,
                frameLength: frameLength,
                channelCount: channelCount,
                sampleRate: sampleRate
            )
            return interleaveBuffer(output, frameLength: frameLength, channelCount: channelCount)
        }

            let leftInput = [inputBuffer[0]]
            let rightInput = [inputBuffer[1]]

            let (leftProcessed, leftSnapshot) = processGraph(
                inputBuffer: leftInput,
                channelCount: 1,
                sampleRate: sampleRate,
                nodes: snapshot.splitLeftNodes,
                connections: snapshot.splitLeftConnections,
                startID: snapshot.splitLeftStartID,
                endID: snapshot.splitLeftEndID,
                autoConnectEnd: autoConnect,
                snapshot: snapshot
            )
            let (rightProcessed, rightSnapshot) = processGraph(
                inputBuffer: rightInput,
                channelCount: 1,
                sampleRate: sampleRate,
                nodes: snapshot.splitRightNodes,
                connections: snapshot.splitRightConnections,
                startID: snapshot.splitRightStartID,
                endID: snapshot.splitRightEndID,
                autoConnectEnd: autoConnect,
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

            var output = combined
            applyGraphChangeCrossfade(
                &output,
                frameLength: frameLength,
                channelCount: channelCount,
                sampleRate: sampleRate,
                signature: snapshot.graphSignature
            )
            recordIfNeeded(
                output,
                frameLength: frameLength,
                channelCount: channelCount,
                sampleRate: sampleRate
            )
            return interleaveBuffer(output, frameLength: frameLength, channelCount: channelCount)
        }

        func renderManualGraph(inputBuffer: [[Float]]) -> ([[Float]], [UUID: Float]) {
            let autoConnect = snapshot.manualGraphAutoConnectEnd
            return processGraph(
                inputBuffer: inputBuffer,
                channelCount: channelCount,
                sampleRate: sampleRate,
                nodes: snapshot.manualGraphNodes,
                connections: snapshot.manualGraphConnections,
                startID: snapshot.manualGraphStartID,
                endID: snapshot.manualGraphEndID,
                autoConnectEnd: autoConnect,
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
            }

            let limited = snapshot.limiterEnabled ? applySoftLimiter(processedAudio) : processedAudio
            return (limited, levelSnapshot)
        }

        let useManual = snapshot.useManualGraph
        if lastUseManualGraph != useManual {
            graphTransitionFromManual = lastUseManualGraph
            graphTransitionSamplesTotal = max(1, Int(sampleRate * 0.2))
            graphTransitionSamplesRemaining = graphTransitionSamplesTotal
            lastUseManualGraph = useManual
        }

        if graphTransitionSamplesRemaining > 0 {
            let inputBuffer = deinterleavedInput(
                channelData: channelData,
                frameLength: frameLength,
                channelCount: channelCount
            )
            let (manualProcessed, manualLevels) = renderManualGraph(inputBuffer: inputBuffer)
            let (autoProcessed, autoLevels) = renderAutomaticGraph()

            let fromProcessed = graphTransitionFromManual ? manualProcessed : autoProcessed
            let toProcessed = graphTransitionFromManual ? autoProcessed : manualProcessed
            let targetLevels = useManual ? manualLevels : autoLevels

            var mixed = fromProcessed
            let total = max(graphTransitionSamplesTotal, 1)
            let start = total - graphTransitionSamplesRemaining
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    let t = min(1.0, Double(start + frame) / Double(total))
                    let fadeOut = Float(cos(t * 0.5 * Double.pi))
                    let fadeIn = Float(sin(t * 0.5 * Double.pi))
                    mixed[channel][frame] = fromProcessed[channel][frame] * fadeOut
                        + toProcessed[channel][frame] * fadeIn
                }
            }

            graphTransitionSamplesRemaining = max(0, graphTransitionSamplesRemaining - frameLength)
            if snapshot.limiterEnabled {
                mixed = applySoftLimiter(mixed)
            }
            var output = mixed
            applyGraphChangeCrossfade(
                &output,
                frameLength: frameLength,
                channelCount: channelCount,
                sampleRate: sampleRate,
                signature: snapshot.graphSignature
            )
            updateEffectLevelsIfNeeded(targetLevels)
            recordIfNeeded(
                output,
                frameLength: frameLength,
                channelCount: channelCount,
                sampleRate: sampleRate
            )
            return interleaveBuffer(output, frameLength: frameLength, channelCount: channelCount)
        }

        if useManual {
            let inputBuffer = deinterleavedInput(
                channelData: channelData,
                frameLength: frameLength,
                channelCount: channelCount
            )
            let (processed, levelSnapshot) = renderManualGraph(inputBuffer: inputBuffer)
            var output = processed
            applyGraphChangeCrossfade(
                &output,
                frameLength: frameLength,
                channelCount: channelCount,
                sampleRate: sampleRate,
                signature: snapshot.graphSignature
            )
            updateEffectLevelsIfNeeded(levelSnapshot)
            recordIfNeeded(
                output,
                frameLength: frameLength,
                channelCount: channelCount,
                sampleRate: sampleRate
            )
            return interleaveBuffer(output, frameLength: frameLength, channelCount: channelCount)
        }

        let (processedAudio, levelSnapshot) = renderAutomaticGraph()
        var output = processedAudio
        applyGraphChangeCrossfade(
            &output,
            frameLength: frameLength,
            channelCount: channelCount,
            sampleRate: sampleRate,
            signature: snapshot.graphSignature
        )
        updateEffectLevelsIfNeeded(levelSnapshot)
        recordIfNeeded(
            output,
            frameLength: frameLength,
            channelCount: channelCount,
            sampleRate: sampleRate
        )
        return interleaveBuffer(output, frameLength: frameLength, channelCount: channelCount)
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

    func initializeRingBuffer(frameSize: Int, capacity: Int = 10) {
        os_unfair_lock_lock(&ringBufferLock)
        defer { os_unfair_lock_unlock(&ringBufferLock) }

        if let buffer = ringBuffer {
            buffer.deallocate()
        }
        ringBufferFrameSize = frameSize
        ringBufferCapacity = max(2, capacity)
        let totalFloats = ringBufferFrameSize * ringBufferCapacity
        ringBuffer = UnsafeMutablePointer<Float>.allocate(capacity: totalFloats)
        ringBuffer?.initialize(repeating: 0, count: totalFloats)
        ringWriteIndex = 0
        ringReadIndex = 0
    }
}

// MARK: - AudioQueue Callback

func audioQueueOutputCallback(
    inUserData: UnsafeMutableRawPointer?,
    inAQ: AudioQueueRef,
    inBuffer: AudioQueueBufferRef
) {
    guard let userData = inUserData else { return }

    let audioEngine = Unmanaged<AudioEngine>.fromOpaque(userData).takeUnretainedValue()

    let floatBuffer = inBuffer.pointee.mAudioData.assumingMemoryBound(to: Float.self)
    let floatCount = Int(inBuffer.pointee.mAudioDataBytesCapacity) / MemoryLayout<Float>.size
    let bufferSize = Int(inBuffer.pointee.mAudioDataBytesCapacity)

    if !audioEngine.getAudioDataForOutput(into: floatBuffer, count: floatCount) {
        memset(inBuffer.pointee.mAudioData, 0, bufferSize)
    }
    inBuffer.pointee.mAudioDataByteSize = UInt32(bufferSize)

    // Re-enqueue the buffer
    AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
}
