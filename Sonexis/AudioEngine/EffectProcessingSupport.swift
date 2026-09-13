import Accelerate
import Foundation

extension AudioEngine {
    func normalizedBiquadStates(_ states: [BiquadState], channelCount: Int) -> [BiquadState] {
        guard states.count == channelCount else {
            return [BiquadState](repeating: BiquadState(), count: channelCount)
        }
        return states
    }

    func normalizedTenBandStates(_ states: [[BiquadState]]?, channelCount: Int) -> [[BiquadState]] {
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

    func readDelaySample(
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

    func allPassProcess(x: Float, coefficient a: Float, state: inout AllPassState) -> Float {
        let y = -a * x + state.x1 + a * state.y1
        state.x1 = x
        state.y1 = y
        return y
    }

    func quantizeSample(_ sample: Float, bitDepth: Int) -> Float {
        let clamped = min(max(sample, -1), 1)
        let levels = Float((1 << max(min(bitDepth, 16), 1)) - 1)
        let normalized = (clamped + 1) * 0.5
        let quantized = round(normalized * levels) / levels
        return quantized * 2 - 1
    }

    func softConstrainedSample(_ sample: Float, knee: Float, ceiling: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > knee else { return sample }

        let sign: Float = sample >= 0 ? 1 : -1
        let range = max(ceiling - knee, 0.0001)
        let over = magnitude - knee
        let shaped = knee + (1 - Float(exp(Double(-over / range)))) * range
        return sign * min(shaped, ceiling)
    }

    func clampedFloat(_ value: Double, min minValue: Float, max maxValue: Float) -> Float {
        min(max(Float(value), minValue), maxValue)
    }

    func smoothingCoefficient(sampleRate: Double, timeConstant: Double) -> Float {
        guard sampleRate > 0, timeConstant > 0 else { return 1 }
        return Float(1.0 - exp(-1.0 / (sampleRate * timeConstant)))
    }

    func smoothParameter(_ value: inout Float, target: Float, coefficient: Float) {
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

    func signatureParameters(
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

    func signatureCoefficients(
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

    func applySignatureEffect(
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

    func nodeParams(for nodeId: UUID?, snapshot: ProcessingSnapshot) -> NodeEffectParameters? {
        guard let nodeId else { return nil }
        return snapshot.nodeParameters[nodeId]
    }

    func nodeIsEnabled(_ nodeId: UUID?, snapshot: ProcessingSnapshot) -> Bool {
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

    func resetFaultStateUnlocked(for effect: EffectType, nodeId: UUID?) {
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

    func registerDSPFault(
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

    func rubberBandProcessor(
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

    func withRubberBandScratch(
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

    func applyRubberBand(
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

    func applyRubberBandInputSafety(
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

}
