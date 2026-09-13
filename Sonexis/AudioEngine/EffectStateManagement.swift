import Accelerate
import Foundation

extension AudioEngine {
    func initializeEffectStates(channelCount: Int) {
        if bassBoostState.count != channelCount {
            bassBoostState = [BiquadState](repeating: BiquadState(), count: channelCount)
        }
        if clarityState.count != channelCount {
            clarityState = [BiquadState](repeating: BiquadState(), count: channelCount)
        }
        if deMudState.count != channelCount {
            deMudState = [BiquadState](repeating: BiquadState(), count: channelCount)
        }
        if eqBassState.count != channelCount {
            eqBassState = [BiquadState](repeating: BiquadState(), count: channelCount)
        }
        if eqMidsState.count != channelCount {
            eqMidsState = [BiquadState](repeating: BiquadState(), count: channelCount)
        }
        if eqTrebleState.count != channelCount {
            eqTrebleState = [BiquadState](repeating: BiquadState(), count: channelCount)
        }
        if tenBandStates.count != tenBandFrequencies.count || tenBandStates.first?.count != channelCount {
            tenBandStates = tenBandFrequencies.map { _ in
                [BiquadState](repeating: BiquadState(), count: channelCount)
            }
        }
        if phaserStates.count != channelCount {
            phaserStates = Array(
                repeating: Array(repeating: AllPassState(), count: phaserStageCount),
                count: channelCount
            )
        }
        if phaserFeedbackSamples.count != channelCount {
            phaserFeedbackSamples = [Float](repeating: 0, count: channelCount)
        }
        if bitcrusherHoldCounters.count != channelCount {
            bitcrusherHoldCounters = [Int](repeating: 0, count: channelCount)
        }
        if bitcrusherHoldValues.count != channelCount {
            bitcrusherHoldValues = [Float](repeating: 0, count: channelCount)
        }
    }


    private func updateBassBoostCoefficients(sampleRate: Double) {
        if sampleRate != bassBoostLastSampleRate || bassBoostAmount != bassBoostLastAmount {
            bassBoostLastSampleRate = sampleRate
            bassBoostLastAmount = bassBoostAmount

            let gainDb = min(max(bassBoostAmount, 0), 1) * 24.0
            bassBoostCoefficients = BiquadCoefficients.lowShelf(
                sampleRate: sampleRate,
                frequency: 80,
                gainDb: gainDb,
                q: 0.8
            )
            // Debug output removed.
        }
    }

    private func updateClarityCoefficients(sampleRate: Double, intensity: Double) {
        if sampleRate != clarityLastSampleRate || intensity != clarityLastAmount {
            clarityLastSampleRate = sampleRate
            clarityLastAmount = intensity

            let gainDb = min(max(intensity, 0), 1) * 12.0 // Up to 12dB high shelf boost
            clarityCoefficients = BiquadCoefficients.highShelf(
                sampleRate: sampleRate,
                frequency: 3000, // 3kHz and up
                gainDb: gainDb,
                q: 0.7
            )
            // Debug output removed.
        }
    }

    private func updateDeMudCoefficients(sampleRate: Double) {
        if sampleRate != deMudLastSampleRate || deMudStrength != deMudLastStrength {
            deMudLastSampleRate = sampleRate
            deMudLastStrength = deMudStrength

            let gainDb = -min(max(deMudStrength, 0), 1) * 8.0 // Up to -8dB cut
            deMudCoefficients = BiquadCoefficients.peakingEQ(
                sampleRate: sampleRate,
                frequency: 250, // 250Hz muddy range
                gainDb: gainDb,
                q: 1.5
            )
            // Debug output removed.
        }
    }

    private func updateSimpleEQCoefficients(sampleRate: Double) {
        if sampleRate != eqLastSampleRate {
            eqLastSampleRate = sampleRate
        }

        // Bass band (80Hz low shelf)
        let bassGainDb = eqBass * 12.0 // -12 to +12 dB
        eqBassCoefficients = BiquadCoefficients.lowShelf(
            sampleRate: sampleRate,
            frequency: 80,
            gainDb: bassGainDb,
            q: 0.7
        )

        // Mids band (1kHz peaking)
        let midsGainDb = eqMids * 12.0 // -12 to +12 dB
        eqMidsCoefficients = BiquadCoefficients.peakingEQ(
            sampleRate: sampleRate,
            frequency: 1000,
            gainDb: midsGainDb,
            q: 1.0
        )

        // Treble band (8kHz high shelf)
        let trebleGainDb = eqTreble * 12.0 // -12 to +12 dB
        eqTrebleCoefficients = BiquadCoefficients.highShelf(
            sampleRate: sampleRate,
            frequency: 8000,
            gainDb: trebleGainDb,
            q: 0.7
        )
    }

