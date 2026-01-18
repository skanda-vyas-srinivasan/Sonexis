import Accelerate
import Foundation

extension AudioEngine {
    private func normalizedBiquadStates(_ states: [BiquadState], channelCount: Int) -> [BiquadState] {
        guard states.count == channelCount else {
            return [BiquadState](repeating: BiquadState(), count: channelCount)
        }
        return states
    }

    private func normalizedTenBandStates(_ states: [[BiquadState]]?, channelCount: Int) -> [[BiquadState]] {
        if let states = states,
           states.count == tenBandFrequencies.count,
           !states.isEmpty,
           states.allSatisfy({ $0.count == channelCount }) {
            return states
        }
        return tenBandFrequencies.map { _ in
            [BiquadState](repeating: BiquadState(), count: channelCount)
        }
    }

    private func readDelaySample(
        buffer: [[Float]],
        writeIndex: Int,
        delaySamples: Double,
        channel: Int
    ) -> Float {
        let bufferSize = buffer[channel].count
        if bufferSize == 0 {
            return 0
        }
        let delay = max(min(delaySamples, Double(bufferSize - 1)), 0)
        let readPos = Double(writeIndex) - delay
        let wrapped = readPos < 0 ? readPos + Double(bufferSize) : readPos
        let index0 = Int(wrapped) % bufferSize
        let index1 = (index0 + 1) % bufferSize
        let frac = Float(wrapped - Double(index0))
        let s0 = buffer[channel][index0]
        let s1 = buffer[channel][index1]
        return s0 + (s1 - s0) * frac
    }

    private func allPassProcess(x: Float, coefficient a: Float, state: inout AllPassState) -> Float {
        let y = -a * x + state.x1 + a * state.y1
        state.x1 = x
        state.y1 = y
        return y
    }

    private func quantizeSample(_ sample: Float, bitDepth: Int) -> Float {
        let clamped = min(max(sample, -1), 1)
        let levels = Float((1 << max(min(bitDepth, 16), 1)) - 1)
        let normalized = (clamped + 1) * 0.5
        let quantized = round(normalized * levels) / levels
        return quantized * 2 - 1
    }

    func applySoftLimiter(_ buffer: [[Float]]) -> [[Float]] {
        let threshold: Float = 0.9
        var limited = buffer

        for channel in limited.indices {
            for index in limited[channel].indices {
                let sample = limited[channel][index]
                let magnitude = abs(sample)
                if magnitude > threshold {
                    let sign: Float = sample >= 0 ? 1 : -1
                    let over = magnitude - threshold
                    let compressed = threshold + (1 - exp(-over * 3.0)) * 0.2
                    limited[channel][index] = sign * min(compressed, 1.0)
                }
            }
        }
        return limited
    }

    var defaultEffectOrder: [EffectType] {
        [
            .bassBoost,
            .clarity,
            .deMud,
            .simpleEQ,
            .tenBandEQ,
            .compressor,
            .reverb,
            .delay,
            .distortion,
            .tremolo,
            .chorus,
            .phaser,
            .flanger,
            .bitcrusher,
            .tapeSaturation,
            .resampling,
            .rubberBandPitch,
            .stereoWidth
        ]
    }

    struct EffectNode {
        let id: UUID?
        let type: EffectType
    }

    private func nodeParams(for nodeId: UUID?, snapshot: ProcessingSnapshot) -> NodeEffectParameters? {
        guard let nodeId else { return nil }
        return snapshot.nodeParameters[nodeId]
    }

    private func nodeIsEnabled(_ nodeId: UUID?, snapshot: ProcessingSnapshot) -> Bool {
        guard let nodeId else { return true }
        return snapshot.nodeEnabled[nodeId] ?? true
    }

