import Foundation

extension AudioEngine {
    // MARK: - Preset Support

    func getCurrentEffectChain() -> EffectChainSnapshot {
        var activeEffects: [EffectChainSnapshot.EffectSnapshot] = []

        // Bass Boost
        if bassBoostEnabled {
            let params = EffectChainSnapshot.EffectParameters(bassBoostAmount: bassBoostAmount)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .bassBoost, isEnabled: true, parameters: params))
        }

        // Nightcore
        if nightcoreEnabled {
            let params = EffectChainSnapshot.EffectParameters(nightcoreIntensity: nightcoreIntensity)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .pitchShift, isEnabled: true, parameters: params))
        }

        // Clarity
        if clarityEnabled {
            let params = EffectChainSnapshot.EffectParameters(clarityAmount: clarityAmount)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .clarity, isEnabled: true, parameters: params))
        }

        // De-Mud
        if deMudEnabled {
            let params = EffectChainSnapshot.EffectParameters(deMudStrength: deMudStrength)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .deMud, isEnabled: true, parameters: params))
        }

        // Simple EQ
        if simpleEQEnabled {
            let params = EffectChainSnapshot.EffectParameters(eqBass: eqBass, eqMids: eqMids, eqTreble: eqTreble)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .simpleEQ, isEnabled: true, parameters: params))
        }

        // 10-Band EQ
        if tenBandEQEnabled {
            let params = EffectChainSnapshot.EffectParameters(tenBandGains: tenBandGains)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .tenBandEQ, isEnabled: true, parameters: params))
        }

        // Compressor
        if compressorEnabled {
            let params = EffectChainSnapshot.EffectParameters(
                compressorStrength: compressorStrength,
                compressorThresholdDB: compressorThresholdDB,
                compressorRatio: compressorRatio,
                compressorAttackMS: compressorAttackMS,
                compressorReleaseMS: compressorReleaseMS,
                compressorMakeupDB: compressorMakeupDB,
                compressorMix: compressorMix
            )
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .compressor, isEnabled: true, parameters: params))
        }


        // Reverb
        if reverbEnabled {
            let params = EffectChainSnapshot.EffectParameters(reverbMix: reverbMix, reverbSize: reverbSize)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .reverb, isEnabled: true, parameters: params))
        }

        // Delay
        if delayEnabled {
            let params = EffectChainSnapshot.EffectParameters(
                delayTime: delayTime,
                delayFeedback: delayFeedback,
                delayMix: delayMix
            )
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .delay, isEnabled: true, parameters: params))
        }

        // Amp
        if ampEnabled {
            let params = EffectChainSnapshot.EffectParameters(
                ampInputGain: ampInputGain,
                ampDrive: ampDrive,
                ampOutputGain: ampOutputGain,
                ampMix: ampMix
            )
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .amp, isEnabled: true, parameters: params))
        }

        // Distortion
        if distortionEnabled {
            let params = EffectChainSnapshot.EffectParameters(
                distortionDrive: distortionDrive,
                distortionMix: distortionMix
            )
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .distortion, isEnabled: true, parameters: params))
        }

        // Tremolo
        if tremoloEnabled {
            let params = EffectChainSnapshot.EffectParameters(
                tremoloRate: tremoloRate,
                tremoloDepth: tremoloDepth
            )
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .tremolo, isEnabled: true, parameters: params))
        }

        // Auto Pan
        if autoPanEnabled {
            let params = EffectChainSnapshot.EffectParameters(
                autoPanRate: autoPanRate,
                autoPanDepth: autoPanDepth
            )
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .autoPan, isEnabled: true, parameters: params))
        }

        // Chorus
        if chorusEnabled {
            let params = EffectChainSnapshot.EffectParameters(
                chorusRate: chorusRate,
                chorusDepth: chorusDepth,
                chorusMix: chorusMix
            )
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .chorus, isEnabled: true, parameters: params))
        }

        // Phaser
        if phaserEnabled {
            let params = EffectChainSnapshot.EffectParameters(
                phaserRate: phaserRate,
                phaserDepth: phaserDepth
            )
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .phaser, isEnabled: true, parameters: params))
        }

        // Flanger
        if flangerEnabled {
            let params = EffectChainSnapshot.EffectParameters(
                flangerRate: flangerRate,
                flangerDepth: flangerDepth,
                flangerFeedback: flangerFeedback,
                flangerMix: flangerMix
            )
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .flanger, isEnabled: true, parameters: params))
        }

        // Bitcrusher
        if bitcrusherEnabled {
            let params = EffectChainSnapshot.EffectParameters(
                bitcrusherBitDepth: bitcrusherBitDepth,
                bitcrusherDownsample: bitcrusherDownsample,
                bitcrusherMix: bitcrusherMix
            )
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .bitcrusher, isEnabled: true, parameters: params))
        }

        // Tape Saturation
        if tapeSaturationEnabled {
            let params = EffectChainSnapshot.EffectParameters(
                tapeSaturationDrive: tapeSaturationDrive,
                tapeSaturationMix: tapeSaturationMix
            )
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .tapeSaturation, isEnabled: true, parameters: params))
        }

        // Stereo Width
        if stereoWidthEnabled {
            let params = EffectChainSnapshot.EffectParameters(stereoWidthAmount: stereoWidthAmount)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .stereoWidth, isEnabled: true, parameters: params))
        }

        // Rubber Band Pitch
        if rubberBandPitchEnabled {
            let params = EffectChainSnapshot.EffectParameters(rubberBandPitchSemitones: rubberBandPitchSemitones)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .rubberBandPitch, isEnabled: true, parameters: params))
        }

        return EffectChainSnapshot(activeEffects: activeEffects.filter { !$0.type.isRetired })
    }

    func applyEffectChain(_ chain: EffectChainSnapshot) {
        // First disable all effects
        bassBoostEnabled = false
        enhancerEnabled = false
        nightcoreEnabled = false
        clarityEnabled = false
        deMudEnabled = false
        simpleEQEnabled = false
        tenBandEQEnabled = false
        compressorEnabled = false
        reverbEnabled = false
        stereoWidthEnabled = false
        delayEnabled = false
        ampEnabled = false
        distortionEnabled = false
        tremoloEnabled = false
        autoPanEnabled = false
        chorusEnabled = false
        phaserEnabled = false
        flangerEnabled = false
        bitcrusherEnabled = false
        tapeSaturationEnabled = false
        resampleEnabled = false
        rubberBandPitchEnabled = false
        resetTenBandValues()

        // Then apply each effect from the chain
        for effect in chain.activeEffects where !effect.type.isRetired {
            let params = effect.parameters

            switch effect.type {
            case .bassBoost:
                bassBoostEnabled = effect.isEnabled
                if let amount = params.bassBoostAmount {
                    bassBoostAmount = amount
                }

            case .enhancer:
                enhancerEnabled = false

            case .pitchShift: // Nightcore
                nightcoreEnabled = effect.isEnabled
                if let intensity = params.nightcoreIntensity {
                    nightcoreIntensity = intensity
                }

            case .clarity:
                clarityEnabled = effect.isEnabled
                if let amount = params.clarityAmount {
                    clarityAmount = amount
                }

            case .deMud:
                deMudEnabled = effect.isEnabled
                if let strength = params.deMudStrength {
                    deMudStrength = strength
                }

            case .simpleEQ:
                simpleEQEnabled = effect.isEnabled
                if let bass = params.eqBass { eqBass = bass }
                if let mids = params.eqMids { eqMids = mids }
                if let treble = params.eqTreble { eqTreble = treble }

            case .appleThreeBandEQ:
                if let bass = params.eqBass { eqBass = bass }
                if let mids = params.eqMids { eqMids = mids }
                if let treble = params.eqTreble { eqTreble = treble }

            case .tenBandEQ:
                tenBandEQEnabled = effect.isEnabled
                if let gains = params.tenBandGains, gains.count == tenBandFrequencies.count {
                    tenBand31 = gains[0]
                    tenBand62 = gains[1]
                    tenBand125 = gains[2]
                    tenBand250 = gains[3]
                    tenBand500 = gains[4]
                    tenBand1k = gains[5]
                    tenBand2k = gains[6]
                    tenBand4k = gains[7]
                    tenBand8k = gains[8]
                    tenBand16k = gains[9]
                }

            case .compressor:
                compressorEnabled = effect.isEnabled
                if let strength = params.compressorStrength {
                    compressorStrength = strength
                }
                if let threshold = params.compressorThresholdDB {
                    compressorThresholdDB = threshold
                }
                if let ratio = params.compressorRatio {
                    compressorRatio = ratio
                }
                if let attack = params.compressorAttackMS {
                    compressorAttackMS = attack
                }
                if let release = params.compressorReleaseMS {
                    compressorReleaseMS = release
                }
                if let makeup = params.compressorMakeupDB {
                    compressorMakeupDB = makeup
                }
                if let mix = params.compressorMix {
                    compressorMix = mix
                }

            case .reverb:
                reverbEnabled = effect.isEnabled
                if let mix = params.reverbMix { reverbMix = mix }
                if let size = params.reverbSize { reverbSize = size }

            case .stereoWidth:
                stereoWidthEnabled = effect.isEnabled
                if let amount = params.stereoWidthAmount {
                    stereoWidthAmount = amount
                }

            case .delay:
                delayEnabled = effect.isEnabled
                if let time = params.delayTime { delayTime = time }
                if let feedback = params.delayFeedback { delayFeedback = feedback }
                if let mix = params.delayMix { delayMix = mix }

            case .amp:
                ampEnabled = effect.isEnabled
                if let input = params.ampInputGain { ampInputGain = input }
                if let drive = params.ampDrive { ampDrive = drive }
                if let gain = params.ampOutputGain { ampOutputGain = gain }
                if let mix = params.ampMix { ampMix = mix }

            case .distortion:
                distortionEnabled = effect.isEnabled
                if let drive = params.distortionDrive { distortionDrive = drive }
                if let mix = params.distortionMix { distortionMix = mix }

            case .tremolo:
                tremoloEnabled = effect.isEnabled
                if let rate = params.tremoloRate { tremoloRate = rate }
                if let depth = params.tremoloDepth { tremoloDepth = depth }

            case .autoPan:
                autoPanEnabled = effect.isEnabled
                if let rate = params.autoPanRate { autoPanRate = rate }
                if let depth = params.autoPanDepth { autoPanDepth = depth }

            case .chorus:
                chorusEnabled = effect.isEnabled
                if let rate = params.chorusRate { chorusRate = rate }
                if let depth = params.chorusDepth { chorusDepth = depth }
                if let mix = params.chorusMix { chorusMix = mix }

            case .phaser:
                phaserEnabled = effect.isEnabled
                if let rate = params.phaserRate { phaserRate = rate }
                if let depth = params.phaserDepth { phaserDepth = depth }

            case .flanger:
                flangerEnabled = effect.isEnabled
                if let rate = params.flangerRate { flangerRate = rate }
                if let depth = params.flangerDepth { flangerDepth = depth }
                if let feedback = params.flangerFeedback { flangerFeedback = feedback }
                if let mix = params.flangerMix { flangerMix = mix }

            case .bitcrusher:
                bitcrusherEnabled = effect.isEnabled
                if let bitDepth = params.bitcrusherBitDepth { bitcrusherBitDepth = bitDepth }
                if let downsample = params.bitcrusherDownsample { bitcrusherDownsample = downsample }
                if let mix = params.bitcrusherMix { bitcrusherMix = mix }

            case .tapeSaturation:
                tapeSaturationEnabled = effect.isEnabled
                if let drive = params.tapeSaturationDrive { tapeSaturationDrive = drive }
                if let mix = params.tapeSaturationMix { tapeSaturationMix = mix }

            case .resampling:
                resampleEnabled = false

            case .rubberBandPitch:
                rubberBandPitchEnabled = effect.isEnabled
                if let semitones = params.rubberBandPitchSemitones {
                    rubberBandPitchSemitones = semitones
                }
            case .nightDrive, .chromePunch, .midnightGlow, .afterglow:
                break
            case .plugin:
                break
            }
        }

        // Debug output removed.
    }

    func updateEffectChain(_ chain: [BeginnerNode]) {
        let activeChain = chain.filter { !$0.type.isRetired }
        withEffectStateLock {
            effectChainOrder = activeChain
            useManualGraph = false
            useSplitGraph = false
            syncNodeState(activeChain)
        }
        pluginHost.sync(nodes: activeChain)
        scheduleSnapshotUpdate()

        let activeTypes = Set(activeChain.filter { $0.isEnabled }.map { $0.type })

        bassBoostEnabled = activeTypes.contains(.bassBoost)
        enhancerEnabled = false
        nightcoreEnabled = activeTypes.contains(.pitchShift)
        clarityEnabled = activeTypes.contains(.clarity)
        deMudEnabled = activeTypes.contains(.deMud)
        simpleEQEnabled = activeTypes.contains(.simpleEQ)
        tenBandEQEnabled = activeTypes.contains(.tenBandEQ)
        compressorEnabled = activeTypes.contains(.compressor)
        reverbEnabled = activeTypes.contains(.reverb)
        stereoWidthEnabled = activeTypes.contains(.stereoWidth)
        delayEnabled = activeTypes.contains(.delay)
        ampEnabled = activeTypes.contains(.amp)
        distortionEnabled = activeTypes.contains(.distortion)
        tremoloEnabled = activeTypes.contains(.tremolo)
        autoPanEnabled = activeTypes.contains(.autoPan)
        chorusEnabled = activeTypes.contains(.chorus)
        phaserEnabled = activeTypes.contains(.phaser)
        flangerEnabled = activeTypes.contains(.flanger)
        bitcrusherEnabled = activeTypes.contains(.bitcrusher)
        tapeSaturationEnabled = activeTypes.contains(.tapeSaturation)
        resampleEnabled = false
        rubberBandPitchEnabled = activeTypes.contains(.rubberBandPitch)

        if !activeTypes.contains(.tenBandEQ) {
            resetTenBandValues()
        }

        if chain.isEmpty {
            resetEffectState()
            DispatchQueue.main.async {
                self.effectLevels = [:]
            }
        }
        // Debug output removed.
    }

    func updateEffectGraph(
        nodes: [BeginnerNode],
        connections: [BeginnerConnection],
        startID: UUID,
        endID: UUID,
        autoConnectEnd: Bool = true
    ) {
        let activeNodes = nodes.filter { !$0.type.isRetired }
        let activeNodeIds = Set(activeNodes.map { $0.id }).union([startID, endID])
        let activeConnections = connections.filter {
            activeNodeIds.contains($0.fromNodeId) && activeNodeIds.contains($0.toNodeId)
        }
        withEffectStateLock {
            manualGraphNodes = activeNodes
            manualGraphConnections = activeConnections
            manualGraphStartID = startID
            manualGraphEndID = endID
            manualGraphAutoConnectEnd = autoConnectEnd
            useManualGraph = true
            useSplitGraph = false
            syncNodeState(activeNodes)
        }
        pluginHost.sync(nodes: activeNodes)
        scheduleSnapshotUpdate()

        let activeTypes = Set(activeNodes.filter { $0.isEnabled }.map { $0.type })
        bassBoostEnabled = activeTypes.contains(.bassBoost)
        enhancerEnabled = false
        nightcoreEnabled = activeTypes.contains(.pitchShift)
        clarityEnabled = activeTypes.contains(.clarity)
        deMudEnabled = activeTypes.contains(.deMud)
        simpleEQEnabled = activeTypes.contains(.simpleEQ)
        tenBandEQEnabled = activeTypes.contains(.tenBandEQ)
        compressorEnabled = activeTypes.contains(.compressor)
        reverbEnabled = activeTypes.contains(.reverb)
        stereoWidthEnabled = activeTypes.contains(.stereoWidth)
        delayEnabled = activeTypes.contains(.delay)
        ampEnabled = activeTypes.contains(.amp)
        distortionEnabled = activeTypes.contains(.distortion)
        tremoloEnabled = activeTypes.contains(.tremolo)
        autoPanEnabled = activeTypes.contains(.autoPan)
        chorusEnabled = activeTypes.contains(.chorus)
        phaserEnabled = activeTypes.contains(.phaser)
        flangerEnabled = activeTypes.contains(.flanger)
        bitcrusherEnabled = activeTypes.contains(.bitcrusher)
        tapeSaturationEnabled = activeTypes.contains(.tapeSaturation)
        resampleEnabled = false
        rubberBandPitchEnabled = activeTypes.contains(.rubberBandPitch)
    }

    func updateEffectGraphSplit(
        leftNodes: [BeginnerNode],
        leftConnections: [BeginnerConnection],
        leftStartID: UUID,
        leftEndID: UUID,
        rightNodes: [BeginnerNode],
        rightConnections: [BeginnerConnection],
        rightStartID: UUID,
        rightEndID: UUID,
        autoConnectEnd: Bool = true
    ) {
        let activeLeftNodes = leftNodes.filter { !$0.type.isRetired }
        let activeRightNodes = rightNodes.filter { !$0.type.isRetired }
        let activeLeftIds = Set(activeLeftNodes.map { $0.id }).union([leftStartID, leftEndID])
        let activeRightIds = Set(activeRightNodes.map { $0.id }).union([rightStartID, rightEndID])
        let activeLeftConnections = leftConnections.filter {
            activeLeftIds.contains($0.fromNodeId) && activeLeftIds.contains($0.toNodeId)
        }
        let activeRightConnections = rightConnections.filter {
            activeRightIds.contains($0.fromNodeId) && activeRightIds.contains($0.toNodeId)
        }
        withEffectStateLock {
            splitLeftNodes = activeLeftNodes
            splitLeftConnections = activeLeftConnections
            splitLeftStartID = leftStartID
            splitLeftEndID = leftEndID
            splitRightNodes = activeRightNodes
            splitRightConnections = activeRightConnections
            splitRightStartID = rightStartID
            splitRightEndID = rightEndID
            splitAutoConnectEnd = autoConnectEnd
            useSplitGraph = true
            useManualGraph = false
            syncNodeState(activeLeftNodes + activeRightNodes)
        }
        pluginHost.sync(nodes: activeLeftNodes + activeRightNodes)
        scheduleSnapshotUpdate()

        let activeTypes = Set((activeLeftNodes + activeRightNodes).filter { $0.isEnabled }.map { $0.type })
        bassBoostEnabled = activeTypes.contains(.bassBoost)
        enhancerEnabled = false
        nightcoreEnabled = activeTypes.contains(.pitchShift)
        clarityEnabled = activeTypes.contains(.clarity)
        deMudEnabled = activeTypes.contains(.deMud)
        simpleEQEnabled = activeTypes.contains(.simpleEQ)
        tenBandEQEnabled = activeTypes.contains(.tenBandEQ)
        compressorEnabled = activeTypes.contains(.compressor)
        reverbEnabled = activeTypes.contains(.reverb)
        stereoWidthEnabled = activeTypes.contains(.stereoWidth)
        delayEnabled = activeTypes.contains(.delay)
        ampEnabled = activeTypes.contains(.amp)
        distortionEnabled = activeTypes.contains(.distortion)
        tremoloEnabled = activeTypes.contains(.tremolo)
        autoPanEnabled = activeTypes.contains(.autoPan)
        chorusEnabled = activeTypes.contains(.chorus)
        phaserEnabled = activeTypes.contains(.phaser)
        flangerEnabled = activeTypes.contains(.flanger)
        bitcrusherEnabled = activeTypes.contains(.bitcrusher)
        tapeSaturationEnabled = activeTypes.contains(.tapeSaturation)
        resampleEnabled = false
        rubberBandPitchEnabled = activeTypes.contains(.rubberBandPitch)
    }

    func updateGraphSnapshot(_ snapshot: GraphSnapshot?) {
        currentGraphSnapshot = snapshot
    }

    func requestGraphLoad(
        _ snapshot: GraphSnapshot?,
        mode: GraphLoadMode = .audioAndVisual,
        reason: String = "unspecified"
    ) {
        guard let snapshot else {
            pendingGraphLoadRequest = nil
            return
        }
        print("Graph load requested: mode=\(mode), reason=\(reason), nodes=\(snapshot.nodes.count)")
        pendingGraphLoadRequest = GraphLoadRequest(
            snapshot: snapshot,
            mode: mode,
            reason: reason
        )
    }

    func updateEffectNodeRuntimeState(_ nodes: [BeginnerNode]) {
        let activeNodes = nodes.filter { !$0.type.isRetired }
        withEffectStateLock {
            syncNodeState(activeNodes)
        }
        scheduleSnapshotUpdate()
    }

    private func syncNodeState(_ nodes: [BeginnerNode]) {
        let ids = Set(nodes.map { $0.id })
        let activeRubberBandPitchIDs = Set(
            nodes
                .filter {
                    $0.type == .rubberBandPitch
                        && $0.isEnabled
                        && abs($0.parameters.rubberBandPitchSemitones) > 0.01
                }
                .map { $0.id }
        )
        let shouldResetRubberBandPitch = rubberBandNodes.keys.contains { !activeRubberBandPitchIDs.contains($0) }
            || nodes.contains {
                $0.type == .rubberBandPitch
                    && (!$0.isEnabled || abs($0.parameters.rubberBandPitchSemitones) <= 0.01)
            }

        if shouldResetRubberBandPitch {
            enqueueReset(.rubberBand)
        }

        nodeParameters = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.parameters) })
        nodeEnabled = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.isEnabled) })

        func keepActiveNodes<Value>(_ dictionary: inout [UUID: Value]) {
            dictionary = dictionary.filter { ids.contains($0.key) }
        }

        keepActiveNodes(&bassBoostStatesByNode)
        keepActiveNodes(&bassBoostSmoothedGainByNode)
        keepActiveNodes(&bassBoostVDSPDelayByNode)
        keepActiveNodes(&enhancerSmoothedGainByNode)
        keepActiveNodes(&enhancerLowVDSPDelayByNode)
        keepActiveNodes(&enhancerMidVDSPDelayByNode)
        keepActiveNodes(&enhancerHighVDSPDelayByNode)
        keepActiveNodes(&clarityStatesByNode)
        keepActiveNodes(&claritySmoothedGainByNode)
        keepActiveNodes(&clarityVDSPDelayByNode)
        keepActiveNodes(&nightcoreStatesByNode)
        keepActiveNodes(&nightcoreSmoothedGainByNode)
        keepActiveNodes(&deMudStatesByNode)
        keepActiveNodes(&deMudSmoothedGainByNode)
        keepActiveNodes(&deMudVDSPDelayByNode)
        keepActiveNodes(&eqBassStatesByNode)
        keepActiveNodes(&eqMidsStatesByNode)
        keepActiveNodes(&eqTrebleStatesByNode)
        keepActiveNodes(&eqBassVDSPDelayByNode)
        keepActiveNodes(&eqMidsVDSPDelayByNode)
        keepActiveNodes(&eqTrebleVDSPDelayByNode)
        keepActiveNodes(&simpleEQSmoothedGainByNode)
        keepActiveNodes(&appleThreeBandEQProcessorsByNode)
        keepActiveNodes(&appleThreeBandEQDryScratchByNode)
        keepActiveNodes(&appleThreeBandEQSmoothedGainByNode)
        keepActiveNodes(&tenBandStatesByNode)
        keepActiveNodes(&tenBandEQSmoothedGainByNode)
        keepActiveNodes(&tenBandVDSPDelaysByNode)
        keepActiveNodes(&compressorEnvelopeByNode)
        keepActiveNodes(&compressorSmoothedGainByNode)
        keepActiveNodes(&reverbStatesByNode)
        keepActiveNodes(&reverbSmoothedGainByNode)
        keepActiveNodes(&delayBuffersByNode)
        keepActiveNodes(&delayWriteIndexByNode)
        keepActiveNodes(&delaySmoothedGainByNode)
        keepActiveNodes(&delayParameterStateByNode)
        keepActiveNodes(&tremoloPhaseByNode)
        keepActiveNodes(&tremoloSmoothedGainByNode)
        keepActiveNodes(&autoPanPhaseByNode)
        keepActiveNodes(&autoPanSmoothedGainByNode)
        keepActiveNodes(&autoPanParameterStateByNode)
        keepActiveNodes(&chorusBuffersByNode)
        keepActiveNodes(&chorusWriteIndexByNode)
        keepActiveNodes(&chorusPhaseByNode)
        keepActiveNodes(&chorusSmoothedGainByNode)
        keepActiveNodes(&chorusParameterStateByNode)
        keepActiveNodes(&flangerBuffersByNode)
        keepActiveNodes(&flangerWriteIndexByNode)
        keepActiveNodes(&flangerPhaseByNode)
        keepActiveNodes(&flangerSmoothedGainByNode)
        keepActiveNodes(&flangerParameterStateByNode)
        keepActiveNodes(&phaserStatesByNode)
        keepActiveNodes(&phaserPhaseByNode)
        keepActiveNodes(&phaserFeedbackSamplesByNode)
        keepActiveNodes(&phaserSmoothedGainByNode)
        keepActiveNodes(&phaserParameterStateByNode)
        keepActiveNodes(&bitcrusherHoldCountersByNode)
        keepActiveNodes(&bitcrusherHoldValuesByNode)
        keepActiveNodes(&bitcrusherSmoothedGainByNode)
        keepActiveNodes(&resampleBuffersByNode)
        keepActiveNodes(&resampleWriteIndexByNode)
        keepActiveNodes(&resampleReadPhaseByNode)
        keepActiveNodes(&resampleCrossfadeRemainingByNode)
        keepActiveNodes(&resampleCrossfadeTotalByNode)
        keepActiveNodes(&resampleCrossfadeStartPhaseByNode)
        keepActiveNodes(&resampleCrossfadeTargetPhaseByNode)
        keepActiveNodes(&resampleSmoothedGainByNode)
        keepActiveNodes(&ampSmoothedGainByNode)
        keepActiveNodes(&distortionSmoothedGainByNode)
        keepActiveNodes(&tapeSaturationSmoothedGainByNode)
        keepActiveNodes(&signatureEffectStatesByNode)
        keepActiveNodes(&stereoWidthSmoothedGainByNode)
        keepActiveNodes(&rubberBandNodes)
        keepActiveNodes(&rubberBandScratchByNode)
        keepActiveNodes(&rubberBandSmoothedGainByNode)
        keepActiveNodes(&pluginDryScratchByNode)
        keepActiveNodes(&pluginWetScratchByNode)
        keepActiveNodes(&pluginCrossfadeRemainingByNode)
        keepActiveNodes(&pluginCrossfadeTotalByNode)
        keepActiveNodes(&pluginCrossfadeOutRemainingByNode)
        keepActiveNodes(&pluginCrossfadeOutTotalByNode)
        keepActiveNodes(&pluginWasEnabledByNode)
        keepActiveNodes(&pluginWasReadyByNode)
        keepActiveNodes(&pluginStableOutputCountByNode)
        keepActiveNodes(&pluginHasStableOutputByNode)
        keepActiveNodes(&pluginReadyDelaySamplesByNode)
    }
}