    private func updateTenBandCoefficients(sampleRate: Double) {
        let gains = tenBandGains.map { min(max($0, -12), 12) }

        if tenBandCoefficients.count != tenBandFrequencies.count {
            tenBandCoefficients = [BiquadCoefficients](repeating: BiquadCoefficients(), count: tenBandFrequencies.count)
        }
        if tenBandLastGains.count != gains.count {
            tenBandLastGains = [Double](repeating: Double.nan, count: gains.count)
        }

        guard sampleRate != tenBandLastSampleRate || gains != tenBandLastGains else { return }
        tenBandLastSampleRate = sampleRate
        tenBandLastGains = gains

        for index in 0..<tenBandFrequencies.count {
            tenBandCoefficients[index] = BiquadCoefficients.peakingEQ(
                sampleRate: sampleRate,
                frequency: tenBandFrequencies[index],
                gainDb: gains[index],
                q: 1.0
            )
        }
    }

    func withEffectStateLock(_ work: () -> Void) {
        effectStateLock.lock()
        defer { effectStateLock.unlock() }
        work()
    }

    func resetBassBoostState() {
        enqueueReset(.bassBoost)
    }

    func resetBassBoostStateUnlocked() {
        if !bassBoostState.isEmpty {
            for index in bassBoostState.indices {
                bassBoostState[index] = BiquadState()
            }
        }
        bassBoostSmoothedGain = 0
        bassBoostSmoothedGainByNode.removeAll()
    }

    func resetClarityState() {
        enqueueReset(.clarity)
    }

    func resetClarityStateUnlocked() {
        clarityState = clarityState.map { _ in BiquadState() }
    }

    func resetDeMudState() {
        enqueueReset(.deMud)
    }

    func resetDeMudStateUnlocked() {
        deMudState = deMudState.map { _ in BiquadState() }
    }

    func resetEQState() {
        enqueueReset(.eq)
    }

    func resetEQStateUnlocked() {
        eqBassState = eqBassState.map { _ in BiquadState() }
        eqMidsState = eqMidsState.map { _ in BiquadState() }
        eqTrebleState = eqTrebleState.map { _ in BiquadState() }
    }

    func resetTenBandEQState() {
        enqueueReset(.tenBandEQ)
    }

    func resetTenBandEQStateUnlocked() {
        tenBandStates = tenBandStates.map { bandStates in
            bandStates.map { _ in BiquadState() }
        }
    }

    func resetChorusStateUnlocked() {
        chorusBuffer.removeAll()
        chorusWriteIndex = 0
        chorusPhase = 0
        chorusBuffersByNode.removeAll()
        chorusWriteIndexByNode.removeAll()
        chorusPhaseByNode.removeAll()
        chorusParameterState = ModulatedEffectParameterState()
        chorusParameterStateByNode.removeAll()
    }

    func resetFlangerStateUnlocked() {
        flangerBuffer.removeAll()
        flangerWriteIndex = 0
        flangerPhase = 0
        flangerBuffersByNode.removeAll()
        flangerWriteIndexByNode.removeAll()
        flangerPhaseByNode.removeAll()
        flangerParameterState = ModulatedEffectParameterState()
        flangerParameterStateByNode.removeAll()
    }

    func resetPhaserStateUnlocked() {
        phaserStates = Array(
            repeating: Array(repeating: AllPassState(), count: phaserStageCount),
            count: phaserStates.count
        )
        phaserPhase = 0
        phaserFeedbackSamples = [Float](repeating: 0, count: phaserFeedbackSamples.count)
        phaserStatesByNode.removeAll()
        phaserPhaseByNode.removeAll()
        phaserFeedbackSamplesByNode.removeAll()
        phaserParameterState = ModulatedEffectParameterState()
        phaserParameterStateByNode.removeAll()
    }

