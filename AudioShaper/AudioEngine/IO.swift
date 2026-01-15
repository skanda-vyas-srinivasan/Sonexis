import AVFoundation
import AudioToolbox
import Foundation

extension AudioEngine {
    func deinterleavedInput(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameLength: Int,
        channelCount: Int
    ) -> [[Float]] {
        var output = [[Float]](repeating: [Float](repeating: 0, count: frameLength), count: channelCount)
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                output[channel][frame] = channelData[channel][frame]
            }
        }
        return output
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
        guard let buffer = ringBuffer else { return }
        ringBufferLock.lock()
        defer { ringBufferLock.unlock() }

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
        guard let buffer = ringBuffer else { return false }
        ringBufferLock.lock()
        defer { ringBufferLock.unlock() }

        guard ringReadIndex != ringWriteIndex else { return false }

        let offset = ringReadIndex * ringBufferFrameSize
        destination.assign(from: buffer.advanced(by: offset), count: min(count, ringBufferFrameSize))
        ringReadIndex = (ringReadIndex + 1) % ringBufferCapacity
        return true
    }

    func interleavedData(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        effectStateLock.lock()
        defer { effectStateLock.unlock() }

        let snapshot = currentProcessingSnapshot()
        applyPendingResetsUnlocked()
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
                updateEffectLevelsIfNeeded(levelSnapshot)
                return interleaveBuffer(processed, frameLength: frameLength, channelCount: channelCount)
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

            return interleaveBuffer(combined, frameLength: frameLength, channelCount: channelCount)
        }

        if snapshot.useManualGraph {
            return processManualGraph(
                channelData: channelData,
                frameLength: frameLength,
                channelCount: channelCount,
                sampleRate: sampleRate,
                snapshot: snapshot
            )
        }

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

        if !levelSnapshot.isEmpty {
            levelUpdateCounter += 1
            if levelUpdateCounter % 8 == 0 {
                let snapshot = levelSnapshot
                DispatchQueue.main.async {
                    self.effectLevels = snapshot
                }
            }
        }

        // Convert to interleaved format
        ensureInterleavedCapacity(frameLength: frameLength, channelCount: channelCount)
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                interleavedOutputBuffer[frame * channelCount + channel] = processedAudio[channel][frame]
            }
        }

        return interleavedOutputBuffer
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
        ringBufferLock.lock()
        defer { ringBufferLock.unlock() }

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
