import Accelerate
import Foundation

extension AudioGraphProcessor {
    func applyEffect(
        _ effect: EffectType,
        to processedAudio: inout [[Float]],
        sampleRate: Double,
        channelCount: Int,
        frameLength: Int,
        nodeId: UUID?,
        levelSnapshot: inout [UUID: Float],
        snapshot: ProcessingSnapshot
    ) {
        if effect.isRetired {
            if let id = nodeId { levelSnapshot[id] = 0 }
            return
        }

        switch effect {
        case .nightDrive, .chromePunch, .midnightGlow, .afterglow:
            applySignatureEffect(
                effect,
                to: &processedAudio,
                sampleRate: sampleRate,
                channelCount: channelCount,
                frameLength: frameLength,
                nodeId: nodeId,
                levelSnapshot: &levelSnapshot,
                snapshot: snapshot
            )

        case .bassBoost:
            // Determine if effect should be active
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.bassBoostEnabled
            let amount = nodeParams(for: nodeId, snapshot: snapshot)?.bassBoostAmount ?? snapshot.bassBoostAmount

            // Target gain: 0 if disabled, otherwise based on amount (max 12dB instead of 24dB)
            let targetGain: Float
            if isNodeDisabled || isGlobalDisabled || amount <= 0 {
                targetGain = 0
            } else {
                targetGain = Float(min(max(amount, 0), 1))
            }

            // Get current smoothed gain
            var smoothedGain: Float
            if let id = nodeId {
                smoothedGain = bassBoostSmoothedGainByNode[id] ?? 0
            } else {
                smoothedGain = bassBoostSmoothedGain
            }

            // If both current and target are 0, skip processing entirely
            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            // Smoothing coefficient: ~15ms ramp at any sample rate
            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))

            // Calculate coefficients at max boost for consistent filter behavior
            let gainDb = min(max(amount, 0), 1) * 12.0
            let coefficients = BiquadCoefficients.lowShelf(
                sampleRate: sampleRate,
                frequency: 80,
                gainDb: max(gainDb, 3.0),  // Minimum 3dB for valid coefficients
                q: 0.8
            )

            // Get or initialize vDSP delay states (4 floats per channel)
            var vdspDelays: [[Float]]
            if let id = nodeId {
                vdspDelays = bassBoostVDSPDelayByNode[id] ?? [[Float]](repeating: [Float](repeating: 0, count: 4), count: channelCount)
            } else {
                vdspDelays = bassBoostVDSPDelay
            }
            // Ensure correct channel count
            while vdspDelays.count < channelCount {
                vdspDelays.append([Float](repeating: 0, count: 4))
            }

            // Ensure scratch buffer is large enough
            if biquadScratchBuffer.count < frameLength {
                biquadScratchBuffer = [Float](repeating: 0, count: frameLength)
            }

            for channel in 0..<channelCount {
                // Step 1: Process entire channel through biquad using vDSP (vectorized)
                coefficients.processBuffer(processedAudio[channel], output: &biquadScratchBuffer, delay: &vdspDelays[channel], frameLength: frameLength)

                // Step 2: Crossfade dry/wet with per-sample gain smoothing (for click-free transitions)
                for frame in 0..<frameLength {
                    smoothedGain += (targetGain - smoothedGain) * smoothingCoeff

                    let dry = processedAudio[channel][frame]
                    let wet = biquadScratchBuffer[frame]
                    let outputGain = 1.0 + smoothedGain * 0.35

                    processedAudio[channel][frame] = (dry * (1 - smoothedGain) + wet * smoothedGain) * outputGain
                }
            }