    func resetBitcrusherStateUnlocked() {
        bitcrusherHoldCounters = bitcrusherHoldCounters.map { _ in 0 }
        bitcrusherHoldValues = bitcrusherHoldValues.map { _ in 0 }
        bitcrusherHoldCountersByNode.removeAll()
        bitcrusherHoldValuesByNode.removeAll()
    }

    func resetRubberBandStateUnlocked() {
        rubberBandNodes.values.forEach { $0.reset() }
        rubberBandGlobalByType.values.forEach { $0.reset() }
        rubberBandNodes.removeAll()
        rubberBandGlobalByType.removeAll()
        rubberBandScratchByNode.removeAll()
        rubberBandScratchGlobal = RubberBandScratch()
        rubberBandSmoothedGain = 0
        rubberBandSmoothedGainByNode.removeAll()
    }

    func resetBassBoostStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetBassBoostStateUnlocked()
            bassBoostStatesByNode.removeAll()
            bassBoostVDSPDelay.removeAll()
            bassBoostVDSPDelayByNode.removeAll()
            return
        }
        bassBoostStatesByNode.removeValue(forKey: nodeId)
        bassBoostSmoothedGainByNode.removeValue(forKey: nodeId)
        bassBoostVDSPDelayByNode.removeValue(forKey: nodeId)
    }

    func resetEnhancerStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            enhancerSmoothedGain = 0
            enhancerSmoothedGainByNode.removeAll()
            enhancerLowVDSPDelay.removeAll()
            enhancerMidVDSPDelay.removeAll()
            enhancerHighVDSPDelay.removeAll()
            enhancerLowVDSPDelayByNode.removeAll()
            enhancerMidVDSPDelayByNode.removeAll()
            enhancerHighVDSPDelayByNode.removeAll()
            return
        }
        enhancerSmoothedGainByNode.removeValue(forKey: nodeId)
        enhancerLowVDSPDelayByNode.removeValue(forKey: nodeId)
        enhancerMidVDSPDelayByNode.removeValue(forKey: nodeId)
        enhancerHighVDSPDelayByNode.removeValue(forKey: nodeId)
    }

    func resetClarityStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetClarityStateUnlocked()
            claritySmoothedGain = 0
            claritySmoothedGainByNode.removeAll()
            clarityVDSPDelay.removeAll()
            clarityVDSPDelayByNode.removeAll()
            clarityStatesByNode.removeAll()
            return
        }
        clarityStatesByNode.removeValue(forKey: nodeId)
        claritySmoothedGainByNode.removeValue(forKey: nodeId)
        clarityVDSPDelayByNode.removeValue(forKey: nodeId)
    }

    func resetNightcoreStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            nightcoreStatesByNode.removeAll()
            nightcoreSmoothedGain = 0
            nightcoreSmoothedGainByNode.removeAll()
            return
        }
        nightcoreStatesByNode.removeValue(forKey: nodeId)
        nightcoreSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetDeMudStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetDeMudStateUnlocked()
            deMudSmoothedGain = 0
            deMudSmoothedGainByNode.removeAll()
            deMudVDSPDelay.removeAll()
            deMudVDSPDelayByNode.removeAll()
            deMudStatesByNode.removeAll()
            return
        }
        deMudStatesByNode.removeValue(forKey: nodeId)
        deMudSmoothedGainByNode.removeValue(forKey: nodeId)
        deMudVDSPDelayByNode.removeValue(forKey: nodeId)
    }

    func resetEQStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetEQStateUnlocked()
            simpleEQSmoothedGain = 0
            simpleEQSmoothedGainByNode.removeAll()
            eqBassVDSPDelay.removeAll()
            eqMidsVDSPDelay.removeAll()
            eqTrebleVDSPDelay.removeAll()
            eqBassVDSPDelayByNode.removeAll()
            eqMidsVDSPDelayByNode.removeAll()
            eqTrebleVDSPDelayByNode.removeAll()
            eqBassStatesByNode.removeAll()
            eqMidsStatesByNode.removeAll()
            eqTrebleStatesByNode.removeAll()
            return
        }
        eqBassStatesByNode.removeValue(forKey: nodeId)
        eqMidsStatesByNode.removeValue(forKey: nodeId)
        eqTrebleStatesByNode.removeValue(forKey: nodeId)
        eqBassVDSPDelayByNode.removeValue(forKey: nodeId)
        eqMidsVDSPDelayByNode.removeValue(forKey: nodeId)
        eqTrebleVDSPDelayByNode.removeValue(forKey: nodeId)
        simpleEQSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetAppleThreeBandEQStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            appleThreeBandEQProcessorsByNode.values.forEach { $0.reset() }
            appleThreeBandEQProcessorsByNode.removeAll()
            appleThreeBandEQDryScratchByNode.removeAll()
            appleThreeBandEQSmoothedGainByNode.removeAll()
            return
        }
        appleThreeBandEQProcessorsByNode[nodeId]?.reset()
        appleThreeBandEQProcessorsByNode.removeValue(forKey: nodeId)
        appleThreeBandEQDryScratchByNode.removeValue(forKey: nodeId)
        appleThreeBandEQSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetTenBandEQStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetTenBandEQStateUnlocked()
            tenBandEQSmoothedGain = 0
            tenBandEQSmoothedGainByNode.removeAll()
            tenBandVDSPDelays.removeAll()
            tenBandVDSPDelaysByNode.removeAll()
            tenBandStatesByNode.removeAll()
            return
        }
        tenBandStatesByNode.removeValue(forKey: nodeId)
        tenBandVDSPDelaysByNode.removeValue(forKey: nodeId)
        tenBandEQSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetCompressorStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetCompressorStateUnlocked()
            return
        }
        compressorEnvelopeByNode.removeValue(forKey: nodeId)
        compressorSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetReverbStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetReverbStateUnlocked()
            reverbSmoothedGain = 0
            reverbStatesByNode.removeAll()
            reverbSmoothedGainByNode.removeAll()
            return
        }
        reverbStatesByNode.removeValue(forKey: nodeId)
        reverbSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetDelayStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetDelayStateUnlocked()
            delaySmoothedGain = 0
            delayBuffersByNode.removeAll()
            delayWriteIndexByNode.removeAll()
            delaySmoothedGainByNode.removeAll()
            delayParameterState = ModulatedEffectParameterState()
            delayParameterStateByNode.removeAll()
            return
        }
        delayBuffersByNode.removeValue(forKey: nodeId)
        delayWriteIndexByNode.removeValue(forKey: nodeId)
        delaySmoothedGainByNode.removeValue(forKey: nodeId)
        delayParameterStateByNode.removeValue(forKey: nodeId)
    }

    func resetTremoloStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            tremoloPhase = 0
            tremoloSmoothedGain = 0
            tremoloPhaseByNode.removeAll()
            tremoloSmoothedGainByNode.removeAll()
            return
        }
        tremoloPhaseByNode.removeValue(forKey: nodeId)
        tremoloSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetAutoPanStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            autoPanPhase = 0
            autoPanSmoothedGain = 0
            autoPanPhaseByNode.removeAll()
            autoPanSmoothedGainByNode.removeAll()
            autoPanParameterState = ModulatedEffectParameterState()
            autoPanParameterStateByNode.removeAll()
            return
        }
        autoPanPhaseByNode.removeValue(forKey: nodeId)
        autoPanSmoothedGainByNode.removeValue(forKey: nodeId)
        autoPanParameterStateByNode.removeValue(forKey: nodeId)
    }

    func resetChorusStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetChorusStateUnlocked()
            chorusSmoothedGain = 0
            chorusSmoothedGainByNode.removeAll()
            chorusParameterState = ModulatedEffectParameterState()
            chorusParameterStateByNode.removeAll()
            return
        }
        chorusBuffersByNode.removeValue(forKey: nodeId)
        chorusWriteIndexByNode.removeValue(forKey: nodeId)
        chorusPhaseByNode.removeValue(forKey: nodeId)
        chorusSmoothedGainByNode.removeValue(forKey: nodeId)
        chorusParameterStateByNode.removeValue(forKey: nodeId)
    }

    func resetFlangerStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetFlangerStateUnlocked()
            flangerSmoothedGain = 0
            flangerSmoothedGainByNode.removeAll()
            flangerParameterState = ModulatedEffectParameterState()
            flangerParameterStateByNode.removeAll()
            return
        }
        flangerBuffersByNode.removeValue(forKey: nodeId)
        flangerWriteIndexByNode.removeValue(forKey: nodeId)
        flangerPhaseByNode.removeValue(forKey: nodeId)
        flangerSmoothedGainByNode.removeValue(forKey: nodeId)
        flangerParameterStateByNode.removeValue(forKey: nodeId)
    }

    func resetPhaserStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetPhaserStateUnlocked()
            phaserSmoothedGain = 0
            phaserSmoothedGainByNode.removeAll()
            phaserFeedbackSamplesByNode.removeAll()
            phaserParameterState = ModulatedEffectParameterState()
            phaserParameterStateByNode.removeAll()
            return
        }
        phaserStatesByNode.removeValue(forKey: nodeId)
        phaserPhaseByNode.removeValue(forKey: nodeId)
        phaserFeedbackSamplesByNode.removeValue(forKey: nodeId)
        phaserSmoothedGainByNode.removeValue(forKey: nodeId)
        phaserParameterStateByNode.removeValue(forKey: nodeId)
    }

    func resetBitcrusherStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetBitcrusherStateUnlocked()
            bitcrusherSmoothedGain = 0
            bitcrusherSmoothedGainByNode.removeAll()
            return
        }
        bitcrusherHoldCountersByNode.removeValue(forKey: nodeId)
        bitcrusherHoldValuesByNode.removeValue(forKey: nodeId)
        bitcrusherSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetSignatureEffectStateUnlocked(effect: EffectType? = nil, nodeId: UUID?) {
        guard let nodeId else {
            signatureEffectStatesByNode.removeAll()
            if let effect {
                signatureEffectStatesByType.removeValue(forKey: effect)
            } else {
                signatureEffectStatesByType.removeAll()
            }
            return
        }
        signatureEffectStatesByNode.removeValue(forKey: nodeId)
    }

    func resetResampleStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resampleBuffer.removeAll()
            resampleWriteIndex = 0
            resampleReadPhase = 0
            resampleCrossfadeRemaining = 0
            resampleCrossfadeTotal = 0
            resampleCrossfadeStartPhase = 0
            resampleCrossfadeTargetPhase = 0
            resampleSmoothedGain = 0
            resampleBuffersByNode.removeAll()
            resampleWriteIndexByNode.removeAll()
            resampleReadPhaseByNode.removeAll()
            resampleCrossfadeRemainingByNode.removeAll()
            resampleCrossfadeTotalByNode.removeAll()
            resampleCrossfadeStartPhaseByNode.removeAll()
            resampleCrossfadeTargetPhaseByNode.removeAll()
            resampleSmoothedGainByNode.removeAll()
            return
        }
        resampleBuffersByNode.removeValue(forKey: nodeId)
        resampleWriteIndexByNode.removeValue(forKey: nodeId)
        resampleReadPhaseByNode.removeValue(forKey: nodeId)
        resampleCrossfadeRemainingByNode.removeValue(forKey: nodeId)
        resampleCrossfadeTotalByNode.removeValue(forKey: nodeId)
        resampleCrossfadeStartPhaseByNode.removeValue(forKey: nodeId)
        resampleCrossfadeTargetPhaseByNode.removeValue(forKey: nodeId)
        resampleSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetRubberBandStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            resetRubberBandStateUnlocked()
            return
        }
        rubberBandNodes[nodeId]?.reset()
        rubberBandNodes.removeValue(forKey: nodeId)
        rubberBandScratchByNode.removeValue(forKey: nodeId)
        rubberBandSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetAmpStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            ampSmoothedGain = 0
            ampSmoothedGainByNode.removeAll()
            return
        }
        ampSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetDistortionStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            distortionSmoothedGain = 0
            distortionSmoothedGainByNode.removeAll()
            return
        }
        distortionSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetTapeSaturationStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            tapeSaturationSmoothedGain = 0
            tapeSaturationSmoothedGainByNode.removeAll()
            return
        }
        tapeSaturationSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetStereoWidthStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            stereoWidthSmoothedGain = 0
            stereoWidthSmoothedGainByNode.removeAll()
            return
        }
        stereoWidthSmoothedGainByNode.removeValue(forKey: nodeId)
    }

    func resetPluginStateUnlocked(nodeId: UUID?) {
        guard let nodeId else {
            pluginDryScratchByNode.removeAll()
            pluginWetScratchByNode.removeAll()
            pluginCrossfadeRemainingByNode.removeAll()
            pluginCrossfadeTotalByNode.removeAll()
            pluginCrossfadeOutRemainingByNode.removeAll()
            pluginCrossfadeOutTotalByNode.removeAll()
            pluginWasEnabledByNode.removeAll()
            pluginWasReadyByNode.removeAll()
            pluginStableOutputCountByNode.removeAll()
            pluginHasStableOutputByNode.removeAll()
            pluginReadyDelaySamplesByNode.removeAll()
            return
        }
        pluginDryScratchByNode.removeValue(forKey: nodeId)
        pluginWetScratchByNode.removeValue(forKey: nodeId)
        pluginCrossfadeRemainingByNode.removeValue(forKey: nodeId)
        pluginCrossfadeTotalByNode.removeValue(forKey: nodeId)
        pluginCrossfadeOutRemainingByNode.removeValue(forKey: nodeId)
        pluginCrossfadeOutTotalByNode.removeValue(forKey: nodeId)
        pluginWasEnabledByNode.removeValue(forKey: nodeId)
        pluginWasReadyByNode.removeValue(forKey: nodeId)
        pluginStableOutputCountByNode.removeValue(forKey: nodeId)
        pluginHasStableOutputByNode.removeValue(forKey: nodeId)
        pluginReadyDelaySamplesByNode.removeValue(forKey: nodeId)
    }

    func resetEffectStateUnlocked() {
        resetBassBoostStateUnlocked()
        enhancerSmoothedGain = 0
        enhancerSmoothedGainByNode.removeAll()
        enhancerLowVDSPDelay.removeAll()
        enhancerMidVDSPDelay.removeAll()
        enhancerHighVDSPDelay.removeAll()
        enhancerLowVDSPDelayByNode.removeAll()
        enhancerMidVDSPDelayByNode.removeAll()
        enhancerHighVDSPDelayByNode.removeAll()
        resetClarityStateUnlocked()
        resetDeMudStateUnlocked()
        resetEQStateUnlocked()
        resetAppleThreeBandEQStateUnlocked(nodeId: nil)
        resetTenBandEQStateUnlocked()
        resetCompressorStateUnlocked()
        tremoloPhase = 0
        resetAutoPanStateUnlocked(nodeId: nil)
        resetReverbStateUnlocked()
        resetDelayStateUnlocked()
        resetChorusStateUnlocked()
        resetFlangerStateUnlocked()
        phaserPhase = 0
        phaserFeedbackSamples = [Float](repeating: 0, count: phaserFeedbackSamples.count)
        phaserParameterState = ModulatedEffectParameterState()
        resetBitcrusherStateUnlocked()
        ampSmoothedGain = 0
        ampSmoothedGainByNode.removeAll()
        distortionSmoothedGain = 0
        distortionSmoothedGainByNode.removeAll()
        tapeSaturationSmoothedGain = 0
        tapeSaturationSmoothedGainByNode.removeAll()
        signatureEffectStatesByNode.removeAll()
        signatureEffectStatesByType.removeAll()
        resampleBuffer.removeAll()
        resampleWriteIndex = 0
        resampleReadPhase = 0
        resampleCrossfadeRemaining = 0
        resampleCrossfadeTotal = 0
        resampleCrossfadeStartPhase = 0
        resampleCrossfadeTargetPhase = 0
        autoPanParameterState = ModulatedEffectParameterState()
        chorusParameterState = ModulatedEffectParameterState()
        flangerParameterState = ModulatedEffectParameterState()
        resetRubberBandStateUnlocked()
        bassBoostStatesByNode.removeAll()
        clarityStatesByNode.removeAll()
        nightcoreStatesByNode.removeAll()
        deMudStatesByNode.removeAll()
        eqBassStatesByNode.removeAll()
        eqMidsStatesByNode.removeAll()
        eqTrebleStatesByNode.removeAll()
        appleThreeBandEQProcessorsByNode.removeAll()
        appleThreeBandEQDryScratchByNode.removeAll()
        appleThreeBandEQSmoothedGainByNode.removeAll()
        tenBandStatesByNode.removeAll()
        reverbStatesByNode.removeAll()
        delayBuffersByNode.removeAll()
        delayWriteIndexByNode.removeAll()
        delayParameterStateByNode.removeAll()
        tremoloPhaseByNode.removeAll()
        autoPanPhaseByNode.removeAll()
        autoPanParameterStateByNode.removeAll()
        chorusBuffersByNode.removeAll()
        chorusWriteIndexByNode.removeAll()
        chorusPhaseByNode.removeAll()
        chorusParameterStateByNode.removeAll()
        flangerBuffersByNode.removeAll()
        flangerWriteIndexByNode.removeAll()
        flangerPhaseByNode.removeAll()
        flangerParameterStateByNode.removeAll()
        phaserStatesByNode.removeAll()
        phaserFeedbackSamplesByNode.removeAll()
        phaserParameterStateByNode.removeAll()
        signatureEffectStatesByNode.removeAll()
        signatureEffectStatesByType.removeAll()
        bitcrusherHoldCountersByNode.removeAll()
        bitcrusherHoldValuesByNode.removeAll()
        resampleBuffersByNode.removeAll()
        resampleWriteIndexByNode.removeAll()
        resampleReadPhaseByNode.removeAll()
        dspFaultCountsByEffect.removeAll()
        dspFaultCountsByNode.removeAll()
    }

    func applyPendingResets() {
        pendingResetsLock.lock()
        let resets = pendingResets
        pendingResets = []
        pendingResetsLock.unlock()

        guard resets != [] else { return }

        if resets.contains(ResetFlags.all) {
            resetEffectStateUnlocked()
            DispatchQueue.main.async {
                self.effectLevels = [:]
            }
            return
        }

        if resets.contains(ResetFlags.bassBoost) { resetBassBoostStateUnlocked() }
        if resets.contains(ResetFlags.clarity) { resetClarityStateUnlocked() }
        if resets.contains(ResetFlags.deMud) { resetDeMudStateUnlocked() }
        if resets.contains(ResetFlags.eq) { resetEQStateUnlocked() }
        if resets.contains(ResetFlags.tenBandEQ) { resetTenBandEQStateUnlocked() }
        if resets.contains(ResetFlags.compressor) { resetCompressorStateUnlocked() }
        if resets.contains(ResetFlags.reverb) { resetReverbStateUnlocked() }
        if resets.contains(ResetFlags.delay) { resetDelayStateUnlocked() }
        if resets.contains(ResetFlags.autoPan) { resetAutoPanStateUnlocked(nodeId: nil) }
        if resets.contains(ResetFlags.chorus) { resetChorusStateUnlocked() }
        if resets.contains(ResetFlags.flanger) { resetFlangerStateUnlocked() }
        if resets.contains(ResetFlags.phaser) { resetPhaserStateUnlocked() }
        if resets.contains(ResetFlags.bitcrusher) { resetBitcrusherStateUnlocked() }
        if resets.contains(ResetFlags.rubberBand) { resetRubberBandStateUnlocked() }
    }

    func resetTenBandValues() {
        tenBand31 = 0
        tenBand62 = 0
        tenBand125 = 0
        tenBand250 = 0
        tenBand500 = 0
        tenBand1k = 0
        tenBand2k = 0
        tenBand4k = 0
        tenBand8k = 0
        tenBand16k = 0
    }

    func resetCompressorState() {
        enqueueReset(.compressor)
    }

    func resetCompressorStateUnlocked() {
        compressorEnvelope = 1
        compressorEnvelopeByNode.removeAll()
        compressorSmoothedGain = 0
        compressorSmoothedGainByNode.removeAll()
    }

    func resetReverbState() {
        enqueueReset(.reverb)
    }

    func resetReverbStateUnlocked() {
        reverbState.reset()
    }

    func resetDelayState() {
        enqueueReset(.delay)
    }

    func resetDelayStateUnlocked() {
        delayBuffer.removeAll()
        delayWriteIndex = 0
        delayParameterState = ModulatedEffectParameterState()
    }

    func resetChorusState() {
        enqueueReset(.chorus)
    }

    func resetAutoPanState() {
        enqueueReset(.autoPan)
    }

    func resetFlangerState() {
        enqueueReset(.flanger)
    }

    func resetPhaserState() {
        enqueueReset(.phaser)
    }

    func resetBitcrusherState() {
        enqueueReset(.bitcrusher)
    }

    func resetEffectState() {
        enqueueReset(.all)
    }

    // Note: Proper pitch shifting without tempo change requires complex DSP (phase vocoder, etc.)
    // For now, nightcore is implemented as a simple brightness/clarity boost
    // True pitch shifting will be added in a future update

}
