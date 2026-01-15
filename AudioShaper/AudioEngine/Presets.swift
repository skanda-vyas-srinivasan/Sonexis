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
            let params = EffectChainSnapshot.EffectParameters(compressorStrength: compressorStrength)
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

        // Resampling
        if resampleEnabled {
            let params = EffectChainSnapshot.EffectParameters(resampleRate: resampleRate, resampleCrossfade: resampleCrossfade)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .resampling, isEnabled: true, parameters: params))
        }

        // Rubber Band Pitch
        if rubberBandPitchEnabled {
            let params = EffectChainSnapshot.EffectParameters(rubberBandPitchSemitones: rubberBandPitchSemitones)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .rubberBandPitch, isEnabled: true, parameters: params))
        }

        return EffectChainSnapshot(activeEffects: activeEffects)
    }

    func applyEffectChain(_ chain: EffectChainSnapshot) {
        // First disable all effects
        bassBoostEnabled = false
        nightcoreEnabled = false
        clarityEnabled = false
        deMudEnabled = false
        simpleEQEnabled = false
        tenBandEQEnabled = false
        compressorEnabled = false
        reverbEnabled = false
        stereoWidthEnabled = false
        delayEnabled = false
        distortionEnabled = false
        tremoloEnabled = false
        chorusEnabled = false
        phaserEnabled = false
        flangerEnabled = false
        bitcrusherEnabled = false
        tapeSaturationEnabled = false
        resampleEnabled = false
        rubberBandPitchEnabled = false
        resetTenBandValues()

        // Then apply each effect from the chain
        for effect in chain.activeEffects {
            let params = effect.parameters

            switch effect.type {
            case .bassBoost:
                bassBoostEnabled = effect.isEnabled
                if let amount = params.bassBoostAmount {
                    bassBoostAmount = amount
                }

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

            case .distortion:
                distortionEnabled = effect.isEnabled
                if let drive = params.distortionDrive { distortionDrive = drive }
                if let mix = params.distortionMix { distortionMix = mix }

            case .tremolo:
                tremoloEnabled = effect.isEnabled
                if let rate = params.tremoloRate { tremoloRate = rate }
                if let depth = params.tremoloDepth { tremoloDepth = depth }

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
                resampleEnabled = effect.isEnabled
                if let rate = params.resampleRate { resampleRate = rate }
                if let crossfade = params.resampleCrossfade { resampleCrossfade = crossfade }

            case .rubberBandPitch:
                rubberBandPitchEnabled = effect.isEnabled
                if let semitones = params.rubberBandPitchSemitones {
                    rubberBandPitchSemitones = semitones
                }
            }
        }

        // Debug output removed.
    }

    func updateEffectChain(_ chain: [BeginnerNode]) {
        withEffectStateLock {
            effectChainOrder = chain
            useManualGraph = false
            useSplitGraph = false
            syncNodeState(chain)
        }

        let activeTypes = Set(chain.filter { $0.isEnabled }.map { $0.type })

        bassBoostEnabled = activeTypes.contains(.bassBoost)
        nightcoreEnabled = activeTypes.contains(.pitchShift)
        clarityEnabled = activeTypes.contains(.clarity)
        deMudEnabled = activeTypes.contains(.deMud)
        simpleEQEnabled = activeTypes.contains(.simpleEQ)
        tenBandEQEnabled = activeTypes.contains(.tenBandEQ)
        compressorEnabled = activeTypes.contains(.compressor)
        reverbEnabled = activeTypes.contains(.reverb)
        stereoWidthEnabled = activeTypes.contains(.stereoWidth)
        delayEnabled = activeTypes.contains(.delay)
        distortionEnabled = activeTypes.contains(.distortion)
        tremoloEnabled = activeTypes.contains(.tremolo)
        chorusEnabled = activeTypes.contains(.chorus)
        phaserEnabled = activeTypes.contains(.phaser)
        flangerEnabled = activeTypes.contains(.flanger)
        bitcrusherEnabled = activeTypes.contains(.bitcrusher)
        tapeSaturationEnabled = activeTypes.contains(.tapeSaturation)
        resampleEnabled = activeTypes.contains(.resampling)
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
        withEffectStateLock {
            manualGraphNodes = nodes
            manualGraphConnections = connections
            manualGraphStartID = startID
            manualGraphEndID = endID
            manualGraphAutoConnectEnd = autoConnectEnd
            useManualGraph = true
            useSplitGraph = false
            syncNodeState(nodes)
        }

        let activeTypes = Set(nodes.filter { $0.isEnabled }.map { $0.type })
        bassBoostEnabled = activeTypes.contains(.bassBoost)
        nightcoreEnabled = activeTypes.contains(.pitchShift)
        clarityEnabled = activeTypes.contains(.clarity)
        deMudEnabled = activeTypes.contains(.deMud)
        simpleEQEnabled = activeTypes.contains(.simpleEQ)
        tenBandEQEnabled = activeTypes.contains(.tenBandEQ)
        compressorEnabled = activeTypes.contains(.compressor)
        reverbEnabled = activeTypes.contains(.reverb)
        stereoWidthEnabled = activeTypes.contains(.stereoWidth)
        delayEnabled = activeTypes.contains(.delay)
        distortionEnabled = activeTypes.contains(.distortion)
        tremoloEnabled = activeTypes.contains(.tremolo)
        chorusEnabled = activeTypes.contains(.chorus)
        phaserEnabled = activeTypes.contains(.phaser)
        flangerEnabled = activeTypes.contains(.flanger)
        bitcrusherEnabled = activeTypes.contains(.bitcrusher)
        tapeSaturationEnabled = activeTypes.contains(.tapeSaturation)
        resampleEnabled = activeTypes.contains(.resampling)
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
        withEffectStateLock {
            splitLeftNodes = leftNodes
            splitLeftConnections = leftConnections
            splitLeftStartID = leftStartID
            splitLeftEndID = leftEndID
            splitRightNodes = rightNodes
            splitRightConnections = rightConnections
            splitRightStartID = rightStartID
            splitRightEndID = rightEndID
            splitAutoConnectEnd = autoConnectEnd
            useSplitGraph = true
            useManualGraph = false
            syncNodeState(leftNodes + rightNodes)
        }

        let activeTypes = Set((leftNodes + rightNodes).filter { $0.isEnabled }.map { $0.type })
        bassBoostEnabled = activeTypes.contains(.bassBoost)
        nightcoreEnabled = activeTypes.contains(.pitchShift)
        clarityEnabled = activeTypes.contains(.clarity)
        deMudEnabled = activeTypes.contains(.deMud)
        simpleEQEnabled = activeTypes.contains(.simpleEQ)
        tenBandEQEnabled = activeTypes.contains(.tenBandEQ)
        compressorEnabled = activeTypes.contains(.compressor)
        reverbEnabled = activeTypes.contains(.reverb)
        stereoWidthEnabled = activeTypes.contains(.stereoWidth)
        delayEnabled = activeTypes.contains(.delay)
        distortionEnabled = activeTypes.contains(.distortion)
        tremoloEnabled = activeTypes.contains(.tremolo)
        chorusEnabled = activeTypes.contains(.chorus)
        phaserEnabled = activeTypes.contains(.phaser)
        flangerEnabled = activeTypes.contains(.flanger)
        bitcrusherEnabled = activeTypes.contains(.bitcrusher)
        tapeSaturationEnabled = activeTypes.contains(.tapeSaturation)
        resampleEnabled = activeTypes.contains(.resampling)
        rubberBandPitchEnabled = activeTypes.contains(.rubberBandPitch)
    }

    func updateGraphSnapshot(_ snapshot: GraphSnapshot?) {
        currentGraphSnapshot = snapshot
    }

    func requestGraphLoad(_ snapshot: GraphSnapshot?) {
        pendingGraphSnapshot = snapshot
    }

    private func syncNodeState(_ nodes: [BeginnerNode]) {
        let ids = Set(nodes.map { $0.id })
        nodeParameters = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.parameters) })
        nodeEnabled = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.isEnabled) })
        bassBoostStatesByNode = bassBoostStatesByNode.filter { ids.contains($0.key) }
        clarityStatesByNode = clarityStatesByNode.filter { ids.contains($0.key) }
        nightcoreStatesByNode = nightcoreStatesByNode.filter { ids.contains($0.key) }
        deMudStatesByNode = deMudStatesByNode.filter { ids.contains($0.key) }
        eqBassStatesByNode = eqBassStatesByNode.filter { ids.contains($0.key) }
        eqMidsStatesByNode = eqMidsStatesByNode.filter { ids.contains($0.key) }
        eqTrebleStatesByNode = eqTrebleStatesByNode.filter { ids.contains($0.key) }
        tenBandStatesByNode = tenBandStatesByNode.filter { ids.contains($0.key) }
        reverbBuffersByNode = reverbBuffersByNode.filter { ids.contains($0.key) }
        reverbWriteIndexByNode = reverbWriteIndexByNode.filter { ids.contains($0.key) }
        delayBuffersByNode = delayBuffersByNode.filter { ids.contains($0.key) }
        delayWriteIndexByNode = delayWriteIndexByNode.filter { ids.contains($0.key) }
        tremoloPhaseByNode = tremoloPhaseByNode.filter { ids.contains($0.key) }
        chorusBuffersByNode = chorusBuffersByNode.filter { ids.contains($0.key) }
        chorusWriteIndexByNode = chorusWriteIndexByNode.filter { ids.contains($0.key) }
        chorusPhaseByNode = chorusPhaseByNode.filter { ids.contains($0.key) }
        flangerBuffersByNode = flangerBuffersByNode.filter { ids.contains($0.key) }
        flangerWriteIndexByNode = flangerWriteIndexByNode.filter { ids.contains($0.key) }
        flangerPhaseByNode = flangerPhaseByNode.filter { ids.contains($0.key) }
        phaserStatesByNode = phaserStatesByNode.filter { ids.contains($0.key) }
        phaserPhaseByNode = phaserPhaseByNode.filter { ids.contains($0.key) }
        bitcrusherHoldCountersByNode = bitcrusherHoldCountersByNode.filter { ids.contains($0.key) }
        bitcrusherHoldValuesByNode = bitcrusherHoldValuesByNode.filter { ids.contains($0.key) }
        resampleBuffersByNode = resampleBuffersByNode.filter { ids.contains($0.key) }
        resampleWriteIndexByNode = resampleWriteIndexByNode.filter { ids.contains($0.key) }
        resampleReadPhaseByNode = resampleReadPhaseByNode.filter { ids.contains($0.key) }
        resampleCrossfadeRemainingByNode = resampleCrossfadeRemainingByNode.filter { ids.contains($0.key) }
        resampleCrossfadeTotalByNode = resampleCrossfadeTotalByNode.filter { ids.contains($0.key) }
        resampleCrossfadeStartPhaseByNode = resampleCrossfadeStartPhaseByNode.filter { ids.contains($0.key) }
        resampleCrossfadeTargetPhaseByNode = resampleCrossfadeTargetPhaseByNode.filter { ids.contains($0.key) }
        rubberBandNodes = rubberBandNodes.filter { ids.contains($0.key) }
    }
}