    private func rubberBandProcessor(
        for nodeId: UUID?,
        type: EffectType,
        sampleRate: Double,
        channels: Int
    ) -> RubberBandWrapper {
        if let nodeId {
            if let existing = rubberBandNodes[nodeId] {
                existing.configure(withSampleRate: sampleRate, channels: Int32(channels))
                return existing
            }
            let created = RubberBandWrapper(sampleRate: sampleRate, channels: Int32(channels))
            rubberBandNodes[nodeId] = created
            return created
        }

        if let existing = rubberBandGlobalByType[type] {
            existing.configure(withSampleRate: sampleRate, channels: Int32(channels))
            return existing
        }
        let created = RubberBandWrapper(sampleRate: sampleRate, channels: Int32(channels))
        rubberBandGlobalByType[type] = created
        return created
    }

    private func withRubberBandScratch(
        nodeId: UUID?,
        channelCount: Int,
        frameLength: Int,
        _ body: (inout RubberBandScratch) -> Void
    ) {
        let required = frameLength * channelCount
        if let nodeId {
            var scratch = rubberBandScratchByNode[nodeId] ?? RubberBandScratch()
            if scratch.capacity < required || scratch.channelCount != channelCount {
                scratch.interleaved = [Float](repeating: 0, count: required)
                scratch.output = [Float](repeating: 0, count: required)
                scratch.capacity = required
                scratch.channelCount = channelCount
            }
            body(&scratch)
            rubberBandScratchByNode[nodeId] = scratch
        } else {
            if rubberBandScratchGlobal.capacity < required || rubberBandScratchGlobal.channelCount != channelCount {
                rubberBandScratchGlobal.interleaved = [Float](repeating: 0, count: required)
                rubberBandScratchGlobal.output = [Float](repeating: 0, count: required)
                rubberBandScratchGlobal.capacity = required
                rubberBandScratchGlobal.channelCount = channelCount
            }
            body(&rubberBandScratchGlobal)
        }
    }

    private func applyRubberBand(
        _ processor: RubberBandWrapper,
        to processedAudio: inout [[Float]],
        frameLength: Int,
        channelCount: Int,
        nodeId: UUID?
    ) {
        guard frameLength > 0, channelCount > 0 else { return }
        withRubberBandScratch(nodeId: nodeId, channelCount: channelCount, frameLength: frameLength) { scratch in
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    scratch.interleaved[frame * channelCount + channel] = processedAudio[channel][frame]
                }
            }

            scratch.interleaved.withUnsafeBufferPointer { inputPtr in
                scratch.output.withUnsafeMutableBufferPointer { outputPtr in
                    guard let inputBase = inputPtr.baseAddress, let outputBase = outputPtr.baseAddress else { return }
                    _ = processor.processInput(
                        inputBase,
                        frames: Int32(frameLength),
                        channels: Int32(channelCount),
                        output: outputBase,
                        outputCapacity: Int32(frameLength)
                    )
                }
            }

