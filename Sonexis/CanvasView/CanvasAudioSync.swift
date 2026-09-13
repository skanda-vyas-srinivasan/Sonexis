import SwiftUI
import AppKit

extension CanvasView {
    func applyChainToEngine(
        reason: String = "graph edit",
        forceAudioApply: Bool = false
    ) {
        // Publish the latest workspace immediately; quitting before the audio
        // apply debounce fires must not lose the final canvas edit.
        audioEngine.updateGraphSnapshot(currentGraphSnapshot())
        if forceAudioApply {
            cancelPendingAudioGraphApply()
            performChainApplyToEngine(reason: reason, forceAudioApply: true)
            return
        }

        pendingAudioGraphApplyReason = reason
        pendingAudioGraphApplyForce = pendingAudioGraphApplyForce || forceAudioApply
        pendingAudioGraphApplyWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            let reason = pendingAudioGraphApplyReason
            let force = pendingAudioGraphApplyForce
            pendingAudioGraphApplyWorkItem = nil
            pendingAudioGraphApplyForce = false
            performChainApplyToEngine(reason: reason, forceAudioApply: force)
        }
        pendingAudioGraphApplyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: workItem)
    }

    func cancelPendingAudioGraphApply() {
        pendingAudioGraphApplyWorkItem?.cancel()
        pendingAudioGraphApplyWorkItem = nil
        pendingAudioGraphApplyForce = false
    }

    func performChainApplyToEngine(
        reason: String,
        forceAudioApply: Bool
    ) {
        let signature = currentAudioGraphSignature()
        if !forceAudioApply, lastAppliedAudioGraphSignature == signature {
            audioEngine.updateGraphSnapshot(currentGraphSnapshot())
            if debugGraphLifecycle {
                print("Audio graph apply skipped: reason=\(reason), unchanged signature=\(signature)")
            }
            return
        }
        lastAppliedAudioGraphSignature = signature
        if debugGraphLifecycle {
            print("Audio graph apply: reason=\(reason), force=\(forceAudioApply), signature=\(signature), nodes=\(effectChain.count)")
        }

        if graphMode == .split {
            let leftNodes = effectChain.filter { $0.lane == .left }
            let rightNodes = effectChain.filter { $0.lane == .right }
            let leftConnections = wiringMode == .automatic
                ? autoConnections(for: .left)
                : manualConnections.filter { laneForConnection($0) == .left }
            let rightConnections = wiringMode == .automatic
                ? autoConnections(for: .right)
                : manualConnections.filter { laneForConnection($0) == .right }

            audioEngine.updateEffectGraphSplit(
                leftNodes: leftNodes,
                leftConnections: leftConnections,
                leftStartID: leftStartNodeID,
                leftEndID: leftEndNodeID,
                rightNodes: rightNodes,
                rightConnections: rightConnections,
                rightStartID: rightStartNodeID,
                rightEndID: rightEndNodeID,
                autoConnectEnd: autoConnectEnd
            )
            // Debug overlay removed.
        } else {
            let path = chainPath(for: nil)
            if wiringMode == .automatic {
                // Debug output removed.
            } else {
                let edges = manualGraphEdges(lane: nil)
                // Debug output removed.
            }
            if wiringMode == .manual {
                audioEngine.updateEffectGraph(
                    nodes: effectChain,
                    connections: manualConnections,
                    startID: startNodeID,
                    endID: endNodeID,
                    autoConnectEnd: autoConnectEnd
                )
                // Debug overlay removed.
            } else {
                if autoGainOverrides.isEmpty {
                    audioEngine.updateEffectChain(path)
                } else {
                    let connections = autoConnections(for: .left)
                    audioEngine.updateEffectGraph(
                        nodes: effectChain,
                        connections: connections,
                        startID: startNodeID,
                        endID: endNodeID
                    )
                }
                // Debug overlay removed.
            }
        }
        audioEngine.updateGraphSnapshot(currentGraphSnapshot())
    }

    func updateChainParametersOnly() {
        audioEngine.updateEffectNodeRuntimeState(effectChain)
        audioEngine.updateGraphSnapshot(currentGraphSnapshot())
    }

    func currentAudioGraphSignature() -> Int {
        var hasher = Hasher()
        hasher.combine(graphMode.rawValue)
        hasher.combine(wiringMode == .manual ? "manual" : "automatic")
        hasher.combine(autoConnectEnd)

        switch graphMode {
        case .single:
            combineAudioNodes(into: &hasher, nodes: audioRelevantNodes(for: nil))
            combineAudioConnections(into: &hasher, connections: audioRelevantConnections(for: nil))
        case .split:
            hasher.combine("left")
            combineAudioNodes(into: &hasher, nodes: audioRelevantNodes(for: .left))
            combineAudioConnections(into: &hasher, connections: audioRelevantConnections(for: .left))
            hasher.combine("right")
            combineAudioNodes(into: &hasher, nodes: audioRelevantNodes(for: .right))
            combineAudioConnections(into: &hasher, connections: audioRelevantConnections(for: .right))
        }

        return hasher.finalize()
    }

    func audioRelevantNodes(for lane: GraphLane?) -> [BeginnerNode] {
        if wiringMode == .automatic {
            return chainPath(for: lane)
        }

        let nodes = graphMode == .split
            ? effectChain.filter { $0.lane == lane }
            : effectChain
        return nodes.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func audioRelevantConnections(for lane: GraphLane?) -> [BeginnerConnection] {
        if wiringMode == .automatic {
            if autoGainOverrides.isEmpty {
                return []
            }
            return autoConnections(for: lane ?? .left)
        }

        let connections = graphMode == .split
            ? manualConnections.filter { laneForConnection($0) == lane }
            : manualConnections
        return connections.sorted {
            if $0.fromNodeId.uuidString != $1.fromNodeId.uuidString {
                return $0.fromNodeId.uuidString < $1.fromNodeId.uuidString
            }
            return $0.toNodeId.uuidString < $1.toNodeId.uuidString
        }
    }

    func combineAudioNodes(into hasher: inout Hasher, nodes: [BeginnerNode]) {
        hasher.combine(nodes.count)
        for node in nodes {
            hasher.combine(node.id)
            hasher.combine(node.type.rawValue)
            hasher.combine(node.isEnabled)
            hasher.combine(node.lane.rawValue)
            if let plugin = node.plugin {
                hasher.combine(plugin.format.rawValue)
                hasher.combine(plugin.identifier)
                hasher.combine(plugin.componentType)
                hasher.combine(plugin.componentSubType)
                hasher.combine(plugin.componentManufacturer)
            }
        }
    }

    func combineAudioConnections(into hasher: inout Hasher, connections: [BeginnerConnection]) {
        hasher.combine(connections.count)
        for connection in connections {
            hasher.combine(connection.fromNodeId)
            hasher.combine(connection.toNodeId)
            hasher.combine(connection.gain)
        }
    }

    func bindingForEffect(_ id: UUID) -> Binding<BeginnerNode> {
        Binding(
            get: {
                effectChain.first(where: { $0.id == id }) ?? BeginnerNode(type: .bassBoost)
            },
            set: { updated in
                guard let index = effectChain.firstIndex(where: { $0.id == id }) else { return }
                effectChain[index] = updated
            }
        )
    }

    func applyGraphSnapshot(
        _ snapshot: GraphSnapshot,
        mode: GraphLoadMode = .audioAndVisual,
        reason: String = "direct restore"
    ) {
        let nodes = snapshot.hasNodeParameters ? snapshot.nodes : migrateNodeParameters(snapshot.nodes)
        let removedIds = Set(nodes.filter { $0.type == .pitchShift || $0.type.isRetired }.map { $0.id })
        let filteredNodes = nodes.filter { $0.type != .pitchShift && !$0.type.isRetired }
        minimumCanvasSize = .zero
        effectChain = filteredNodes
        manualConnections = snapshot.connections.filter { !removedIds.contains($0.fromNodeId) && !removedIds.contains($0.toNodeId) }
        let filteredAutoGains = snapshot.autoGainOverrides.filter {
            !removedIds.contains($0.fromNodeId) && !removedIds.contains($0.toNodeId)
        }
        autoGainOverrides = Dictionary(
            uniqueKeysWithValues: filteredAutoGains.map {
                (WireKey(from: $0.fromNodeId, to: $0.toNodeId), $0.gain)
            }
        )
        startNodeID = snapshot.startNodeID
        endNodeID = snapshot.endNodeID
        leftStartNodeID = snapshot.leftStartNodeID ?? leftStartNodeID
        leftEndNodeID = snapshot.leftEndNodeID ?? leftEndNodeID
        rightStartNodeID = snapshot.rightStartNodeID ?? rightStartNodeID
        rightEndNodeID = snapshot.rightEndNodeID ?? rightEndNodeID
        graphMode = snapshot.graphMode
        wiringMode = snapshot.wiringMode == .manual ? .manual : .automatic
        autoConnectEnd = snapshot.autoConnectEnd
        if graphMode == .split {
            manualConnections.removeAll { laneForConnection($0) == nil }
        }
        let maxAccent = effectChain.map(\.accentIndex).max() ?? -1
        nextAccentIndex = (maxAccent + 1) % accentPalette.count
        selectedNodeIDs.removeAll()
        selectedWireID = nil
        selectedAutoWire = nil

        switch mode {
        case .visualOnly:
            cancelPendingAudioGraphApply()
            let signature = currentAudioGraphSignature()
            lastAppliedAudioGraphSignature = signature
            audioEngine.updateGraphSnapshot(currentGraphSnapshot())
            if debugGraphLifecycle {
                print("Graph restore visual-only: reason=\(reason), signature=\(signature), nodes=\(effectChain.count)")
            }
        case .audioAndVisual:
            applyChainToEngine(reason: "restore: \(reason)", forceAudioApply: true)
        }
    }

    func migrateNodeParameters(_ nodes: [BeginnerNode]) -> [BeginnerNode] {
        nodes.map { node in
            var updated = node
            var params = NodeEffectParameters.defaults()
            switch node.type {
            case .enhancer:
                params.enhancerAmount = audioEngine.enhancerAmount
            case .bassBoost:
                params.bassBoostAmount = audioEngine.bassBoostAmount
            case .pitchShift:
                params.nightcoreIntensity = audioEngine.nightcoreIntensity
            case .rubberBandPitch:
                params.rubberBandPitchSemitones = audioEngine.rubberBandPitchSemitones
            case .clarity:
                params.clarityAmount = audioEngine.clarityAmount
            case .deMud:
                params.deMudStrength = audioEngine.deMudStrength
            case .simpleEQ, .appleThreeBandEQ:
                params.eqBass = audioEngine.eqBass
                params.eqMids = audioEngine.eqMids
                params.eqTreble = audioEngine.eqTreble
            case .tenBandEQ:
                params.tenBandGains = [
                    audioEngine.tenBand31,
                    audioEngine.tenBand62,
                    audioEngine.tenBand125,
                    audioEngine.tenBand250,
                    audioEngine.tenBand500,
                    audioEngine.tenBand1k,
                    audioEngine.tenBand2k,
                    audioEngine.tenBand4k,
                    audioEngine.tenBand8k,
                    audioEngine.tenBand16k
                ]
            case .compressor:
                params.compressorStrength = audioEngine.compressorStrength
                params.compressorThresholdDB = audioEngine.compressorThresholdDB
                params.compressorRatio = audioEngine.compressorRatio
                params.compressorAttackMS = audioEngine.compressorAttackMS
                params.compressorReleaseMS = audioEngine.compressorReleaseMS
                params.compressorMakeupDB = audioEngine.compressorMakeupDB
                params.compressorMix = audioEngine.compressorMix
            case .reverb:
                params.reverbMix = audioEngine.reverbMix
                params.reverbSize = audioEngine.reverbSize
            case .stereoWidth:
                params.stereoWidthAmount = audioEngine.stereoWidthAmount
            case .delay:
                params.delayTime = audioEngine.delayTime
                params.delayFeedback = audioEngine.delayFeedback
                params.delayMix = audioEngine.delayMix
            case .amp:
                params.ampInputGain = audioEngine.ampInputGain
                params.ampDrive = audioEngine.ampDrive
                params.ampOutputGain = audioEngine.ampOutputGain
                params.ampMix = audioEngine.ampMix
            case .distortion:
                params.distortionDrive = audioEngine.distortionDrive
                params.distortionMix = audioEngine.distortionMix
            case .tremolo:
                params.tremoloRate = audioEngine.tremoloRate
                params.tremoloDepth = audioEngine.tremoloDepth
            case .autoPan:
                params.autoPanRate = audioEngine.autoPanRate
                params.autoPanDepth = audioEngine.autoPanDepth
            case .chorus:
                params.chorusRate = audioEngine.chorusRate
                params.chorusDepth = audioEngine.chorusDepth
                params.chorusMix = audioEngine.chorusMix
            case .phaser:
                params.phaserRate = audioEngine.phaserRate
                params.phaserDepth = audioEngine.phaserDepth
            case .flanger:
                params.flangerRate = audioEngine.flangerRate
                params.flangerDepth = audioEngine.flangerDepth
                params.flangerFeedback = audioEngine.flangerFeedback
                params.flangerMix = audioEngine.flangerMix
            case .bitcrusher:
                params.bitcrusherBitDepth = audioEngine.bitcrusherBitDepth
                params.bitcrusherDownsample = audioEngine.bitcrusherDownsample
                params.bitcrusherMix = audioEngine.bitcrusherMix
            case .tapeSaturation:
                params.tapeSaturationDrive = audioEngine.tapeSaturationDrive
                params.tapeSaturationMix = audioEngine.tapeSaturationMix
            case .nightDrive, .chromePunch, .midnightGlow, .afterglow:
                break
            case .resampling:
                params.resampleRate = audioEngine.resampleRate
                params.resampleCrossfade = audioEngine.resampleCrossfade
            case .plugin:
                break
            }
            updated.parameters = params
            return updated
        }
    }

    func currentGraphSnapshot() -> GraphSnapshot {
        let nodesWithState = effectChain.map { node in
            guard node.type == .plugin, var plugin = node.plugin else { return node }
            var updated = node
            plugin.stateData = audioEngine.pluginStateData(for: node.id) ?? plugin.stateData
            updated.plugin = plugin
            return updated
        }

        return GraphSnapshot(
            graphMode: graphMode,
            wiringMode: wiringMode == .manual ? .manual : .automatic,
            autoConnectEnd: autoConnectEnd,
            nodes: nodesWithState,
            connections: manualConnections,
            autoGainOverrides: autoGainOverrides.map {
                BeginnerConnection(fromNodeId: $0.key.from, toNodeId: $0.key.to, gain: $0.value)
            },
            startNodeID: startNodeID,
            endNodeID: endNodeID,
            leftStartNodeID: leftStartNodeID,
            leftEndNodeID: leftEndNodeID,
            rightStartNodeID: rightStartNodeID,
            rightEndNodeID: rightEndNodeID,
            hasNodeParameters: true
        )
    }

    func manualGraphEdges(lane: GraphLane?) -> [String] {
        var edges: [String] = []

        func name(for id: UUID) -> String {
            if graphMode == .split {
                if id == leftStartNodeID { return "Start L" }
                if id == leftEndNodeID { return "End L" }
                if id == rightStartNodeID { return "Start R" }
                if id == rightEndNodeID { return "End R" }
            } else {
                if id == startNodeID { return "Start" }
                if id == endNodeID { return "End" }
            }
            return effectChain.first(where: { $0.id == id })?.type.rawValue ?? "?"
        }

        for connection in manualConnections {
            if graphMode == .split, laneForConnection(connection) != lane { continue }
            edges.append("\(name(for: connection.fromNodeId))→\(name(for: connection.toNodeId))")
        }

        for nodeID in implicitEndNodes(lane: lane) {
            let endLabel = graphMode == .split ? (lane == .right ? "End R" : "End L") : "End"
            edges.append("\(name(for: nodeID))→\(endLabel)")
        }

        return edges
    }

    func edgeStrings(from connections: [BeginnerConnection], lane: GraphLane?) -> [String] {
        func name(for id: UUID) -> String {
            if graphMode == .split {
                if id == leftStartNodeID { return "Start L" }
                if id == leftEndNodeID { return "End L" }
                if id == rightStartNodeID { return "Start R" }
                if id == rightEndNodeID { return "End R" }
            } else {
                if id == startNodeID { return "Start" }
                if id == endNodeID { return "End" }
            }
            return effectChain.first(where: { $0.id == id })?.type.rawValue ?? "?"
        }

        return connections.map { connection in
            "\(name(for: connection.fromNodeId))→\(name(for: connection.toNodeId))"
        }
    }

}
