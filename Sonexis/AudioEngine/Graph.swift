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
        let autoConnect = snapshot.manualGraphAutoConnectEnd
        let (processed, levelSnapshot) = processGraph(
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
        updateEffectLevelsIfNeeded(levelSnapshot)
        recordIfNeeded(
            processed,
            frameLength: frameLength,
            channelCount: channelCount,
            sampleRate: sampleRate
        )
        return interleaveBuffer(processed, frameLength: frameLength, channelCount: channelCount)
    }

    func processGraph(
        inputBuffer: [[Float]],
        channelCount: Int,
        sampleRate: Double,
        nodes: [BeginnerNode],
        connections: [BeginnerConnection],
        startID: UUID?,
        endID: UUID?,
        autoConnectEnd: Bool = true,
        snapshot: ProcessingSnapshot
    ) -> ([[Float]], [UUID: Float]) {
        guard let startID, let endID else {
            return (inputBuffer, [:])
        }

        // Clear and reuse pre-allocated scratch buffers (avoids allocation)
        for key in graphOutEdges.keys { graphOutEdges[key]?.removeAll(keepingCapacity: true) }
        for key in graphInEdges.keys { graphInEdges[key]?.removeAll(keepingCapacity: true) }
        graphOutputBuffers.removeAll(keepingCapacity: true)
        graphIndegree.removeAll(keepingCapacity: true)
        graphQueue.removeAll(keepingCapacity: true)

        for connection in connections {
            graphOutEdges[connection.fromNodeId, default: []].append(connection.toNodeId)
            graphInEdges[connection.toNodeId, default: []].append((connection.fromNodeId, connection.gain))
        }

        let reachable = reachableNodes(from: startID, outEdges: graphOutEdges)

        if autoConnectEnd {
            for nodeID in reachable where nodeID != startID && nodeID != endID {
                let outs = graphOutEdges[nodeID] ?? []
                let hasReachableOut = outs.contains(where: { reachable.contains($0) && $0 != endID })
                let hasEndOut = outs.contains(endID)
                if !hasReachableOut && !hasEndOut {
                    graphOutEdges[nodeID, default: []].append(endID)
                    graphInEdges[endID, default: []].append((nodeID, 1.0))
                }
            }
        }

        for node in nodes where reachable.contains(node.id) {
            let incoming = graphInEdges[node.id] ?? []
            let count = incoming.filter { $0.0 != startID }.count
            graphIndegree[node.id] = count
            if count == 0 {
                graphQueue.append(node.id)
            }
        }

        var levelSnapshot: [UUID: Float] = [:]

        while let nodeID = graphQueue.first {
            graphQueue.removeFirst()
            guard let node = nodes.first(where: { $0.id == nodeID }) else { continue }

            let inputs = graphInEdges[nodeID] ?? []
            let merged = mergeInputs(
                inputs: inputs,
                startID: startID,
                inputBuffer: inputBuffer,
                outputBuffers: graphOutputBuffers,
                frameLength: inputBuffer.first?.count ?? 0,
                channelCount: channelCount
            )

            var processed = merged
            applyEffect(
                node.type,
                to: &processed,
                sampleRate: sampleRate,
                channelCount: channelCount,
                frameLength: inputBuffer.first?.count ?? 0,
                nodeId: node.id,
                levelSnapshot: &levelSnapshot,
                snapshot: snapshot
            )
            graphOutputBuffers[nodeID] = processed

            for next in graphOutEdges[nodeID] ?? [] {
                guard reachable.contains(next), next != endID else { continue }
                graphIndegree[next, default: 0] -= 1
                if graphIndegree[next] == 0 {
                    graphQueue.append(next)
                }
            }
        }

        let endInputs = graphInEdges[endID] ?? []
        let mixed = mergeInputs(
            inputs: endInputs,
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

    private func reachableNodes(from startID: UUID, outEdges: [UUID: [UUID]]) -> Set<UUID> {
        var visited: Set<UUID> = [startID]
        var queue: [UUID] = [startID]

        while let current = queue.first {
            queue.removeFirst()
            for next in outEdges[current] ?? [] {
                if !visited.contains(next) {
                    visited.insert(next)
                    queue.append(next)
                }
            }
        }
        return visited
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