            var index = 0
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    processedAudio[channel][frame] = scratch.output[index]
                    index += 1
                }
            }
        }
    }

    var tenBandGains: [Double] {
        [
            tenBand31,
            tenBand62,
            tenBand125,
            tenBand250,
            tenBand500,
            tenBand1k,
            tenBand2k,
            tenBand4k,
            tenBand8k,
            tenBand16k
        ]
    }

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
        switch effect {
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
                coefficients.processBuffer(processedAudio[channel], output: &biquadScratchBuffer, delay: &vdspDelays[channel])

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
                coefficients.processBuffer(processedAudio[channel], output: &biquadScratchBuffer, delay: &vdspDelays[channel])
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
                coefficients.processBuffer(processedAudio[channel], output: &biquadScratchBuffer, delay: &vdspDelays[channel])
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
                    bassCoefficients.processBuffer(processedAudio[channel], output: &biquadScratchBuffer, delay: &bassDelays[channel])
                } else {
                    biquadScratchBuffer = Array(processedAudio[channel].prefix(frameLength))
                }

                if mids != 0 {
                    midsCoefficients.processBuffer(biquadScratchBuffer, output: &biquadScratchBuffer2, delay: &midsDelays[channel])
                } else {
                    biquadScratchBuffer2 = biquadScratchBuffer
                }

                if treble != 0 {
                    trebleCoefficients.processBuffer(biquadScratchBuffer2, output: &biquadScratchBuffer, delay: &trebleDelays[channel])
                } else {
                    biquadScratchBuffer = biquadScratchBuffer2
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
                        bandCoefficients[band].processBuffer(biquadScratchBuffer, output: &biquadScratchBuffer2, delay: &vdspDelays[band][channel])
                    } else {
                        bandCoefficients[band].processBuffer(biquadScratchBuffer2, output: &biquadScratchBuffer, delay: &vdspDelays[band][channel])
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
            let strength = nodeParams(for: nodeId, snapshot: snapshot)?.compressorStrength ?? snapshot.compressorStrength

            let targetGain: Float = (isNodeDisabled || isGlobalDisabled || strength <= 0) ? 0 : 1

            var smoothedGain: Float = nodeId != nil ? (compressorSmoothedGainByNode[nodeId!] ?? 0) : compressorSmoothedGain

            if smoothedGain < 0.001 && targetGain < 0.001 {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                    let dry = processedAudio[channel][frame]
                    let threshold: Float = 0.5
                    let ratio: Float = 1.0 + Float(strength) * 3.0
                    let absInput = abs(dry)

                    let wet: Float
                    if absInput > threshold {
                        let excess = absInput - threshold
                        let compressed = threshold + excess / ratio
                        wet = (dry > 0 ? compressed : -compressed) * (1.0 + Float(strength) * 0.3)
                    } else {
                        wet = dry * (1.0 + Float(strength) * 0.3)
                    }

                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
            }
            if let id = nodeId {
                compressorSmoothedGainByNode[id] = smoothedGain
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            } else {
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
            let delayTime = 0.03 * sizeValue
            let delayFrames = max(Int(sampleRate * delayTime), 1)
            let targetId = nodeId
            var buffer = targetId.flatMap { reverbBuffersByNode[$0] } ?? reverbBuffer
            var writeIndex = targetId.flatMap { reverbWriteIndexByNode[$0] } ?? reverbWriteIndex

            if buffer.count != channelCount || buffer.first?.count != delayFrames {
                buffer = [[Float]](repeating: [Float](repeating: 0, count: delayFrames), count: channelCount)
                writeIndex = 0
            }

            for frame in 0..<frameLength {
                smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    let reverbWet = buffer[channel][writeIndex]
                    let mix = Float(mixValue)
                    let wet = dry * (1.0 - mix) + reverbWet * mix
                    buffer[channel][writeIndex] = dry + reverbWet * 0.5
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
                writeIndex = (writeIndex + 1) % delayFrames
            }
            if let id = targetId {
                reverbBuffersByNode[id] = buffer
                reverbWriteIndexByNode[id] = writeIndex
                reverbSmoothedGainByNode[id] = smoothedGain
            } else {
                reverbBuffer = buffer
                reverbWriteIndex = writeIndex
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

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let delayFrames = max(Int(sampleRate * timeValue), 1)
            let targetId = nodeId
            var buffer = targetId.flatMap { delayBuffersByNode[$0] } ?? delayBuffer
            var writeIndex = targetId.flatMap { delayWriteIndexByNode[$0] } ?? delayWriteIndex
            if buffer.count != channelCount || buffer.first?.count != delayFrames {
                buffer = [[Float]](repeating: [Float](repeating: 0, count: delayFrames), count: channelCount)
                writeIndex = 0
            }

            for frame in 0..<frameLength {
                smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    let delayWet = buffer[channel][writeIndex]
                    let mix = Float(mixValue)
                    let wet = dry * (1.0 - mix) + delayWet * mix
                    let feedback = Float(feedbackValue)
                    buffer[channel][writeIndex] = dry + delayWet * feedback
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
                writeIndex = (writeIndex + 1) % delayFrames
            }
            if let id = targetId {
                delayBuffersByNode[id] = buffer
                delayWriteIndexByNode[id] = writeIndex
                delaySmoothedGainByNode[id] = smoothedGain
            } else {
                delayBuffer = buffer
                delayWriteIndex = writeIndex
                delaySmoothedGain = smoothedGain
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
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

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let baseDelay = 0.02
            let depthDelay = 0.01 * depthValue
            let bufferLength = Int(sampleRate * 0.05)
            let targetId = nodeId
            var buffer = targetId.flatMap { chorusBuffersByNode[$0] } ?? chorusBuffer
            var writeIndex = targetId.flatMap { chorusWriteIndexByNode[$0] } ?? chorusWriteIndex
            var phase = targetId.flatMap { chorusPhaseByNode[$0] } ?? chorusPhase
            if buffer.count != channelCount || buffer.first?.count != bufferLength {
                buffer = [[Float]](repeating: [Float](repeating: 0, count: bufferLength), count: channelCount)
                writeIndex = 0
            }

            for frame in 0..<frameLength {
                smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                let lfo = (sin(phase) + 1) * 0.5
                let delaySamples = (baseDelay + depthDelay * lfo) * sampleRate
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    let chorusWet = readDelaySample(buffer: buffer, writeIndex: writeIndex, delaySamples: delaySamples, channel: channel)
                    let mix = Float(mixValue)
                    let wet = dry * (1 - mix) + chorusWet * mix
                    buffer[channel][writeIndex] = dry
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
                writeIndex = (writeIndex + 1) % bufferLength
                phase += rateValue * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
            }

            if let id = targetId {
                chorusBuffersByNode[id] = buffer
                chorusWriteIndexByNode[id] = writeIndex
                chorusPhaseByNode[id] = phase
                chorusSmoothedGainByNode[id] = smoothedGain
            } else {
                chorusBuffer = buffer
                chorusWriteIndex = writeIndex
                chorusPhase = phase
                chorusSmoothedGain = smoothedGain
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

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            var phase = nodeId.flatMap { phaserPhaseByNode[$0] } ?? phaserPhase
            let targetId = nodeId
            var states = targetId.flatMap { phaserStatesByNode[$0] } ?? phaserStates
            if states.count != channelCount || states.first?.count != phaserStageCount {
                states = Array(
                    repeating: Array(repeating: AllPassState(), count: phaserStageCount),
                    count: channelCount
                )
            }

            for frame in 0..<frameLength {
                smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                let lfo = (sin(phase) + 1) * 0.5
                let freq = 200 + lfo * (800 * depthValue)
                let g = tan(Double.pi * freq / sampleRate)
                let a = Float((1 - g) / (1 + g))
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    var sample = dry
                    for stage in 0..<phaserStageCount {
                        var state = states[channel][stage]
                        sample = allPassProcess(x: sample, coefficient: a, state: &state)
                        states[channel][stage] = state
                    }
                    let mix = Float(depthValue)
                    let wet = dry * (1 - mix) + sample * mix
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
                phase += rateValue * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
            }

            if let id = targetId {
                phaserStatesByNode[id] = states
                phaserPhaseByNode[id] = phase
                phaserSmoothedGainByNode[id] = smoothedGain
            } else {
                phaserStates = states
                phaserPhase = phase
                phaserSmoothedGain = smoothedGain
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

            let smoothingCoeff = Float(1.0 - exp(-1.0 / (sampleRate * 0.015)))
            let baseDelay = 0.003
            let depthDelay = 0.002 * depthValue
            let bufferLength = Int(sampleRate * 0.01)
            let targetId = nodeId
            var buffer = targetId.flatMap { flangerBuffersByNode[$0] } ?? flangerBuffer
            var writeIndex = targetId.flatMap { flangerWriteIndexByNode[$0] } ?? flangerWriteIndex
            var phase = targetId.flatMap { flangerPhaseByNode[$0] } ?? flangerPhase
            if buffer.count != channelCount || buffer.first?.count != bufferLength {
                buffer = [[Float]](repeating: [Float](repeating: 0, count: bufferLength), count: channelCount)
                writeIndex = 0
            }

            for frame in 0..<frameLength {
                smoothedGain += (targetGain - smoothedGain) * smoothingCoeff
                let lfo = (sin(phase) + 1) * 0.5
                let delaySamples = (baseDelay + depthDelay * lfo) * sampleRate
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    let flangerWet = readDelaySample(buffer: buffer, writeIndex: writeIndex, delaySamples: delaySamples, channel: channel)
                    let mix = Float(mixValue)
                    let wet = dry * (1 - mix) + flangerWet * mix
                    buffer[channel][writeIndex] = dry + flangerWet * Float(feedbackValue)
                    processedAudio[channel][frame] = dry * (1 - smoothedGain) + wet * smoothedGain
                }
                writeIndex = (writeIndex + 1) % bufferLength
                phase += rateValue * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
            }

            if let id = targetId {
                flangerBuffersByNode[id] = buffer
                flangerWriteIndexByNode[id] = writeIndex
                flangerPhaseByNode[id] = phase
                flangerSmoothedGainByNode[id] = smoothedGain
            } else {
                flangerBuffer = buffer
                flangerWriteIndex = writeIndex
                flangerPhase = phase
                flangerSmoothedGain = smoothedGain
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .bitcrusher:
            let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
            let isGlobalDisabled = nodeId == nil && !snapshot.bitcrusherEnabled
            let bitDepthValue = Int(nodeParams(for: nodeId, snapshot: snapshot)?.bitcrusherBitDepth ?? snapshot.bitcrusherBitDepth)
            let downsampleValue = Int(nodeParams(for: nodeId, snapshot: snapshot)?.bitcrusherDownsample ?? snapshot.bitcrusherDownsample)
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
        }
    }

    private func computeRMS(_ processedAudio: [[Float]], frameLength: Int, channelCount: Int) -> Float {
        guard frameLength > 0, channelCount > 0 else { return 0 }
        var sumRMSSquared: Float = 0
        for channel in 0..<channelCount {
            var channelRMS: Float = 0
            vDSP_rmsqv(processedAudio[channel], 1, &channelRMS, vDSP_Length(frameLength))
            sumRMSSquared += channelRMS * channelRMS
        }
        return sqrt(sumRMSSquared / Float(channelCount))
    }

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
        if compressorEnvelope.count != channelCount {
            compressorEnvelope = [Float](repeating: 0, count: channelCount)
        }
        if phaserStates.count != channelCount {
            phaserStates = Array(
                repeating: Array(repeating: AllPassState(), count: phaserStageCount),
                count: channelCount
            )
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
    }

    func resetFlangerStateUnlocked() {
        flangerBuffer.removeAll()
        flangerWriteIndex = 0
        flangerPhase = 0
        flangerBuffersByNode.removeAll()
        flangerWriteIndexByNode.removeAll()
        flangerPhaseByNode.removeAll()
    }

    func resetPhaserStateUnlocked() {
        phaserStates = Array(
            repeating: Array(repeating: AllPassState(), count: phaserStageCount),
            count: phaserStates.count
        )
        phaserPhase = 0
        phaserStatesByNode.removeAll()
        phaserPhaseByNode.removeAll()
    }

    func resetBitcrusherStateUnlocked() {
        bitcrusherHoldCounters = bitcrusherHoldCounters.map { _ in 0 }
        bitcrusherHoldValues = bitcrusherHoldValues.map { _ in 0 }
        bitcrusherHoldCountersByNode.removeAll()
        bitcrusherHoldValuesByNode.removeAll()
    }

    func resetEffectStateUnlocked() {
        resetBassBoostStateUnlocked()
        resetClarityStateUnlocked()
        resetDeMudStateUnlocked()
        resetEQStateUnlocked()
        resetTenBandEQStateUnlocked()
        resetCompressorStateUnlocked()
        tremoloPhase = 0
        resetReverbStateUnlocked()
        resetDelayStateUnlocked()
        resetChorusStateUnlocked()
        resetFlangerStateUnlocked()
        phaserPhase = 0
        resetBitcrusherStateUnlocked()
        resampleBuffer.removeAll()
        resampleWriteIndex = 0
        resampleReadPhase = 0
        resampleCrossfadeRemaining = 0
        resampleCrossfadeTotal = 0
        resampleCrossfadeStartPhase = 0
        resampleCrossfadeTargetPhase = 0
        rubberBandNodes.values.forEach { $0.reset() }
        rubberBandGlobalByType.values.forEach { $0.reset() }
        rubberBandNodes.removeAll()
        rubberBandGlobalByType.removeAll()
        rubberBandScratchByNode.removeAll()
        rubberBandScratchGlobal = RubberBandScratch()
        bassBoostStatesByNode.removeAll()
        clarityStatesByNode.removeAll()
        nightcoreStatesByNode.removeAll()
        deMudStatesByNode.removeAll()
        eqBassStatesByNode.removeAll()
        eqMidsStatesByNode.removeAll()
        eqTrebleStatesByNode.removeAll()
        tenBandStatesByNode.removeAll()
        reverbBuffersByNode.removeAll()
        reverbWriteIndexByNode.removeAll()
        delayBuffersByNode.removeAll()
        delayWriteIndexByNode.removeAll()
        tremoloPhaseByNode.removeAll()
        chorusBuffersByNode.removeAll()
        chorusWriteIndexByNode.removeAll()
        chorusPhaseByNode.removeAll()
        flangerBuffersByNode.removeAll()
        flangerWriteIndexByNode.removeAll()
        flangerPhaseByNode.removeAll()
        phaserStatesByNode.removeAll()
        bitcrusherHoldCountersByNode.removeAll()
        bitcrusherHoldValuesByNode.removeAll()
        resampleBuffersByNode.removeAll()
        resampleWriteIndexByNode.removeAll()
        resampleReadPhaseByNode.removeAll()
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
        if resets.contains(ResetFlags.chorus) { resetChorusStateUnlocked() }
        if resets.contains(ResetFlags.flanger) { resetFlangerStateUnlocked() }
        if resets.contains(ResetFlags.phaser) { resetPhaserStateUnlocked() }
        if resets.contains(ResetFlags.bitcrusher) { resetBitcrusherStateUnlocked() }
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
        compressorEnvelope = compressorEnvelope.map { _ in 0 }
    }

    func resetReverbState() {
        enqueueReset(.reverb)
    }

    func resetReverbStateUnlocked() {
        reverbBuffer.removeAll()
        reverbWriteIndex = 0
    }

    func resetDelayState() {
        enqueueReset(.delay)
    }

    func resetDelayStateUnlocked() {
        delayBuffer.removeAll()
        delayWriteIndex = 0
    }

    func resetChorusState() {
        enqueueReset(.chorus)
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

// MARK: - Bass Boost Biquad

struct BiquadState {
    var x1: Float = 0
    var x2: Float = 0
    var y1: Float = 0
    var y2: Float = 0
}

struct AllPassState {
    var x1: Float = 0
    var y1: Float = 0
}

struct BiquadCoefficients {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0

    static func lowShelf(sampleRate: Double, frequency: Double, gainDb: Double, q: Double) -> BiquadCoefficients {
        let a = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / (2.0 * q)
        let sqrtA = sqrt(a)

        let b0 =    a * ((a + 1.0) - (a - 1.0) * cosw0 + 2.0 * sqrtA * alpha)
        let b1 =  2.0 * a * ((a - 1.0) - (a + 1.0) * cosw0)
        let b2 =    a * ((a + 1.0) - (a - 1.0) * cosw0 - 2.0 * sqrtA * alpha)
        let a0 =        (a + 1.0) + (a - 1.0) * cosw0 + 2.0 * sqrtA * alpha
        let a1 =   -2.0 * ((a - 1.0) + (a + 1.0) * cosw0)
        let a2 =        (a + 1.0) + (a - 1.0) * cosw0 - 2.0 * sqrtA * alpha

        return BiquadCoefficients(
            b0: Float(b0 / a0),
            b1: Float(b1 / a0),
            b2: Float(b2 / a0),
            a1: Float(a1 / a0),
            a2: Float(a2 / a0)
        )
    }

    static func highShelf(sampleRate: Double, frequency: Double, gainDb: Double, q: Double) -> BiquadCoefficients {
        let a = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / (2.0 * q)
        let sqrtA = sqrt(a)

        let b0 =    a * ((a + 1.0) + (a - 1.0) * cosw0 + 2.0 * sqrtA * alpha)
        let b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cosw0)
        let b2 =    a * ((a + 1.0) + (a - 1.0) * cosw0 - 2.0 * sqrtA * alpha)
        let a0 =        (a + 1.0) - (a - 1.0) * cosw0 + 2.0 * sqrtA * alpha
        let a1 =    2.0 * ((a - 1.0) - (a + 1.0) * cosw0)
        let a2 =        (a + 1.0) - (a - 1.0) * cosw0 - 2.0 * sqrtA * alpha

        return BiquadCoefficients(
            b0: Float(b0 / a0),
            b1: Float(b1 / a0),
            b2: Float(b2 / a0),
            a1: Float(a1 / a0),
            a2: Float(a2 / a0)
        )
    }

    static func peakingEQ(sampleRate: Double, frequency: Double, gainDb: Double, q: Double) -> BiquadCoefficients {
        let a = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / (2.0 * q)

        let b0 =  1.0 + alpha * a
        let b1 = -2.0 * cosw0
        let b2 =  1.0 - alpha * a
        let a0 =  1.0 + alpha / a
        let a1 = -2.0 * cosw0
        let a2 =  1.0 - alpha / a

        return BiquadCoefficients(
            b0: Float(b0 / a0),
            b1: Float(b1 / a0),
            b2: Float(b2 / a0),
            a1: Float(a1 / a0),
            a2: Float(a2 / a0)
        )
    }

    func process(x: Float, state: inout BiquadState) -> Float {
        let y = b0 * x + b1 * state.x1 + b2 * state.x2 - a1 * state.y1 - a2 * state.y2
        state.x2 = state.x1
        state.x1 = x
        state.y2 = state.y1
        state.y1 = y
        return y
    }

    /// Process entire buffer using vDSP_biquad (vectorized, ~3x faster)
    /// - Parameters:
    ///   - input: Input samples for one channel
    ///   - output: Output buffer (will be overwritten)
    ///   - delay: vDSP delay state, must have 4 elements, persists between calls
    func processBuffer(_ input: [Float], output: inout [Float], delay: inout [Float]) {
        guard input.count > 0 else { return }

        // vDSP_biquad expects coefficients as [b0, b1, b2, a1, a2] in Double
        let coefficients: [Double] = [Double(b0), Double(b1), Double(b2), Double(a1), Double(a2)]

        guard let setup = vDSP_biquad_CreateSetup(coefficients, 1) else { return }
        defer { vDSP_biquad_DestroySetup(setup) }

        // Ensure output buffer is sized correctly
        if output.count < input.count {
            output = [Float](repeating: 0, count: input.count)
        }

        // Ensure delay buffer is sized correctly (4 elements for single section)
        if delay.count < 4 {
            delay = [Float](repeating: 0, count: 4)
        }

        vDSP_biquad(setup, &delay, input, 1, &output, 1, vDSP_Length(input.count))
    }
}
