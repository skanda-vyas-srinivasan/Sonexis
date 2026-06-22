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

    private func softConstrainedSample(_ sample: Float, knee: Float, ceiling: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > knee else { return sample }

        let sign: Float = sample >= 0 ? 1 : -1
        let range = max(ceiling - knee, 0.0001)
        let over = magnitude - knee
        let shaped = knee + (1 - Float(exp(Double(-over / range)))) * range
        return sign * min(shaped, ceiling)
    }

    private func clampedFloat(_ value: Double, min minValue: Float, max maxValue: Float) -> Float {
        min(max(Float(value), minValue), maxValue)
    }

    private func smoothingCoefficient(sampleRate: Double, timeConstant: Double) -> Float {
        guard sampleRate > 0, timeConstant > 0 else { return 1 }
        return Float(1.0 - exp(-1.0 / (sampleRate * timeConstant)))
    }

    private func smoothParameter(_ value: inout Float, target: Float, coefficient: Float) {
        value += (target - value) * coefficient
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

    private func signatureParameters(
        for effect: EffectType,
        params: NodeEffectParameters
    ) -> (primary: Float, secondary: Float) {
        switch effect {
        case .nightDrive:
            return (
                clampedFloat(params.nightDriveIntensity, min: 0, max: 1),
                clampedFloat(params.nightDriveWidth, min: 0, max: 1)
            )
        case .chromePunch:
            return (
                clampedFloat(params.chromePunchPunch, min: 0, max: 1),
                clampedFloat(params.chromePunchBody, min: 0, max: 1)
            )
        case .midnightGlow:
            return (
                clampedFloat(params.midnightGlowGlow, min: 0, max: 1),
                clampedFloat(params.midnightGlowWarmth, min: 0, max: 1)
            )
        case .afterglow:
            return (
                clampedFloat(params.afterglowAir, min: 0, max: 1),
                clampedFloat(params.afterglowSpace, min: 0, max: 1)
            )
        default:
            return (0, 0)
        }
    }

    private func signatureCoefficients(
        for effect: EffectType,
        primary: Float,
        secondary: Float,
        sampleRate: Double
    ) -> (low: BiquadCoefficients, mid: BiquadCoefficients, high: BiquadCoefficients) {
        switch effect {
        case .nightDrive:
            return (
                BiquadCoefficients.lowShelf(sampleRate: sampleRate, frequency: 88, gainDb: Double(primary * 9.0), q: 0.82),
                BiquadCoefficients.peakingEQ(sampleRate: sampleRate, frequency: 520, gainDb: Double(-primary * 4.0), q: 0.95),
                BiquadCoefficients.highShelf(sampleRate: sampleRate, frequency: 6200, gainDb: Double(-primary * 5.5), q: 0.70)
            )
        case .chromePunch:
            return (
                BiquadCoefficients.lowShelf(sampleRate: sampleRate, frequency: 115, gainDb: Double(secondary * 6.5), q: 0.92),
                BiquadCoefficients.peakingEQ(sampleRate: sampleRate, frequency: 2600, gainDb: Double(primary * 6.0), q: 1.25),
                BiquadCoefficients.highShelf(sampleRate: sampleRate, frequency: 7800, gainDb: Double(primary * 2.6), q: 0.72)
            )
        case .midnightGlow:
            return (
                BiquadCoefficients.lowShelf(sampleRate: sampleRate, frequency: 170, gainDb: Double(secondary * 5.5), q: 0.78),
                BiquadCoefficients.peakingEQ(sampleRate: sampleRate, frequency: 720, gainDb: Double(secondary * 3.2), q: 0.85),
                BiquadCoefficients.highShelf(sampleRate: sampleRate, frequency: 6400, gainDb: Double(-primary * 3.6), q: 0.72)
            )
        case .afterglow:
            return (
                BiquadCoefficients.lowShelf(sampleRate: sampleRate, frequency: 150, gainDb: Double(-secondary * 1.8), q: 0.74),
                BiquadCoefficients.peakingEQ(sampleRate: sampleRate, frequency: 3200, gainDb: Double(primary * 3.2), q: 1.05),
                BiquadCoefficients.highShelf(sampleRate: sampleRate, frequency: 7200, gainDb: Double(primary * 9.0), q: 0.66)
            )
        default:
            return (
                BiquadCoefficients.lowShelf(sampleRate: sampleRate, frequency: 100, gainDb: 0, q: 0.7),
                BiquadCoefficients.peakingEQ(sampleRate: sampleRate, frequency: 1000, gainDb: 0, q: 1.0),
                BiquadCoefficients.highShelf(sampleRate: sampleRate, frequency: 8000, gainDb: 0, q: 0.7)
            )
        }
    }

    private func applySignatureEffect(
        _ effect: EffectType,
        to processedAudio: inout [[Float]],
        sampleRate: Double,
        channelCount: Int,
        frameLength: Int,
        nodeId: UUID?,
        levelSnapshot: inout [UUID: Float],
        snapshot: ProcessingSnapshot
    ) {
        guard frameLength > 0, channelCount > 0 else { return }
        let isNodeDisabled = nodeId != nil && !nodeIsEnabled(nodeId!, snapshot: snapshot)
        let isGlobalDisabled = nodeId == nil
        guard let params = nodeParams(for: nodeId, snapshot: snapshot) else {
            if let id = nodeId { levelSnapshot[id] = 0 }
            return
        }

        let (primary, secondary) = signatureParameters(for: effect, params: params)
        let targetGain: Float = (isNodeDisabled || isGlobalDisabled || (primary <= 0 && secondary <= 0)) ? 0 : 1
        var state = nodeId.flatMap { signatureEffectStatesByNode[$0] }
            ?? signatureEffectStatesByType[effect]
            ?? SignatureEffectDSPState()

        if state.smoothedGain < 0.001 && targetGain < 0.001 {
            if let id = nodeId { levelSnapshot[id] = 0 }
            return
        }

        state.configure(channelCount: channelCount)
        if effect == .afterglow {
            state.reverb.configure(sampleRate: sampleRate, channelCount: channelCount)
        }

        let coefficients = signatureCoefficients(
            for: effect,
            primary: primary,
            secondary: secondary,
            sampleRate: sampleRate
        )
        let gainSmoothingCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.020)
        let safeChannelCount = min(channelCount, processedAudio.count)
        let attackCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.004)
        let releaseCoeff = smoothingCoefficient(sampleRate: sampleRate, timeConstant: 0.090)

        for frame in 0..<frameLength {
            smoothParameter(&state.smoothedGain, target: targetGain, coefficient: gainSmoothingCoeff)

            var peak: Float = 0
            for channel in 0..<safeChannelCount where frame < processedAudio[channel].count {
                peak = max(peak, abs(processedAudio[channel][frame]))
            }
            let envelopeCoeff = peak > state.envelope ? attackCoeff : releaseCoeff
            smoothParameter(&state.envelope, target: peak, coefficient: envelopeCoeff)
            let transient = max(peak - state.envelope, 0)

            for channel in 0..<safeChannelCount where frame < processedAudio[channel].count {
                let dry = processedAudio[channel][frame]
                let edge = abs(dry - state.previousSamples[channel])
                state.previousSamples[channel] = dry
                var wet = coefficients.low.process(x: dry, state: &state.lowStates[channel])
                wet = coefficients.mid.process(x: wet, state: &state.midStates[channel])
                wet = coefficients.high.process(x: wet, state: &state.highStates[channel])

                switch effect {
                case .nightDrive:
                    let drive = 1.0 + primary * 3.0
                    let norm = max(tanhf(drive), 0.0001)
                    wet = tanhf(wet * drive) / norm
                    wet *= 0.82 - primary * 0.08

                case .chromePunch:
                    let edgeAttack = min(edge * primary * 18.0, 0.9)
                    let transientAttack = min(transient * primary * 6.0, 0.65)
                    let hitGain = min(1.0 + edgeAttack + transientAttack, 2.1)
                    let drive = 1.0 + primary * 1.7
                    let norm = max(tanhf(drive), 0.0001)
                    wet = tanhf(wet * hitGain * drive) / norm
                    wet *= 0.86 - primary * 0.06

                case .midnightGlow:
                    let leveller = 1.12 + primary * 0.30 - min(state.envelope * primary * 0.42, 0.24)
                    let drive = 1.0 + (primary + secondary) * 1.25
                    let norm = max(tanhf(drive), 0.0001)
                    wet = tanhf(wet * leveller * drive) / norm
                    wet *= 0.86 - primary * 0.06

                case .afterglow:
                    let shimmerDrive = 1.0 + primary * 1.6
                    let shimmerNorm = max(tanhf(shimmerDrive), 0.0001)
                    wet = tanhf(wet * shimmerDrive) / shimmerNorm
                    let tail = state.reverb.process(
                        input: wet * (0.34 + secondary * 0.50),
                        channel: channel,
                        feedback: min(0.64 + secondary * 0.28, 0.90),
                        damping: 0.18 + (1.0 - primary) * 0.10
                    )
                    wet += tail * (0.18 + secondary * 0.62)
                    wet *= 0.84 - primary * 0.04
                    wet = softConstrainedSample(wet, knee: 1.15, ceiling: 2.0)

                default:
                    break
                }

                let blended = dry * (1 - state.smoothedGain) + wet * state.smoothedGain
                processedAudio[channel][frame] = softConstrainedSample(blended, knee: 1.25, ceiling: 2.2)
            }

            if effect == .nightDrive && safeChannelCount >= 2,
               frame < processedAudio[0].count,
               frame < processedAudio[1].count {
                let width = secondary * state.smoothedGain * 0.85
                let left = processedAudio[0][frame]
                let right = processedAudio[1][frame]
                let mid = (left + right) * 0.5
                let side = (left - right) * 0.5 * (1.0 + width)
                processedAudio[0][frame] = mid + side
                processedAudio[1][frame] = mid - side
            } else if effect == .afterglow && safeChannelCount >= 2,
                      frame < processedAudio[0].count,
                      frame < processedAudio[1].count {
                let width = secondary * state.smoothedGain * 0.55
                let left = processedAudio[0][frame]
                let right = processedAudio[1][frame]
                let mid = (left + right) * 0.5
                let side = (left - right) * 0.5 * (1.0 + width)
                processedAudio[0][frame] = mid + side
                processedAudio[1][frame] = mid - side
            }
        }

        if let id = nodeId {
            signatureEffectStatesByNode[id] = state
            levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
        } else {
            signatureEffectStatesByType[effect] = state
        }
    }

    var defaultEffectOrder: [EffectType] {
        [
            .bassBoost,
            .clarity,
            .simpleEQ,
            .reverb,
            .delay,
            .amp,
            .tremolo,
            .autoPan,
            .chorus,
            .phaser,
            .flanger,
            .bitcrusher,
            .tapeSaturation,
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

    func sanitizeEffectOutput(
        _ processedAudio: inout [[Float]],
        effect: EffectType,
        nodeId: UUID?,
        frameLength: Int,
        channelCount: Int
    ) {
        guard frameLength > 0, channelCount > 0 else { return }

        let faultLimit: Float = 16.0
        let headroomKnee: Float = 1.25
        let headroomCeiling: Float = 2.5
        var repairedSamples = 0
        var limitedSamples = 0
        let safeChannelCount = min(channelCount, processedAudio.count)

        for channel in 0..<safeChannelCount {
            let safeFrameCount = min(frameLength, processedAudio[channel].count)
            for frame in 0..<safeFrameCount {
                let sample = processedAudio[channel][frame]
                if !sample.isFinite {
                    processedAudio[channel][frame] = 0
                    repairedSamples += 1
                } else {
                    let magnitude = abs(sample)
                    if magnitude > faultLimit {
                        limitedSamples += 1
                        processedAudio[channel][frame] = softConstrainedSample(
                            sample,
                            knee: headroomKnee,
                            ceiling: headroomCeiling
                        )
                    } else if magnitude > headroomKnee {
                        processedAudio[channel][frame] = softConstrainedSample(
                            sample,
                            knee: headroomKnee,
                            ceiling: headroomCeiling
                        )
                    }
                }
            }
        }

        guard repairedSamples > 0 || limitedSamples > 0 else { return }

        registerDSPFault(
            effect: effect,
            nodeId: nodeId,
            repairedSamples: repairedSamples,
            limitedSamples: limitedSamples
        )

        if repairedSamples > 0 {
            resetFaultStateUnlocked(for: effect, nodeId: nodeId)
        }
    }

    private func resetFaultStateUnlocked(for effect: EffectType, nodeId: UUID?) {
        switch effect {
        case .bassBoost:
            resetBassBoostStateUnlocked(nodeId: nodeId)
        case .enhancer:
            resetEnhancerStateUnlocked(nodeId: nodeId)
        case .clarity:
            resetClarityStateUnlocked(nodeId: nodeId)
        case .deMud:
            resetDeMudStateUnlocked(nodeId: nodeId)
        case .simpleEQ:
            resetEQStateUnlocked(nodeId: nodeId)
        case .appleThreeBandEQ:
            resetAppleThreeBandEQStateUnlocked(nodeId: nodeId)
        case .tenBandEQ:
            resetTenBandEQStateUnlocked(nodeId: nodeId)
        case .compressor:
            resetCompressorStateUnlocked(nodeId: nodeId)
        case .reverb:
            resetReverbStateUnlocked(nodeId: nodeId)
        case .delay:
            resetDelayStateUnlocked(nodeId: nodeId)
        case .tremolo:
            resetTremoloStateUnlocked(nodeId: nodeId)
        case .autoPan:
            resetAutoPanStateUnlocked(nodeId: nodeId)
        case .chorus:
            resetChorusStateUnlocked(nodeId: nodeId)
        case .phaser:
            resetPhaserStateUnlocked(nodeId: nodeId)
        case .flanger:
            resetFlangerStateUnlocked(nodeId: nodeId)
        case .bitcrusher:
            resetBitcrusherStateUnlocked(nodeId: nodeId)
        case .resampling:
            resetResampleStateUnlocked(nodeId: nodeId)
        case .rubberBandPitch:
            resetRubberBandStateUnlocked(nodeId: nodeId)
        case .amp:
            resetAmpStateUnlocked(nodeId: nodeId)
        case .distortion:
            resetDistortionStateUnlocked(nodeId: nodeId)
        case .tapeSaturation:
            resetTapeSaturationStateUnlocked(nodeId: nodeId)
        case .stereoWidth:
            resetStereoWidthStateUnlocked(nodeId: nodeId)
        case .pitchShift:
            resetNightcoreStateUnlocked(nodeId: nodeId)
        case .plugin:
            resetPluginStateUnlocked(nodeId: nodeId)
        case .nightDrive, .chromePunch, .midnightGlow, .afterglow:
            resetSignatureEffectStateUnlocked(effect: effect, nodeId: nodeId)
        }
    }

    private func registerDSPFault(
        effect: EffectType,
        nodeId: UUID?,
        repairedSamples: Int,
        limitedSamples: Int
    ) {
        let effectCount = (dspFaultCountsByEffect[effect] ?? 0) + 1
        dspFaultCountsByEffect[effect] = effectCount

        if let nodeId {
            dspFaultCountsByNode[nodeId] = (dspFaultCountsByNode[nodeId] ?? 0) + 1
        }

        guard effectCount == 1 || effectCount % 100 == 0 else { return }

        let nodeText = nodeId.map { " node=\($0.uuidString)" } ?? ""
        DispatchQueue.main.async {
            print(
                "DSP fault guarded: \(effect.rawValue)\(nodeText), repaired=\(repairedSamples), limited=\(limitedSamples), count=\(effectCount)"
            )
        }
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

    private func applyRubberBandInputSafety(
        to processedAudio: inout [[Float]],
        frameLength: Int,
        channelCount: Int,
        sampleRate: Double,
        nodeId: UUID?
    ) {
        guard frameLength > 0, channelCount > 0 else { return }

        let ceiling: Float = 1.15
        var peak: Float = 0
        let safeChannelCount = min(channelCount, processedAudio.count)
        for channel in 0..<safeChannelCount {
            let safeFrameCount = min(frameLength, processedAudio[channel].count)
            for frame in 0..<safeFrameCount {
                let sample = processedAudio[channel][frame]
                if sample.isFinite {
                    peak = max(peak, abs(sample))
                }
            }
        }

        let targetGain: Float = peak > ceiling ? ceiling / peak : 1.0
        var safetyGain: Float
        if let id = nodeId {
            safetyGain = rubberBandSmoothedGainByNode[id] ?? 1.0
        } else {
            safetyGain = rubberBandSmoothedGain
        }
        if !safetyGain.isFinite || safetyGain <= 0 {
            safetyGain = 1.0
        }

        guard targetGain < 0.999 || safetyGain < 0.999 else { return }

        let attackCoeff: Float = 0.35
        let releaseCoeff = Float(1.0 - exp(-1.0 / max(sampleRate * 0.25, 1.0)))
        for frame in 0..<frameLength {
            let coeff = targetGain < safetyGain ? attackCoeff : releaseCoeff
            safetyGain += (targetGain - safetyGain) * coeff
            for channel in 0..<safeChannelCount {
                if frame < processedAudio[channel].count {
                    processedAudio[channel][frame] *= safetyGain
                }
            }
        }

        if let id = nodeId {
            rubberBandSmoothedGainByNode[id] = safetyGain
        } else {
            rubberBandSmoothedGain = safetyGain
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
            guard let instance = pluginHost.instance(for: nodeId) else { return }
            if !instance.isReady {
                pluginWasReadyByNode[nodeId] = false
                pluginStableOutputCountByNode[nodeId] = 0
                pluginHasStableOutputByNode[nodeId] = false
                pluginReadyDelaySamplesByNode[nodeId] = 0
                return
            }
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
            instance.process(
                buffer: &processedAudio,
                frameLength: frameLength,
                sampleRate: sampleRate,
                channelCount: channelCount
            )
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
    func processBuffer(_ input: [Float], output: inout [Float], delay: inout [Float], frameLength: Int? = nil) {
        let sampleCount = min(frameLength ?? input.count, input.count)
        guard sampleCount > 0 else { return }

        // vDSP_biquad expects the normalized RBJ coefficient convention used here.
        let coefficients: [Double] = [Double(b0), Double(b1), Double(b2), Double(a1), Double(a2)]

        guard let setup = vDSP_biquad_CreateSetup(coefficients, 1) else { return }
        defer { vDSP_biquad_DestroySetup(setup) }

        // Ensure output buffer is sized correctly
        if output.count < sampleCount {
            output = [Float](repeating: 0, count: sampleCount)
        }

        // Ensure delay buffer is sized correctly (4 elements for single section)
        if delay.count < 4 {
            delay = [Float](repeating: 0, count: 4)
        }

        vDSP_biquad(setup, &delay, input, 1, &output, 1, vDSP_Length(sampleCount))
    }
}