            // Store updated state
            if let id = nodeId {
                bassBoostVDSPDelayByNode[id] = vdspDelays
                bassBoostSmoothedGainByNode[id] = smoothedGain
            } else {
                bassBoostVDSPDelay = vdspDelays
                bassBoostSmoothedGain = smoothedGain
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .enhancer:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.enhancerEnabled
            let amount = nodeParams(for: nodeId, snapshot: snapshot)?.enhancerAmount ?? snapshot.enhancerAmount

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || amount <= 0) ? 0 : Float(min(max(amount, 0), 1))
            var smoothedGain: Float = nodeId != nil ? (enhancerSmoothedGainByNode[nodeId!] ?? 0) : enhancerSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.02)))
            let normalizedAmount = min(max(amount, 0), 1)
            let lowGainDb = normalizedAmount * 4.0
            let midGainDb = -normalizedAmount * 3.0
            let highGainDb = normalizedAmount * 6.0

            let lowCoefficients = BiquadCoefficients.lowShelf(
                sampleRate: sampleRate,
                frequency: 120,
                gainDb: lowGainDb,
                q: 0.8
            )
            let midCoefficients = BiquadCoefficients.peakingEQ(
                sampleRate: sampleRate,
                frequency: 320,
                gainDb: midGainDb,
                q: 1.2
            )
            let highCoefficients = BiquadCoefficients.highShelf(
                sampleRate: sampleRate,
                frequency: 5500,
                gainDb: highGainDb,
                q: 0.7
            )

            var lowDelays: [[Float]]
            var midDelays: [[Float]]
            var highDelays: [[Float]]
            if let id = nodeId {
                lowDelays = enhancerLowVDSPDelayByNode[id] ?? [[Float]](repeating: [Float](repeating: 0, count: 4), count: channelCount)
                midDelays = enhancerMidVDSPDelayByNode[id] ?? [[Float]](repeating: [Float](repeating: 0, count: 4), count: channelCount)
                highDelays = enhancerHighVDSPDelayByNode[id] ?? [[Float]](repeating: [Float](repeating: 0, count: 4), count: channelCount)
            } else {
                lowDelays = enhancerLowVDSPDelay
                midDelays = enhancerMidVDSPDelay
                highDelays = enhancerHighVDSPDelay
            }

            while lowDelays.count < channelCount { lowDelays.append([Float](repeating: 0, count: 4)) }
            while midDelays.count < channelCount { midDelays.append([Float](repeating: 0, count: 4)) }
            while highDelays.count < channelCount { highDelays.append([Float](repeating: 0, count: 4)) }

            if biquadScratchBuffer.count < frameLength {
                biquadScratchBuffer = [Float](repeating: 0, count: frameLength)
            }
            if biquadScratchBuffer2.count < frameLength {
                biquadScratchBuffer2 = [Float](repeating: 0, count: frameLength)
            }

            let drive = Float(1.0 + normalizedAmount * 4.0)
            let driveNorm = Float(tanh(Double(drive)))

            for channel in 0..<channelCount {
                lowCoefficients.processBuffer(processedAudio[channel], output: &biquadScratchBuffer, delay: &lowDelays[channel], frameLength: frameLength)
                midCoefficients.processBuffer(biquadScratchBuffer, output: &biquadScratchBuffer2, delay: &midDelays[channel], frameLength: frameLength)
                highCoefficients.processBuffer(biquadScratchBuffer2, output: &biquadScratchBuffer, delay: &highDelays[channel], frameLength: frameLength)

                for frame in 0..<frameLength {
                    smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                    let dry = processedAudio[channel][frame]
                    let driven = biquadScratchBuffer[frame] * drive
                    let saturated = Float(tanh(Double(driven))) / max(driveNorm, 0.0001)
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + saturated * smoothedGain
                }
            }

            if let id = nodeId {
                enhancerLowVDSPDelayByNode[id] = lowDelays
                enhancerMidVDSPDelayByNode[id] = midDelays
                enhancerHighVDSPDelayByNode[id] = highDelays
                enhancerSmoothedGainByNode[id] = smoothedGain
            } else {
                enhancerLowVDSPDelay = lowDelays
                enhancerMidVDSPDelay = midDelays
                enhancerHighVDSPDelay = highDelays
                enhancerSmoothedGain = smoothedGain
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .pitchShift:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.nightcoreEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }
            return

        case .clarity:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.clarityEnabled
            let amount = nodeParams(for: nodeId, snapshot: snapshot)?.clarityAmount ?? snapshot.clarityAmount

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || amount <= 0) ? 0 : Float(min(max(amount, 0), 1))

            var smoothedGain: Float = nodeId != nil ? (claritySmoothedGainByNode[nodeId!] ?? 0) : claritySmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let gainDb = min(max(amount, 0), 1) * 12.0
            let coefficients = BiquadCoefficients.highShelf(
                sampleRate: sampleRate,
                frequency: 3000,
                gainDb: max(gainDb, 3.0),
                q: 0.7
            )

            // Get or initialize vDSP delay states
            var vdspDelays: [[Float]]
            if let id = nodeId {
                vdspDelays = clarityVDSPDelayByNode[id] ?? [[Float]](repeating: [Float](repeating: 0, count: 4), count: channelCount)
            } else {
                vdspDelays = clarityVDSPDelay
            }
            while vdspDelays.count < channelCount {
                vdspDelays.append([Float](repeating: 0, count: 4))
            }

            if biquadScratchBuffer.count < frameLength {
                biquadScratchBuffer = [Float](repeating: 0, count: frameLength)
            }

            for channel in 0..<channelCount {
                coefficients.processBuffer(processedAudio[channel], output: &biquadScratchBuffer, delay: &vdspDelays[channel], frameLength: frameLength)
                for frame in 0..<frameLength {
                    smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                    let dry = processedAudio[channel][frame]
                    let wet = biquadScratchBuffer[frame]
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
            }

            if let id = nodeId {
                clarityVDSPDelayByNode[id] = vdspDelays
                claritySmoothedGainByNode[id] = smoothedGain
            } else {
                clarityVDSPDelay = vdspDelays
                claritySmoothedGain = smoothedGain
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .deMud:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.deMudEnabled
            let strength = nodeParams(for: nodeId, snapshot: snapshot)?.deMudStrength ?? snapshot.deMudStrength

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || strength <= 0) ? 0 : Float(min(max(strength, 0), 1))

            var smoothedGain: Float = nodeId != nil ? (deMudSmoothedGainByNode[nodeId!] ?? 0) : deMudSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let gainDb = -min(max(strength, 0), 1) * 8.0
            let coefficients = BiquadCoefficients.peakingEQ(
                sampleRate: sampleRate,
                frequency: 250,
                gainDb: min(gainDb, -2.0),
                q: 1.5
            )

            var vdspDelays: [[Float]]
            if let id = nodeId {
                vdspDelays = deMudVDSPDelayByNode[id] ?? [[Float]](repeating: [Float](repeating: 0, count: 4), count: channelCount)
            } else {
                vdspDelays = deMudVDSPDelay
            }
            while vdspDelays.count < channelCount {
                vdspDelays.append([Float](repeating: 0, count: 4))
            }

            if biquadScratchBuffer.count < frameLength {
                biquadScratchBuffer = [Float](repeating: 0, count: frameLength)
            }

            for channel in 0..<channelCount {
                coefficients.processBuffer(processedAudio[channel], output: &biquadScratchBuffer, delay: &vdspDelays[channel], frameLength: frameLength)
                for frame in 0..<frameLength {
                    smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                    let dry = processedAudio[channel][frame]
                    let wet = biquadScratchBuffer[frame]
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
            }

            if let id = nodeId {
                deMudVDSPDelayByNode[id] = vdspDelays
                deMudSmoothedGainByNode[id] = smoothedGain
            } else {
                deMudVDSPDelay = vdspDelays
                deMudSmoothedGain = smoothedGain
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .simpleEQ:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.simpleEQEnabled
            let params = nodeParams(for: nodeId, snapshot: snapshot)
            let bass = params?.eqBass ?? snapshot.eqBass
            let mids = params?.eqMids ?? snapshot.eqMids
            let treble = params?.eqTreble ?? snapshot.eqTreble
            let hasEQ = bass != 0 || mids != 0 || treble != 0

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || !hasEQ) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (simpleEQSmoothedGainByNode[nodeId!] ?? 0) : simpleEQSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let bassCoefficients = BiquadCoefficients.lowShelf(
                sampleRate: sampleRate,
                frequency: 80,
                gainDb: bass * 12.0,
                q: 0.7
            )
            let midsCoefficients = BiquadCoefficients.peakingEQ(
                sampleRate: sampleRate,
                frequency: 1000,
                gainDb: mids * 12.0,
                q: 1.0
            )
            let trebleCoefficients = BiquadCoefficients.highShelf(
                sampleRate: sampleRate,
                frequency: 8000,
                gainDb: treble * 12.0,
                q: 0.7
            )

            // Get vDSP delays for each band
            let targetId = nodeId
            var bassDelays = targetId.flatMap { eqBassVDSPDelayByNode[$0] } ?? eqBassVDSPDelay
            var midsDelays = targetId.flatMap { eqMidsVDSPDelayByNode[$0] } ?? eqMidsVDSPDelay
            var trebleDelays = targetId.flatMap { eqTrebleVDSPDelayByNode[$0] } ?? eqTrebleVDSPDelay

            while bassDelays.count < channelCount { bassDelays.append([Float](repeating: 0, count: 4)) }
            while midsDelays.count < channelCount { midsDelays.append([Float](repeating: 0, count: 4)) }
            while trebleDelays.count < channelCount { trebleDelays.append([Float](repeating: 0, count: 4)) }

            if biquadScratchBuffer.count < frameLength {
                biquadScratchBuffer = [Float](repeating: 0, count: frameLength)
            }
            if biquadScratchBuffer2.count < frameLength {
                biquadScratchBuffer2 = [Float](repeating: 0, count: frameLength)
            }

            for channel in 0..<channelCount {
                // Process through 3 bands in series using vDSP
                // Input → Bass → Mids → Treble → Output (wet)
                if bass != 0 {
                    bassCoefficients.processBuffer(processedAudio[channel], output: &biquadScratchBuffer, delay: &bassDelays[channel], frameLength: frameLength)
                } else {
                    for frame in 0..<frameLength {
                        biquadScratchBuffer[frame] = processedAudio[channel][frame]
                    }
                }

                if mids != 0 {
                    midsCoefficients.processBuffer(biquadScratchBuffer, output: &biquadScratchBuffer2, delay: &midsDelays[channel], frameLength: frameLength)
                } else {
                    for frame in 0..<frameLength {
                        biquadScratchBuffer2[frame] = biquadScratchBuffer[frame]
                    }
                }

                if treble != 0 {
                    trebleCoefficients.processBuffer(biquadScratchBuffer2, output: &biquadScratchBuffer, delay: &trebleDelays[channel], frameLength: frameLength)
                } else {
                    for frame in 0..<frameLength {
                        biquadScratchBuffer[frame] = biquadScratchBuffer2[frame]
                    }
                }

                // biquadScratchBuffer now contains the fully filtered wet signal
                for frame in 0..<frameLength {
                    smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                    let dry = processedAudio[channel][frame]
                    let wet = biquadScratchBuffer[frame]
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
            }

            if let id = targetId {
                eqBassVDSPDelayByNode[id] = bassDelays
                eqMidsVDSPDelayByNode[id] = midsDelays
                eqTrebleVDSPDelayByNode[id] = trebleDelays
                simpleEQSmoothedGainByNode[id] = smoothedGain
            } else {
                eqBassVDSPDelay = bassDelays
                eqMidsVDSPDelay = midsDelays
                eqTrebleVDSPDelay = trebleDelays
                simpleEQSmoothedGain = smoothedGain
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .appleThreeBandEQ:
            guard let nodeId else { return }
            let isNodeDisabled = !nodeIsEnabled(nodeId, snapshot: snapshot)
            let params = nodeParams(for: nodeId, snapshot: snapshot)
            let bass = params?.eqBass ?? snapshot.eqBass
            let mids = params?.eqMids ?? snapshot.eqMids
            let treble = params?.eqTreble ?? snapshot.eqTreble
            let hasEQ = bass != 0 || mids != 0 || treble != 0
            let targetGain: Float = (isNodeDisabled || !hasEQ) ? 0 : 1
            var smoothedGain = appleThreeBandEQSmoothedGainByNode[nodeId] ?? 0

            if smoothedGain < 0.001 && targetGain < 0.001 {
                levelSnapshot[nodeId] = 0
                return
            }

            var dryScratch = ensureAppleThreeBandEQDryScratch(
                nodeId: nodeId,
                channelCount: channelCount,
                frameLength: frameLength
            )
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    dryScratch[channel][frame] = processedAudio[channel][frame]
                }
            }
            appleThreeBandEQDryScratchByNode[nodeId] = dryScratch

            let processor = appleThreeBandEQProcessor(for: nodeId)
            let rendered = processor.process(
                buffer: &processedAudio,
                frameLength: frameLength,
                sampleRate: sampleRate,
                channelCount: channelCount,
                bassGainDB: bass * 12.0,
                midGainDB: mids * 12.0,
                trebleGainDB: treble * 12.0
            )

            guard rendered else {
                processedAudio = dryScratch
                appleThreeBandEQSmoothedGainByNode[nodeId] = 0
                levelSnapshot[nodeId] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                    let dry = dryScratch[channel][frame]
                    let wet = processedAudio[channel][frame]
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
            }

            appleThreeBandEQSmoothedGainByNode[nodeId] = smoothedGain
            levelSnapshot[nodeId] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)

        case .tenBandEQ:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.tenBandEQEnabled
            let gains = nodeParams(for: nodeId, snapshot: snapshot)?.tenBandGains ?? snapshot.tenBandGains
            let hasEQ = gains.contains(where: { $0 != 0 })

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || !hasEQ) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (tenBandEQSmoothedGainByNode[nodeId!] ?? 0) : tenBandEQSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let clampedGains = gains.map { min(max($0, -12), 12) }
            var bandCoefficients: [BiquadCoefficients] = []
            bandCoefficients.reserveCapacity(tenBandFrequencies.count)
            for (index, frequency) in tenBandFrequencies.enumerated() {
                let gain = index < clampedGains.count ? clampedGains[index] : 0
                bandCoefficients.append(
                    BiquadCoefficients.peakingEQ(
                        sampleRate: sampleRate,
                        frequency: frequency,
                        gainDb: gain,
                        q: 1.0
                    )
                )
            }

            // Get or initialize vDSP delays: [band][channel][4 floats]
            let targetId = nodeId
            var vdspDelays: [[[Float]]] = targetId.flatMap { tenBandVDSPDelaysByNode[$0] } ?? tenBandVDSPDelays

            // Ensure we have delays for all bands and channels
            let bandCount = tenBandFrequencies.count
            while vdspDelays.count < bandCount {
                vdspDelays.append([[Float]](repeating: [Float](repeating: 0, count: 4), count: channelCount))
            }
            for band in 0..<bandCount {
                while vdspDelays[band].count < channelCount {
                    vdspDelays[band].append([Float](repeating: 0, count: 4))
                }
            }

            if biquadScratchBuffer.count < frameLength {
                biquadScratchBuffer = [Float](repeating: 0, count: frameLength)
            }
            if biquadScratchBuffer2.count < frameLength {
                biquadScratchBuffer2 = [Float](repeating: 0, count: frameLength)
            }

            for channel in 0..<channelCount {
                // Process through all 10 bands in series using vDSP
                // Copy input to scratch buffer first
                for i in 0..<frameLength {
                    biquadScratchBuffer[i] = processedAudio[channel][i]
                }

                for band in 0..<bandCount {
                    // Alternate: scratch -> scratch2 -> scratch -> scratch2 ...
                    if band % 2 == 0 {
                        bandCoefficients[band].processBuffer(biquadScratchBuffer, output: &biquadScratchBuffer2, delay: &vdspDelays[band][channel], frameLength: frameLength)
                    } else {
                        bandCoefficients[band].processBuffer(biquadScratchBuffer2, output: &biquadScratchBuffer, delay: &vdspDelays[band][channel], frameLength: frameLength)
                    }
                }

                // After 10 bands (even number), result is in biquadScratchBuffer2
                let wetBuffer = biquadScratchBuffer2
                for frame in 0..<frameLength {
                    smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                    let dry = processedAudio[channel][frame]
                    let wet = wetBuffer[frame]
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
            }

            if let id = targetId {
                tenBandVDSPDelaysByNode[id] = vdspDelays
                tenBandEQSmoothedGainByNode[id] = smoothedGain
            } else {
                tenBandVDSPDelays = vdspDelays
                tenBandEQSmoothedGain = smoothedGain
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .compressor:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.compressorEnabled
            let params = nodeParams(for: nodeId, snapshot: snapshot)
            let thresholdDB = min(max(params?.compressorThresholdDB ?? snapshot.compressorThresholdDB, -60), 0)
            let ratio = min(max(params?.compressorRatio ?? snapshot.compressorRatio, 1), 20)
            let attackMS = min(max(params?.compressorAttackMS ?? snapshot.compressorAttackMS, 0.1), 200)
            let releaseMS = min(max(params?.compressorReleaseMS ?? snapshot.compressorReleaseMS, 5), 2000)
            let makeupDB = min(max(params?.compressorMakeupDB ?? snapshot.compressorMakeupDB, -24), 24)
            let mix = min(max(params?.compressorMix ?? snapshot.compressorMix, 0), 1)

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || mix <= 0) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (compressorSmoothedGainByNode[nodeId!] ?? 0) : compressorSmoothedGain
            var detectorGain: Float = nodeId != nil ? (compressorEnvelopeByNode[nodeId!] ?? 1) : compressorEnvelope
            if !detectorGain.isFinite || detectorGain <= 0 {
                detectorGain = 1
            }

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let attackCoeff = Float(1.0 - exp(-1.0 / max(sampleRate * attackMS * 0.001, 1.0)))
            let releaseCoeff = Float(1.0 - exp(-1.0 / max(sampleRate * releaseMS * 0.001, 1.0)))
            let makeupGain = Float(pow(10.0, makeupDB / 20.0))
            let safeChannelCount = min(channelCount, processedAudio.count)

            for frame in 0..<frameLength {
                var sidechainPeak: Float = 0
                for channel in 0..<safeChannelCount {
                    guard frame < processedAudio[channel].count else { continue }
                    sidechainPeak = max(sidechainPeak, abs(processedAudio[channel][frame]))
                }

                let inputDB = sidechainPeak > 0.000001 ? 20.0 * log10(Double(sidechainPeak)) : -120.0
                var targetDetectorGain: Float = 1
                if inputDB > thresholdDB && ratio > 1.0001 {
                    let overDB = inputDB - thresholdDB
                    let compressedOverDB = overDB / ratio
                    let gainReductionDB = compressedOverDB - overDB
                    targetDetectorGain = Float(pow(10.0, gainReductionDB / 20.0))
                }

                let detectorCoeff = targetDetectorGain < detectorGain ? attackCoeff : releaseCoeff
                detectorGain += (targetDetectorGain - detectorGain) * detectorCoeff
                smoothedGain += (targetGain - smoothedGain) * smoothingCoeff

                let wetBlend = smoothedGain * Float(mix)
                let wetScalar = detectorGain * makeupGain
                for channel in 0..<safeChannelCount {
                    guard frame < processedAudio[channel].count else { continue }
                    let dry = processedAudio[channel][frame]
                    let wet = dry * wetScalar
                    processedAudio[channel][frame] = dry + (wet - dry) * wetBlend
                }
            }

            if let id = nodeId {
                compressorEnvelopeByNode[id] = detectorGain
                compressorSmoothedGainByNode[id] = smoothedGain
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            } else {
                compressorEnvelope = detectorGain
                compressorSmoothedGain = smoothedGain
            }

        case .reverb:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.reverbEnabled
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.reverbMix ?? snapshot.reverbMix
            let sizeValue = nodeParams(for: nodeId, snapshot: snapshot)?.reverbSize ?? snapshot.reverbSize

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || mixValue <= 0) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (reverbSmoothedGainByNode[nodeId!] ?? 0) : reverbSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let targetId = nodeId
            var tank = targetId.flatMap { reverbStatesByNode[$0] } ?? reverbState
            tank.configure(sampleRate: sampleRate, channelCount: channelCount)
            let size = Float(min(max(sizeValue, 0), 1))
            let mix = Float(min(max(mixValue, 0), 1))
            let feedback = min(Float(0.62) + size * 0.30, 0.92)
            let damping = Float(0.18) + size * 0.18
            let inputSend = Float(0.45) + size * 0.20

            for frame in 0..<frameLength {
                smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    let wet = tank.process(
                        input: dry * inputSend,
                        channel: channel,
                        feedback: feedback,
                        damping: damping
                    )
                    let wetMix = smoothedGain * mix
                    processedAudio[channel][frame] = dry * (1 - wetMix) + wet * wetMix
                }
            }
            if let id = targetId {
                reverbStatesByNode[id] = tank
                reverbSmoothedGainByNode[id] = smoothedGain
            } else {
                reverbState = tank
                reverbSmoothedGain = smoothedGain
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .delay:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.delayEnabled
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.delayMix ?? snapshot.delayMix
            let feedbackValue = nodeParams(for: nodeId, snapshot: snapshot)?.delayFeedback ?? snapshot.delayFeedback
            let timeValue = nodeParams(for: nodeId, snapshot: snapshot)?.delayTime ?? snapshot.delayTime

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || mixValue <= 0) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (delaySmoothedGainByNode[nodeId!] ?? 0) : delaySmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let gainSmoothingCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.015)
            let parameterSmoothingCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.045)
            let bufferLength = max(Int(sampleRate * 2.05), 2)
            let targetDelaySamples = clampedFloat(timeValue, min: 0.01, max: 2.0) * Float(sampleRate)
            let targetMix = clampedFloat(mixValue, min: 0, max: 1)
            let targetFeedback = clampedFloat(feedbackValue, min: 0, max: 0.95)
            let targetId = nodeId
            var buffer = targetId.flatMap { delayBuffersByNode[$0] } ?? delayBuffer
            var writeIndex = targetId.flatMap { delayWriteIndexByNode[$0] } ?? delayWriteIndex
            var parameterState = targetId.flatMap { delayParameterStateByNode[$0] } ?? delayParameterState
            if buffer.count != channelCount || buffer.first?.count != bufferLength {
                buffer = [[Float]](repeating: [Float](repeating: 0, count: bufferLength), count: channelCount)
                writeIndex = min(writeIndex, bufferLength - 1)
            }
            if !parameterState.initialized {
                parameterState.initialized = true
                parameterState.delaySamples = targetDelaySamples
                parameterState.mix = targetMix
                parameterState.feedback = targetFeedback
            }

            for frame in 0..<frameLength {
                smoothParameter(&smoothedGain, target: targetGain, coefficient: gainSmoothingCoeff)
                smoothParameter(&parameterState.delaySamples, target: targetDelaySamples, coefficient: parameterSmoothingCoeff)
                smoothParameter(&parameterState.mix, target: targetMix, coefficient: parameterSmoothingCoeff)
                smoothParameter(&parameterState.feedback, target: targetFeedback, coefficient: parameterSmoothingCoeff)
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    let delayWet = readDelaySample(
                        buffer: buffer,
                        writeIndex: writeIndex,
                        delaySamples: Double(parameterState.delaySamples),
                        channel: channel
                    )
                    let mix = parameterState.mix
                    let wet = dry * (1.0 - mix) + delayWet * mix
                    buffer[channel][writeIndex] = softConstrainedSample(
                        dry + delayWet * parameterState.feedback,
                        knee: 1.2,
                        ceiling: 2.0
                    )
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
                writeIndex = (writeIndex + 1) % bufferLength
            }
            if let id = targetId {
                delayBuffersByNode[id] = buffer
                delayWriteIndexByNode[id] = writeIndex
                delaySmoothedGainByNode[id] = smoothedGain
                delayParameterStateByNode[id] = parameterState
            } else {
                delayBuffer = buffer
                delayWriteIndex = writeIndex
                delaySmoothedGain = smoothedGain
                delayParameterState = parameterState
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .amp:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.ampEnabled
            let params = nodeParams(for: nodeId, snapshot: snapshot)
            let inputGainDb = params?.ampInputGain ?? snapshot.ampInputGain
            let driveValue = params?.ampDrive ?? snapshot.ampDrive
            let outputGainDb = params?.ampOutputGain ?? snapshot.ampOutputGain
            let mixValue = params?.ampMix ?? snapshot.ampMix

            let normalizedDrive = min(max(driveValue, 0), 1)
            let active = !(isNodeDisabled || isGlobalDisabled)
                && (abs(inputGainDb) > 0.001 || normalizedDrive > 0.001 || abs(outputGainDb) > 0.001)
            let targetGain: Float = active ? 1 : 0

            var smoothedGain: Float = nodeId != nil ? (ampSmoothedGainByNode[nodeId!] ?? 0) : ampSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let inputGain = Float(pow(10.0, inputGainDb / 20.0))
            let outputGain = Float(pow(10.0, outputGainDb / 20.0))
            let driveAmount = Float(normalizedDrive)
            let preDrive = Float(1.0 + normalizedDrive * 22.0)
            let asymmetry = driveAmount * 0.12
            let centerOffset = tanhf(asymmetry * preDrive)
            let positiveNorm = max(tanhf((1.0 + asymmetry) * preDrive) - centerOffset, 0.0001)
            let clipPoint = max(Float(0.32), Float(0.95) - driveAmount * 0.55)
            let hardClipBlend = max(0, (driveAmount - 0.35) / 0.65) * 0.45
            let driveCompensation = Float(1.0 / (1.0 + Double(driveAmount) * 0.5))
            let mix = Float(min(max(mixValue, 0), 1))

            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                    let dry = processedAudio[channel][frame]
                    let preamped = dry * inputGain
                    let driven: Float
                    if driveAmount > 0.001 {
                        let biased = preamped + asymmetry
                        let softClipped = (tanhf(biased * preDrive) - centerOffset) / positiveNorm
                        let hardClipped = min(max(softClipped, -clipPoint), clipPoint) / clipPoint
                        let gritty = softClipped * (1.0 - hardClipBlend) + hardClipped * hardClipBlend
                        driven = gritty * driveCompensation
                    } else {
                        driven = preamped
                    }
                    let wet = (preamped * (1.0 - mix) + driven * mix) * outputGain
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
            }
            if let id = nodeId {
                ampSmoothedGainByNode[id] = smoothedGain
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            } else {
                ampSmoothedGain = smoothedGain
            }

        case .distortion:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.distortionEnabled
            let driveValue = nodeParams(for: nodeId, snapshot: snapshot)?.distortionDrive ?? snapshot.distortionDrive
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.distortionMix ?? snapshot.distortionMix

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || driveValue <= 0) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (distortionSmoothedGainByNode[nodeId!] ?? 0) : distortionSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let drive = Float(driveValue) * 10.0
            let mix = Float(mixValue)

            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                    let dry = processedAudio[channel][frame]
                    let driven = dry * drive
                    let distorted = tanhf(driven) / (1.0 + drive * 0.1)
                    let wet = dry * (1.0 - mix) + distorted * mix
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
            }
            if let id = nodeId {
                distortionSmoothedGainByNode[id] = smoothedGain
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            } else {
                distortionSmoothedGain = smoothedGain
            }

        case .tremolo:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.tremoloEnabled
            let rateValue = nodeParams(for: nodeId, snapshot: snapshot)?.tremoloRate ?? snapshot.tremoloRate
            let depthValue = nodeParams(for: nodeId, snapshot: snapshot)?.tremoloDepth ?? snapshot.tremoloDepth

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || depthValue <= 0) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (tremoloSmoothedGainByNode[nodeId!] ?? 0) : tremoloSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let rate = Float(rateValue)
            let depth = Float(depthValue)
            var phase = nodeId.flatMap { tremoloPhaseByNode[$0] } ?? tremoloPhase

            for frame in 0..<frameLength {
                smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                let lfoValue = (sin(Float(phase)) + 1.0) * 0.5
                let tremoloGain = 1.0 - (depth * (1.0 - lfoValue))
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    let wet = dry * tremoloGain
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
                phase += Double(rate) * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
            }
            if let id = nodeId {
                tremoloPhaseByNode[id] = phase
                tremoloSmoothedGainByNode[id] = smoothedGain
            } else {
                tremoloPhase = phase
                tremoloSmoothedGain = smoothedGain
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .autoPan:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.autoPanEnabled
            let rateValue = nodeParams(for: nodeId, snapshot: snapshot)?.autoPanRate ?? snapshot.autoPanRate
            let depthValue = nodeParams(for: nodeId, snapshot: snapshot)?.autoPanDepth ?? snapshot.autoPanDepth

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || depthValue <= 0 || channelCount < 2) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (autoPanSmoothedGainByNode[nodeId!] ?? 0) : autoPanSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let gainSmoothingCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.015)
            let parameterSmoothingCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.030)
            let targetRate = clampedFloat(rateValue, min: 0, max: 20)
            let targetDepth = clampedFloat(depthValue, min: 0, max: 1)
            var phase = nodeId.flatMap { autoPanPhaseByNode[$0] } ?? autoPanPhase
            var parameterState = nodeId.flatMap { autoPanParameterStateByNode[$0] } ?? autoPanParameterState
            if !parameterState.initialized {
                parameterState.initialized = true
                parameterState.rate = targetRate
                parameterState.depth = targetDepth
            }
            let safeChannelCount = min(channelCount, processedAudio.count)

            for frame in 0..<frameLength {
                smoothParameter(&smoothedGain, target: targetGain, coefficient: gainSmoothingCoeff)
                smoothParameter(&parameterState.rate, target: targetRate, coefficient: parameterSmoothingCoeff)
                smoothParameter(&parameterState.depth, target: targetDepth, coefficient: parameterSmoothingCoeff)
                let pan = sin(Float(phase)) * parameterState.depth
                let angle = (pan + 1.0) * (Float.pi / 4.0)
                let equalPowerCompensation = sqrtf(2.0)
                let leftPanGain = cosf(angle) * equalPowerCompensation
                let rightPanGain = sinf(angle) * equalPowerCompensation

                if safeChannelCount >= 2,
                   frame < processedAudio[0].count,
                   frame < processedAudio[1].count {
                    let dryLeft = processedAudio[0][frame]
                    let dryRight = processedAudio[1][frame]
                    let wetLeft = dryLeft * leftPanGain
                    let wetRight = dryRight * rightPanGain
                    processedAudio[0][frame] = dryLeft * (1 - smoothedGain) + wetLeft * smoothedGain
                    processedAudio[1][frame] = dryRight * (1 - smoothedGain) + wetRight * smoothedGain
                }

                phase += Double(parameterState.rate) * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
            }

            if let id = nodeId {
                autoPanPhaseByNode[id] = phase
                autoPanSmoothedGainByNode[id] = smoothedGain
                autoPanParameterStateByNode[id] = parameterState
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            } else {
                autoPanPhase = phase
                autoPanSmoothedGain = smoothedGain
                autoPanParameterState = parameterState
            }

        case .chorus:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.chorusEnabled
            let rateValue = nodeParams(for: nodeId, snapshot: snapshot)?.chorusRate ?? snapshot.chorusRate
            let depthValue = nodeParams(for: nodeId, snapshot: snapshot)?.chorusDepth ?? snapshot.chorusDepth
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.chorusMix ?? snapshot.chorusMix

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || mixValue <= 0) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (chorusSmoothedGainByNode[nodeId!] ?? 0) : chorusSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let gainSmoothingCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.015)
            let parameterSmoothingCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.035)
            let targetRate = clampedFloat(rateValue, min: 0.05, max: 8)
            let targetDepth = clampedFloat(depthValue, min: 0, max: 1)
            let targetMix = clampedFloat(mixValue, min: 0, max: 1)
            let baseDelay: Float = 0.018
            let maxDepthDelay: Float = 0.012
            let bufferLength = max(Int(sampleRate * 0.06), 2)
            let targetId = nodeId
            var buffer = targetId.flatMap { chorusBuffersByNode[$0] } ?? chorusBuffer
            var writeIndex = targetId.flatMap { chorusWriteIndexByNode[$0] } ?? chorusWriteIndex
            var phase = targetId.flatMap { chorusPhaseByNode[$0] } ?? chorusPhase
            var parameterState = targetId.flatMap { chorusParameterStateByNode[$0] } ?? chorusParameterState
            if buffer.count != channelCount || buffer.first?.count != bufferLength {
                buffer = [[Float]](repeating: [Float](repeating: 0, count: bufferLength), count: channelCount)
                writeIndex = min(writeIndex, bufferLength - 1)
            }
            if !parameterState.initialized {
                parameterState.initialized = true
                parameterState.rate = targetRate
                parameterState.depth = targetDepth
                parameterState.mix = targetMix
            }

            for frame in 0..<frameLength {
                smoothParameter(&smoothedGain, target: targetGain, coefficient: gainSmoothingCoeff)
                smoothParameter(&parameterState.rate, target: targetRate, coefficient: parameterSmoothingCoeff)
                smoothParameter(&parameterState.depth, target: targetDepth, coefficient: parameterSmoothingCoeff)
                smoothParameter(&parameterState.mix, target: targetMix, coefficient: parameterSmoothingCoeff)
                for channel in 0..<channelCount {
                    let channelOffset = channel % 2 == 0 ? 0.0 : Double.pi * 0.5
                    let lfo = Float((sin(phase + channelOffset) + 1) * 0.5)
                    let delaySamples = (baseDelay + maxDepthDelay * parameterState.depth * lfo) * Float(sampleRate)
                    let dry = processedAudio[channel][frame]
                    let chorusWet = readDelaySample(buffer: buffer, writeIndex: writeIndex, delaySamples: Double(delaySamples), channel: channel)
                    let mix = parameterState.mix
                    let wet = dry * (1 - mix) + chorusWet * mix
                    buffer[channel][writeIndex] = dry
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
                writeIndex = (writeIndex + 1) % bufferLength
                phase += Double(parameterState.rate) * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
            }

            if let id = targetId {
                chorusBuffersByNode[id] = buffer
                chorusWriteIndexByNode[id] = writeIndex
                chorusPhaseByNode[id] = phase
                chorusSmoothedGainByNode[id] = smoothedGain
                chorusParameterStateByNode[id] = parameterState
            } else {
                chorusBuffer = buffer
                chorusWriteIndex = writeIndex
                chorusPhase = phase
                chorusSmoothedGain = smoothedGain
                chorusParameterState = parameterState
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .phaser:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.phaserEnabled
            let rateValue = nodeParams(for: nodeId, snapshot: snapshot)?.phaserRate ?? snapshot.phaserRate
            let depthValue = nodeParams(for: nodeId, snapshot: snapshot)?.phaserDepth ?? snapshot.phaserDepth

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || depthValue <= 0) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (phaserSmoothedGainByNode[nodeId!] ?? 0) : phaserSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let gainSmoothingCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.015)
            let parameterSmoothingCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.035)
            let targetRate = clampedFloat(rateValue, min: 0.05, max: 8)
            let targetDepth = clampedFloat(depthValue, min: 0, max: 1)
            var phase = nodeId.flatMap { phaserPhaseByNode[$0] } ?? phaserPhase
            let targetId = nodeId
            var states = targetId.flatMap { phaserStatesByNode[$0] } ?? phaserStates
            var feedbackSamples = targetId.flatMap { phaserFeedbackSamplesByNode[$0] } ?? phaserFeedbackSamples
            var parameterState = targetId.flatMap { phaserParameterStateByNode[$0] } ?? phaserParameterState
            if states.count != channelCount || states.first?.count != phaserStageCount {
                states = Array(
                    repeating: Array(repeating: AllPassState(), count: phaserStageCount),
                    count: channelCount
                )
            }
            if feedbackSamples.count != channelCount {
                feedbackSamples = [Float](repeating: 0, count: channelCount)
            }
            if !parameterState.initialized {
                parameterState.initialized = true
                parameterState.rate = targetRate
                parameterState.depth = targetDepth
            }

            for frame in 0..<frameLength {
                smoothParameter(&smoothedGain, target: targetGain, coefficient: gainSmoothingCoeff)
                smoothParameter(&parameterState.rate, target: targetRate, coefficient: parameterSmoothingCoeff)
                smoothParameter(&parameterState.depth, target: targetDepth, coefficient: parameterSmoothingCoeff)
                let lfo = (sin(phase) + 1) * 0.5
                let sweep = 0.10 + pow(lfo, 1.25) * Double(max(parameterState.depth, 0.001)) * 0.90
                let freq = 180.0 * pow(2600.0 / 180.0, sweep)
                let g = tan(Double.pi * freq / sampleRate)
                let a = Float((1 - g) / (1 + g))
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    var sample = dry + feedbackSamples[channel] * 0.35
                    for stage in 0..<phaserStageCount {
                        var state = states[channel][stage]
                        sample = allPassProcess(x: sample, coefficient: a, state: &state)
                        states[channel][stage] = state
                    }
                    feedbackSamples[channel] = softConstrainedSample(sample, knee: 1.2, ceiling: 2.0)
                    let mix = min(0.85, 0.25 + parameterState.depth * 0.60)
                    let wet = dry * (1 - mix) + sample * mix
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
                phase += Double(parameterState.rate) * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
            }

            if let id = targetId {
                phaserStatesByNode[id] = states
                phaserPhaseByNode[id] = phase
                phaserFeedbackSamplesByNode[id] = feedbackSamples
                phaserSmoothedGainByNode[id] = smoothedGain
                phaserParameterStateByNode[id] = parameterState
            } else {
                phaserStates = states
                phaserPhase = phase
                phaserFeedbackSamples = feedbackSamples
                phaserSmoothedGain = smoothedGain
                phaserParameterState = parameterState
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .flanger:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.flangerEnabled
            let rateValue = nodeParams(for: nodeId, snapshot: snapshot)?.flangerRate ?? snapshot.flangerRate
            let depthValue = nodeParams(for: nodeId, snapshot: snapshot)?.flangerDepth ?? snapshot.flangerDepth
            let feedbackValue = nodeParams(for: nodeId, snapshot: snapshot)?.flangerFeedback ?? snapshot.flangerFeedback
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.flangerMix ?? snapshot.flangerMix

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || mixValue <= 0) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (flangerSmoothedGainByNode[nodeId!] ?? 0) : flangerSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let gainSmoothingCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.015)
            let parameterSmoothingCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.035)
            let targetRate = clampedFloat(rateValue, min: 0.05, max: 8)
            let targetDepth = clampedFloat(depthValue, min: 0, max: 1)
            let targetFeedback = clampedFloat(feedbackValue, min: 0, max: 0.9)
            let targetMix = clampedFloat(mixValue, min: 0, max: 1)
            let baseDelay: Float = 0.0015
            let maxDepthDelay: Float = 0.0045
            let bufferLength = max(Int(sampleRate * 0.02), 2)
            let targetId = nodeId
            var buffer = targetId.flatMap { flangerBuffersByNode[$0] } ?? flangerBuffer
            var writeIndex = targetId.flatMap { flangerWriteIndexByNode[$0] } ?? flangerWriteIndex
            var phase = targetId.flatMap { flangerPhaseByNode[$0] } ?? flangerPhase
            var parameterState = targetId.flatMap { flangerParameterStateByNode[$0] } ?? flangerParameterState
            if buffer.count != channelCount || buffer.first?.count != bufferLength {
                buffer = [[Float]](repeating: [Float](repeating: 0, count: bufferLength), count: channelCount)
                writeIndex = min(writeIndex, bufferLength - 1)
            }
            if !parameterState.initialized {
                parameterState.initialized = true
                parameterState.rate = targetRate
                parameterState.depth = targetDepth
                parameterState.feedback = targetFeedback
                parameterState.mix = targetMix
            }

            for frame in 0..<frameLength {
                smoothParameter(&smoothedGain, target: targetGain, coefficient: gainSmoothingCoeff)
                smoothParameter(&parameterState.rate, target: targetRate, coefficient: parameterSmoothingCoeff)
                smoothParameter(&parameterState.depth, target: targetDepth, coefficient: parameterSmoothingCoeff)
                smoothParameter(&parameterState.feedback, target: targetFeedback, coefficient: parameterSmoothingCoeff)
                smoothParameter(&parameterState.mix, target: targetMix, coefficient: parameterSmoothingCoeff)
                for channel in 0..<channelCount {
                    let channelOffset = channel % 2 == 0 ? 0.0 : Double.pi
                    let lfo = Float((sin(phase + channelOffset) + 1) * 0.5)
                    let delaySamples = (baseDelay + maxDepthDelay * parameterState.depth * lfo) * Float(sampleRate)
                    let dry = processedAudio[channel][frame]
                    let flangerWet = readDelaySample(buffer: buffer, writeIndex: writeIndex, delaySamples: Double(delaySamples), channel: channel)
                    let mix = parameterState.mix
                    let wet = dry * (1 - mix) + flangerWet * mix
                    buffer[channel][writeIndex] = softConstrainedSample(
                        dry + flangerWet * parameterState.feedback,
                        knee: 1.2,
                        ceiling: 2.0
                    )
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
                writeIndex = (writeIndex + 1) % bufferLength
                phase += Double(parameterState.rate) * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
            }

            if let id = targetId {
                flangerBuffersByNode[id] = buffer
                flangerWriteIndexByNode[id] = writeIndex
                flangerPhaseByNode[id] = phase
                flangerSmoothedGainByNode[id] = smoothedGain
                flangerParameterStateByNode[id] = parameterState
            } else {
                flangerBuffer = buffer
                flangerWriteIndex = writeIndex
                flangerPhase = phase
                flangerSmoothedGain = smoothedGain
                flangerParameterState = parameterState
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .bitcrusher:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.bitcrusherEnabled
            let bitDepthValue = Int(BitcrusherParameterLimits.boundedBitDepth(
                nodeParams(for: nodeId, snapshot: snapshot)?.bitcrusherBitDepth ?? snapshot.bitcrusherBitDepth))
            let downsampleValue = Int(BitcrusherParameterLimits.boundedDownsample(
                nodeParams(for: nodeId, snapshot: snapshot)?.bitcrusherDownsample ?? snapshot.bitcrusherDownsample))
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.bitcrusherMix ?? snapshot.bitcrusherMix

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || mixValue <= 0) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (bitcrusherSmoothedGainByNode[nodeId!] ?? 0) : bitcrusherSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let targetId = nodeId
            var counters = targetId.flatMap { bitcrusherHoldCountersByNode[$0] } ?? bitcrusherHoldCounters
            var holds = targetId.flatMap { bitcrusherHoldValuesByNode[$0] } ?? bitcrusherHoldValues
            if counters.count != channelCount {
                counters = [Int](repeating: 0, count: channelCount)
            }
            if holds.count != channelCount {
                holds = [Float](repeating: 0, count: channelCount)
            }
            let ds = max(downsampleValue, 1)
            let mix = Float(mixValue)

            for frame in 0..<frameLength {
                smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                for channel in 0..<channelCount {
                    if counters[channel] == 0 {
                        holds[channel] = processedAudio[channel][frame]
                        counters[channel] = ds - 1
                    } else {
                        counters[channel] -= 1
                    }
                    let crushed = quantizeSample(holds[channel], bitDepth: bitDepthValue)
                    let dry = processedAudio[channel][frame]
                    let wet = dry * (1 - mix) + crushed * mix
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
            }

            if let id = targetId {
                bitcrusherHoldCountersByNode[id] = counters
                bitcrusherHoldValuesByNode[id] = holds
                bitcrusherSmoothedGainByNode[id] = smoothedGain
            } else {
                bitcrusherHoldCounters = counters
                bitcrusherHoldValues = holds
                bitcrusherSmoothedGain = smoothedGain
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .tapeSaturation:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.tapeSaturationEnabled
            let driveValue = nodeParams(for: nodeId, snapshot: snapshot)?.tapeSaturationDrive ?? snapshot.tapeSaturationDrive
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.tapeSaturationMix ?? snapshot.tapeSaturationMix

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || mixValue <= 0) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (tapeSaturationSmoothedGainByNode[nodeId!] ?? 0) : tapeSaturationSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let drive = Float(1 + driveValue * 4)
            let mix = Float(mixValue)
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                    let dry = processedAudio[channel][frame]
                    let saturated = tanhf(dry * drive) / tanhf(drive)
                    let wet = dry * (1 - mix) + saturated * mix
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
            }
            if let id = nodeId {
                tapeSaturationSmoothedGainByNode[id] = smoothedGain
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            } else {
                tapeSaturationSmoothedGain = smoothedGain
            }

        case .stereoWidth:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.stereoWidthEnabled
            let amount = nodeParams(for: nodeId, snapshot: snapshot)?.stereoWidthAmount ?? snapshot.stereoWidthAmount

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || amount <= 0 || channelCount != 2) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (stereoWidthSmoothedGainByNode[nodeId!] ?? 0) : stereoWidthSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            for frame in 0..<frameLength {
                smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                let left = processedAudio[0][frame]
                let right = processedAudio[1][frame]
                let mid = (left + right) * 0.5
                let side = (left - right) * 0.5
                let width = Float(amount)
                let wideSide = side * (1.0 + width)
                let wetLeft = mid + wideSide
                let wetRight = mid - wideSide
                processedAudio[0][frame] = left * (1 - smoothedGain) + wetLeft * smoothedGain
                processedAudio[1][frame] = right * (1 - smoothedGain) + wetRight * smoothedGain
            }
            if let id = nodeId {
                stereoWidthSmoothedGainByNode[id] = smoothedGain
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            } else {
                stereoWidthSmoothedGain = smoothedGain
            }

        case .rubberBandPitch:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.rubberBandPitchEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let semitones = nodeParams(for: nodeId, snapshot: snapshot)?.rubberBandPitchSemitones ?? snapshot.rubberBandPitchSemitones
            guard abs(semitones) > 0.01 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let processor = rubberBandProcessor(for: nodeId, type: .rubberBandPitch, sampleRate: sampleRate, channels: channelCount)
            processor.setPitchSemitones(semitones)
            applyRubberBandInputSafety(
                to: &processedAudio,
                frameLength: frameLength,
                channelCount: channelCount,
                sampleRate: sampleRate,
                nodeId: nodeId
            )
            applyRubberBand(processor, to: &processedAudio, frameLength: frameLength, channelCount: channelCount, nodeId: nodeId)
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .resampling:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.resampleEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let rateValue = nodeParams(for: nodeId, snapshot: snapshot)?.resampleRate ?? snapshot.resampleRate
            let crossfadeValue = nodeParams(for: nodeId, snapshot: snapshot)?.resampleCrossfade ?? snapshot.resampleCrossfade
            guard rateValue > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let targetId = nodeId
            var buffer = targetId.flatMap { resampleBuffersByNode[$0] } ?? resampleBuffer
            var writeIndex = targetId.flatMap { resampleWriteIndexByNode[$0] } ?? resampleWriteIndex
            var readPhase = targetId.flatMap { resampleReadPhaseByNode[$0] } ?? resampleReadPhase
            var crossfadeRemaining = targetId.flatMap { resampleCrossfadeRemainingByNode[$0] } ?? resampleCrossfadeRemaining
            var crossfadeTotal = targetId.flatMap { resampleCrossfadeTotalByNode[$0] } ?? resampleCrossfadeTotal
            var crossfadeStartPhase = targetId.flatMap { resampleCrossfadeStartPhaseByNode[$0] } ?? resampleCrossfadeStartPhase
            var crossfadeTargetPhase = targetId.flatMap { resampleCrossfadeTargetPhaseByNode[$0] } ?? resampleCrossfadeTargetPhase
            var bufferReset = false
            let bufferSize = max(frameLength * 4, 4096)
            let safetyOffset = min(max(frameLength * 2, 1024), bufferSize - 1)
            let crossfadeMax = min(bufferSize / 2, 1024)
            let crossfadeSamples = max(32, min(Int(Double(frameLength) * min(max(crossfadeValue, 0.05), 0.6)), crossfadeMax))

            if buffer.count != channelCount || buffer.first?.count != bufferSize {
                buffer = [[Float]](repeating: [Float](repeating: 0, count: bufferSize), count: channelCount)
                writeIndex = 0
                readPhase = 0
                bufferReset = true
            }

            // Write input into ring buffer
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    buffer[channel][writeIndex] = processedAudio[channel][frame]
                }
                writeIndex = (writeIndex + 1) % bufferSize
            }

            if bufferReset {
                readPhase = Double((writeIndex - safetyOffset + bufferSize) % bufferSize)
                crossfadeRemaining = 0
            }

            let readIndex = Int(readPhase) % bufferSize
            let distance = (writeIndex - readIndex + bufferSize) % bufferSize
            if distance < safetyOffset && crossfadeRemaining == 0 {
                crossfadeTotal = crossfadeSamples
                crossfadeRemaining = crossfadeTotal
                crossfadeStartPhase = readPhase
                crossfadeTargetPhase = Double((writeIndex - safetyOffset + bufferSize) % bufferSize)
            }

            // Read resampled output using shared phase
            for frame in 0..<frameLength {
                let phaseIndex = readPhase
                let index0 = Int(phaseIndex) % bufferSize
                let index1 = (index0 + 1) % bufferSize
                let frac = Float(phaseIndex - Double(index0))

                if crossfadeRemaining > 0 {
                    let t = 1.0 - Double(crossfadeRemaining) / Double(max(crossfadeTotal, 1))
                    let startPhase = crossfadeStartPhase + (rateValue * Double(frame))
                    let targetPhase = crossfadeTargetPhase + (rateValue * Double(frame))
                    let startIdx0 = Int(startPhase) % bufferSize
                    let startIdx1 = (startIdx0 + 1) % bufferSize
                    let startFrac = Float(startPhase - Double(startIdx0))
                    let targetIdx0 = Int(targetPhase) % bufferSize
                    let targetIdx1 = (targetIdx0 + 1) % bufferSize
                    let targetFrac = Float(targetPhase - Double(targetIdx0))

                    for channel in 0..<channelCount {
                        let s0 = buffer[channel][startIdx0]
                        let s1 = buffer[channel][startIdx1]
                        let startSample = s0 + (s1 - s0) * startFrac
                        let t0 = buffer[channel][targetIdx0]
                        let t1 = buffer[channel][targetIdx1]
                        let targetSample = t0 + (t1 - t0) * targetFrac
                        processedAudio[channel][frame] = startSample * Float(1 - t) + targetSample * Float(t)
                    }

                    crossfadeRemaining -= 1
                    if crossfadeRemaining == 0 {
                        readPhase = crossfadeTargetPhase
                    }
                } else {
                    for channel in 0..<channelCount {
                        let s0 = buffer[channel][index0]
                        let s1 = buffer[channel][index1]
                        processedAudio[channel][frame] = s0 + (s1 - s0) * frac
                    }
                }

                readPhase += rateValue
                if readPhase >= Double(bufferSize) {
                    readPhase -= Double(bufferSize)
                }
            }

            if let id = targetId {
                resampleBuffersByNode[id] = buffer
                resampleWriteIndexByNode[id] = writeIndex
                resampleReadPhaseByNode[id] = readPhase
                resampleCrossfadeRemainingByNode[id] = crossfadeRemaining
                resampleCrossfadeTotalByNode[id] = crossfadeTotal
                resampleCrossfadeStartPhaseByNode[id] = crossfadeStartPhase
                resampleCrossfadeTargetPhaseByNode[id] = crossfadeTargetPhase
            } else {
                resampleBuffer = buffer
                resampleWriteIndex = writeIndex
                resampleReadPhase = readPhase
                resampleCrossfadeRemaining = crossfadeRemaining
                resampleCrossfadeTotal = crossfadeTotal
                resampleCrossfadeStartPhase = crossfadeStartPhase
                resampleCrossfadeTargetPhase = crossfadeTargetPhase
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .plugin:
            guard let nodeId else { return }
            let isEnabled = nodeIsEnabled(nodeId, snapshot: snapshot)
            if !isEnabled {
                if let lastWet = pluginWetScratchByNode[nodeId], (pluginWasEnabledByNode[nodeId] ?? false) {
                    let total = max(1, Int(sampleRate * 0.5))
                    if pluginCrossfadeOutRemainingByNode[nodeId] == nil || pluginCrossfadeOutRemainingByNode[nodeId] == 0 {
                        pluginCrossfadeOutTotalByNode[nodeId] = total
                        pluginCrossfadeOutRemainingByNode[nodeId] = total
                    }
                    let remaining = pluginCrossfadeOutRemainingByNode[nodeId] ?? 0
                    if remaining > 0 {
                        let start = max(0, total - remaining)
                        for channel in 0..<channelCount {
                            for frame in 0..<frameLength {
                                let pos = min(total, start + frame)
                                let t = Float(pos) / Float(total)
                                processedAudio[channel][frame] = lastWet[channel][frame] * (1 - t)
                                    + processedAudio[channel][frame] * t
                            }
                        }
                        let nextRemaining = remaining - frameLength
                        pluginCrossfadeOutRemainingByNode[nodeId] = max(0, nextRemaining)
                    }
                }
                pluginWasEnabledByNode[nodeId] = false
                pluginWasReadyByNode[nodeId] = false
                pluginStableOutputCountByNode[nodeId] = 0
                pluginHasStableOutputByNode[nodeId] = false
                pluginReadyDelaySamplesByNode[nodeId] = 0
                levelSnapshot[nodeId] = 0
                return
            }
            guard let renderState = snapshot.pluginRenderStates[nodeId] else { return }
            let wasEnabled = pluginWasEnabledByNode[nodeId] ?? false
            let wasReady = pluginWasReadyByNode[nodeId] ?? false
            pluginWasEnabledByNode[nodeId] = true
            pluginWasReadyByNode[nodeId] = true
            pluginCrossfadeOutRemainingByNode[nodeId] = 0
            if !wasEnabled || !wasReady {
                pluginStableOutputCountByNode[nodeId] = 0
                pluginHasStableOutputByNode[nodeId] = false
                pluginReadyDelaySamplesByNode[nodeId] = max(1, Int(sampleRate * 0.35))
            }

            var dryScratch = ensurePluginDryScratch(nodeId: nodeId, channelCount: channelCount, frameLength: frameLength)
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    dryScratch[channel][frame] = processedAudio[channel][frame]
                }
            }
            pluginDryScratchByNode[nodeId] = dryScratch
            let rendered = renderState.process(
                buffer: &processedAudio,
                frameLength: frameLength,
                sampleRate: sampleRate,
                channelCount: channelCount
            )
            if !rendered {
                processedAudio = dryScratch
                pluginWasReadyByNode[nodeId] = false
                pluginStableOutputCountByNode[nodeId] = 0
                pluginHasStableOutputByNode[nodeId] = false
                pluginReadyDelaySamplesByNode[nodeId] = 0
                levelSnapshot[nodeId] = computeRMS(
                    processedAudio,
                    frameLength: frameLength,
                    channelCount: channelCount
                )
                return
            }
            var wetScratch = ensurePluginWetScratch(nodeId: nodeId, channelCount: channelCount, frameLength: frameLength)
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    wetScratch[channel][frame] = processedAudio[channel][frame]
                }
            }
            pluginWetScratchByNode[nodeId] = wetScratch
            let stabilityThreshold: Float = 0.0005
            let stableBlocksRequired = 3
            if let delayRemaining = pluginReadyDelaySamplesByNode[nodeId], delayRemaining > 0 {
                pluginReadyDelaySamplesByNode[nodeId] = max(0, delayRemaining - frameLength)
                processedAudio = dryScratch
                levelSnapshot[nodeId] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
                return
            }
            if !(pluginHasStableOutputByNode[nodeId] ?? false) {
                let wetRms = computeRMS(wetScratch, frameLength: frameLength, channelCount: channelCount)
                var stableCount = pluginStableOutputCountByNode[nodeId] ?? 0
                if wetRms > stabilityThreshold {
                    stableCount += 1
                } else {
                    stableCount = 0
                }
                pluginStableOutputCountByNode[nodeId] = stableCount
                if stableCount >= stableBlocksRequired {
                    pluginHasStableOutputByNode[nodeId] = true
                    let total = max(1, Int(sampleRate * 0.5))
                    pluginCrossfadeTotalByNode[nodeId] = total
                    pluginCrossfadeRemainingByNode[nodeId] = total
                } else {
                    processedAudio = dryScratch
                    levelSnapshot[nodeId] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
                    return
                }
            }
            if let remaining = pluginCrossfadeRemainingByNode[nodeId], remaining > 0 {
                let total = max(1, pluginCrossfadeTotalByNode[nodeId] ?? remaining)
                let startIndex = max(0, total - remaining)
                for channel in 0..<channelCount {
                    for frame in 0..<frameLength {
                        let pos = min(total, startIndex + frame)
                        let t = Float(pos) / Float(total)
                        processedAudio[channel][frame] = dryScratch[channel][frame] * (1 - t) + processedAudio[channel][frame] * t
                    }
                }
                let nextRemaining = remaining - frameLength
                pluginCrossfadeRemainingByNode[nodeId] = max(0, nextRemaining)
            }
            levelSnapshot[nodeId] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
        }
    }

    func computeRMS(_ processedAudio: [[Float]], frameLength: Int, channelCount: Int) -> Float {
        guard frameLength > 0, channelCount > 0 else { return 0 }
        var sumRMSSquared: Float = 0
        for channel in 0..<channelCount {
            var channelRMS: Float = 0
            vDSP_rmsqv(processedAudio[channel], 1, &channelRMS, vDSP_Length(frameLength))
            sumRMSSquared += channelRMS * channelRMS
        }
        return sqrt(sumRMSSquared / Float(channelCount))
    }

    private func ensurePluginDryScratch(nodeId: UUID, channelCount: Int, frameLength: Int) -> [[Float]] {
        var scratch = pluginDryScratchByNode[nodeId] ?? []
        if scratch.count != channelCount {
            scratch = [[Float]](repeating: [Float](repeating: 0, count: frameLength), count: channelCount)
            pluginDryScratchByNode[nodeId] = scratch
            return scratch
        }
        let currentLength = scratch.first?.count ?? 0
        guard currentLength < frameLength else { return scratch }
        let extra = frameLength - currentLength
        for index in 0..<channelCount {
            scratch[index].append(contentsOf: repeatElement(0, count: extra))
        }
        pluginDryScratchByNode[nodeId] = scratch
        return scratch
    }

    private func ensurePluginWetScratch(nodeId: UUID, channelCount: Int, frameLength: Int) -> [[Float]] {
        var scratch = pluginWetScratchByNode[nodeId] ?? []
        if scratch.count != channelCount {
            scratch = [[Float]](repeating: [Float](repeating: 0, count: frameLength), count: channelCount)
            pluginWetScratchByNode[nodeId] = scratch
            return scratch
        }
        let currentLength = scratch.first?.count ?? 0
        guard currentLength < frameLength else { return scratch }
        let extra = frameLength - currentLength
        for index in 0..<channelCount {
            scratch[index].append(contentsOf: repeatElement(0, count: extra))
        }
        pluginWetScratchByNode[nodeId] = scratch
        return scratch
    }

    private func appleThreeBandEQProcessor(for nodeId: UUID) -> AppleThreeBandEQProcessor {
        if let processor = appleThreeBandEQProcessorsByNode[nodeId] {
            return processor
        }
        let processor = AppleThreeBandEQProcessor()
        appleThreeBandEQProcessorsByNode[nodeId] = processor
        return processor
    }

    private func ensureAppleThreeBandEQDryScratch(nodeId: UUID, channelCount: Int, frameLength: Int) -> [[Float]] {
        var scratch = appleThreeBandEQDryScratchByNode[nodeId] ?? []
        if scratch.count != channelCount {
            scratch = [[Float]](repeating: [Float](repeating: 0, count: frameLength), count: channelCount)
            appleThreeBandEQDryScratchByNode[nodeId] = scratch
            return scratch
        }
        let currentLength = scratch.first?.count ?? 0
        guard currentLength < frameLength else { return scratch }
        let extra = frameLength - currentLength
        for index in 0..<channelCount {
            scratch[index].append(contentsOf: repeatElement(0, count: extra))
        }
        appleThreeBandEQDryScratchByNode[nodeId] = scratch
        return scratch
    }

}
