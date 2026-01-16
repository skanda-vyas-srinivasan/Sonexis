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

        var outEdges: [UUID: [UUID]] = [:]
        var inEdges: [UUID: [(UUID, Double)]] = [:]
        for connection in connections {
            outEdges[connection.fromNodeId, default: []].append(connection.toNodeId)
            inEdges[connection.toNodeId, default: []].append((connection.fromNodeId, connection.gain))
        }

        let reachable = reachableNodes(from: startID, outEdges: outEdges)

        if autoConnectEnd {
            var sinkNodes: [UUID] = []
            for nodeID in reachable where nodeID != startID && nodeID != endID {
                let outs = outEdges[nodeID] ?? []
                let hasReachableOut = outs.contains(where: { reachable.contains($0) && $0 != endID })
                let hasEndOut = outs.contains(endID)
                if !hasReachableOut && !hasEndOut {
                    sinkNodes.append(nodeID)
                }
            }

            for sink in sinkNodes {
                outEdges[sink, default: []].append(endID)
                inEdges[endID, default: []].append((sink, 1.0))
            }
        }

        var indegree: [UUID: Int] = [:]
        for node in nodes where reachable.contains(node.id) {
            let incoming = inEdges[node.id] ?? []
            let count = incoming.filter { $0.0 != startID }.count
            indegree[node.id] = count
        }

        var queue: [UUID] = nodes.compactMap { node in
            guard reachable.contains(node.id) else { return nil }
            return (indegree[node.id] ?? 0) == 0 ? node.id : nil
        }

        var outputBuffers: [UUID: [[Float]]] = [:]
        var levelSnapshot: [UUID: Float] = [:]

        while let nodeID = queue.first {
            queue.removeFirst()
            guard let node = nodes.first(where: { $0.id == nodeID }) else { continue }

            let inputs = inEdges[nodeID] ?? []
            let merged = mergeInputs(
                inputs: inputs,
                startID: startID,
                inputBuffer: inputBuffer,
                outputBuffers: outputBuffers,
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
            outputBuffers[nodeID] = processed

            for next in outEdges[nodeID] ?? [] {
                guard reachable.contains(next), next != endID else { continue }
                indegree[next, default: 0] -= 1
                if indegree[next] == 0 {
                    queue.append(next)
                }
            }
        }

        let endInputs = inEdges[endID] ?? []
        let mixed = mergeInputs(
            inputs: endInputs,
            startID: startID,
            inputBuffer: inputBuffer,
            outputBuffers: outputBuffers,
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
            let gainValue = Float(gain)
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    merged[channel][frame] += buffer[channel][frame] * gainValue
                }
            }
        }
        return merged
    }
}
