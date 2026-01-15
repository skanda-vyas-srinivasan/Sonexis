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
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.bassBoostEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let amount = nodeParams(for: nodeId, snapshot: snapshot)?.bassBoostAmount ?? snapshot.bassBoostAmount
            guard amount > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let gainDb = min(max(amount, 0), 1) * 24.0
            let coefficients = BiquadCoefficients.lowShelf(
                sampleRate: sampleRate,
                frequency: 80,
                gainDb: gainDb,
                q: 0.8
            )
            var states: [BiquadState]
            if let id = nodeId {
                states = bassBoostStatesByNode[id] ?? [BiquadState](repeating: BiquadState(), count: channelCount)
            } else {
                states = bassBoostState
            }
            states = normalizedBiquadStates(states, channelCount: channelCount)
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    var state = states[channel]
                    let y = coefficients.process(x: processedAudio[channel][frame], state: &state)
                    let gain = 1.0 + Float(min(max(amount, 0), 1)) * 0.35
                    processedAudio[channel][frame] = y * gain
                    states[channel] = state
                }
            }
            if let id = nodeId {
                bassBoostStatesByNode[id] = states
            } else {
                bassBoostState = states
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
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.clarityEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let amount = nodeParams(for: nodeId, snapshot: snapshot)?.clarityAmount ?? snapshot.clarityAmount
            guard amount > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let gainDb = min(max(amount, 0), 1) * 12.0
            let coefficients = BiquadCoefficients.highShelf(
                sampleRate: sampleRate,
                frequency: 3000,
                gainDb: gainDb,
                q: 0.7
            )
            var states: [BiquadState]
            if let id = nodeId {
                states = clarityStatesByNode[id] ?? [BiquadState](repeating: BiquadState(), count: channelCount)
            } else {
                states = clarityState
            }
            states = normalizedBiquadStates(states, channelCount: channelCount)
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    var state = states[channel]
                    let y = coefficients.process(x: processedAudio[channel][frame], state: &state)
                    processedAudio[channel][frame] = y
                    states[channel] = state
                }
            }
            if let id = nodeId {
                clarityStatesByNode[id] = states
            } else {
                clarityState = states
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .deMud:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.deMudEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let strength = nodeParams(for: nodeId, snapshot: snapshot)?.deMudStrength ?? snapshot.deMudStrength
            guard strength > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let gainDb = -min(max(strength, 0), 1) * 8.0
            let coefficients = BiquadCoefficients.peakingEQ(
                sampleRate: sampleRate,
                frequency: 250,
                gainDb: gainDb,
                q: 1.5
            )
            var states: [BiquadState]
            if let id = nodeId {
                states = deMudStatesByNode[id] ?? [BiquadState](repeating: BiquadState(), count: channelCount)
            } else {
                states = deMudState
            }
            states = normalizedBiquadStates(states, channelCount: channelCount)
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    var state = states[channel]
                    let y = coefficients.process(x: processedAudio[channel][frame], state: &state)
                    processedAudio[channel][frame] = y
                    states[channel] = state
                }
            }
            if let id = nodeId {
                deMudStatesByNode[id] = states
            } else {
                deMudState = states
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .simpleEQ:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.simpleEQEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let params = nodeParams(for: nodeId, snapshot: snapshot)
            let bass = params?.eqBass ?? snapshot.eqBass
            let mids = params?.eqMids ?? snapshot.eqMids
            let treble = params?.eqTreble ?? snapshot.eqTreble
            guard bass != 0 || mids != 0 || treble != 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
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
            let targetId = nodeId
            var bassStates = targetId.flatMap { eqBassStatesByNode[$0] } ?? eqBassState
            var midsStates = targetId.flatMap { eqMidsStatesByNode[$0] } ?? eqMidsState
            var trebleStates = targetId.flatMap { eqTrebleStatesByNode[$0] } ?? eqTrebleState
            bassStates = normalizedBiquadStates(bassStates, channelCount: channelCount)
            midsStates = normalizedBiquadStates(midsStates, channelCount: channelCount)
            trebleStates = normalizedBiquadStates(trebleStates, channelCount: channelCount)

            if bass != 0 {
                for channel in 0..<channelCount {
                    for frame in 0..<frameLength {
                        var state = bassStates[channel]
                        let y = bassCoefficients.process(x: processedAudio[channel][frame], state: &state)
                        processedAudio[channel][frame] = y
                        bassStates[channel] = state
                    }
                }
            }

            if mids != 0 {
                for channel in 0..<channelCount {
                    for frame in 0..<frameLength {
                        var state = midsStates[channel]
                        let y = midsCoefficients.process(x: processedAudio[channel][frame], state: &state)
                        processedAudio[channel][frame] = y
                        midsStates[channel] = state
                    }
                }
            }

            if treble != 0 {
                for channel in 0..<channelCount {
                    for frame in 0..<frameLength {
                        var state = trebleStates[channel]
                        let y = trebleCoefficients.process(x: processedAudio[channel][frame], state: &state)
                        processedAudio[channel][frame] = y
                        trebleStates[channel] = state
                    }
                }
            }
            if let id = targetId {
                eqBassStatesByNode[id] = bassStates
                eqMidsStatesByNode[id] = midsStates
                eqTrebleStatesByNode[id] = trebleStates
            } else {
                eqBassState = bassStates
                eqMidsState = midsStates
                eqTrebleState = trebleStates
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .tenBandEQ:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.tenBandEQEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let gains = nodeParams(for: nodeId, snapshot: snapshot)?.tenBandGains ?? snapshot.tenBandGains
            guard gains.contains(where: { $0 != 0 }) else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
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
            let targetId = nodeId
            var bandStates = normalizedTenBandStates(
                targetId.flatMap { tenBandStatesByNode[$0] },
                channelCount: channelCount
            )

            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    var sample = processedAudio[channel][frame]
                    for band in 0..<tenBandFrequencies.count {
                        var state = bandStates[band][channel]
                        sample = bandCoefficients[band].process(x: sample, state: &state)
                        bandStates[band][channel] = state
                    }
                    processedAudio[channel][frame] = sample
                }
            }
            if let id = targetId {
                tenBandStatesByNode[id] = bandStates
            } else {
                tenBandStates = bandStates
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .compressor:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.compressorEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let strength = nodeParams(for: nodeId, snapshot: snapshot)?.compressorStrength ?? snapshot.compressorStrength
            guard strength > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    let input = processedAudio[channel][frame]
                    let threshold: Float = 0.5
                    let ratio: Float = 1.0 + Float(strength) * 3.0
                    let absInput = abs(input)

                    let output: Float
                    if absInput > threshold {
                        let excess = absInput - threshold
                        let compressed = threshold + excess / ratio
                        output = input > 0 ? compressed : -compressed
                    } else {
                        output = input
                    }

                    processedAudio[channel][frame] = output * (1.0 + Float(strength) * 0.3)
                }
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .reverb:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.reverbEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.reverbMix ?? snapshot.reverbMix
            let sizeValue = nodeParams(for: nodeId, snapshot: snapshot)?.reverbSize ?? snapshot.reverbSize
            guard mixValue > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let delayTime = 0.03 * sizeValue
            let delayFrames = Int(sampleRate * delayTime)
            guard delayFrames > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let targetId = nodeId
            var buffer = targetId.flatMap { reverbBuffersByNode[$0] } ?? reverbBuffer
            var writeIndex = targetId.flatMap { reverbWriteIndexByNode[$0] } ?? reverbWriteIndex

            if buffer.count != channelCount || buffer.first?.count != delayFrames {
                buffer = [[Float]](repeating: [Float](repeating: 0, count: delayFrames), count: channelCount)
                writeIndex = 0
            }

            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    let wet = buffer[channel][writeIndex]
                    let mix = Float(mixValue)
                    processedAudio[channel][frame] = dry * (1.0 - mix) + wet * mix
                    buffer[channel][writeIndex] = dry + wet * 0.5
                }
                writeIndex = (writeIndex + 1) % delayFrames
            }
            if let id = targetId {
                reverbBuffersByNode[id] = buffer
                reverbWriteIndexByNode[id] = writeIndex
            } else {
                reverbBuffer = buffer
                reverbWriteIndex = writeIndex
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .delay:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.delayEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.delayMix ?? snapshot.delayMix
            let feedbackValue = nodeParams(for: nodeId, snapshot: snapshot)?.delayFeedback ?? snapshot.delayFeedback
            let timeValue = nodeParams(for: nodeId, snapshot: snapshot)?.delayTime ?? snapshot.delayTime
            guard mixValue > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let delayFrames = Int(sampleRate * timeValue)
            guard delayFrames > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let targetId = nodeId
            var buffer = targetId.flatMap { delayBuffersByNode[$0] } ?? delayBuffer
            var writeIndex = targetId.flatMap { delayWriteIndexByNode[$0] } ?? delayWriteIndex
            if buffer.count != channelCount || buffer.first?.count != delayFrames {
                buffer = [[Float]](repeating: [Float](repeating: 0, count: delayFrames), count: channelCount)
                writeIndex = 0
            }

            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    let dry = processedAudio[channel][frame]
                    let wet = buffer[channel][writeIndex]
                    let mix = Float(mixValue)
                    processedAudio[channel][frame] = dry * (1.0 - mix) + wet * mix
                    let feedback = Float(feedbackValue)
                    buffer[channel][writeIndex] = dry + wet * feedback
                    writeIndex = (writeIndex + 1) % delayFrames
                }
            }
            if let id = targetId {
                delayBuffersByNode[id] = buffer
                delayWriteIndexByNode[id] = writeIndex
            } else {
                delayBuffer = buffer
                delayWriteIndex = writeIndex
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .distortion:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.distortionEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let driveValue = nodeParams(for: nodeId, snapshot: snapshot)?.distortionDrive ?? snapshot.distortionDrive
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.distortionMix ?? snapshot.distortionMix
            guard driveValue > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let drive = Float(driveValue) * 10.0
            let mix = Float(mixValue)

            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    let dry = processedAudio[channel][frame]
                    let driven = dry * drive
                    let wet = tanhf(driven) / (1.0 + drive * 0.1)
                    processedAudio[channel][frame] = dry * (1.0 - mix) + wet * mix
                }
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .tremolo:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.tremoloEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let rateValue = nodeParams(for: nodeId, snapshot: snapshot)?.tremoloRate ?? snapshot.tremoloRate
            let depthValue = nodeParams(for: nodeId, snapshot: snapshot)?.tremoloDepth ?? snapshot.tremoloDepth
            guard depthValue > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let rate = Float(rateValue)
            let depth = Float(depthValue)
            var phase = nodeId.flatMap { tremoloPhaseByNode[$0] } ?? tremoloPhase

            for frame in 0..<frameLength {
                let lfoValue = (sin(Float(phase)) + 1.0) * 0.5
                let gain = 1.0 - (depth * (1.0 - lfoValue))
                for channel in 0..<channelCount {
                    processedAudio[channel][frame] *= gain
                }

                phase += Double(rate) * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi {
                    phase -= 2.0 * .pi
                }
            }
            if let id = nodeId {
                tremoloPhaseByNode[id] = phase
            } else {
                tremoloPhase = phase
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .chorus:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.chorusEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let rateValue = nodeParams(for: nodeId, snapshot: snapshot)?.chorusRate ?? snapshot.chorusRate
            let depthValue = nodeParams(for: nodeId, snapshot: snapshot)?.chorusDepth ?? snapshot.chorusDepth
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.chorusMix ?? snapshot.chorusMix
            guard mixValue > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
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
                let lfo = (sin(phase) + 1) * 0.5
                let delaySamples = (baseDelay + depthDelay * lfo) * sampleRate
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    let wet = readDelaySample(buffer: buffer, writeIndex: writeIndex, delaySamples: delaySamples, channel: channel)
                    let mix = Float(mixValue)
                    processedAudio[channel][frame] = dry * (1 - mix) + wet * mix
                    buffer[channel][writeIndex] = dry
                }
                writeIndex = (writeIndex + 1) % bufferLength
                phase += rateValue * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
            }

            if let id = targetId {
                chorusBuffersByNode[id] = buffer
                chorusWriteIndexByNode[id] = writeIndex
                chorusPhaseByNode[id] = phase
            } else {
                chorusBuffer = buffer
                chorusWriteIndex = writeIndex
                chorusPhase = phase
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .phaser:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.phaserEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let rateValue = nodeParams(for: nodeId, snapshot: snapshot)?.phaserRate ?? snapshot.phaserRate
            let depthValue = nodeParams(for: nodeId, snapshot: snapshot)?.phaserDepth ?? snapshot.phaserDepth
            guard depthValue > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
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
                let lfo = (sin(phase) + 1) * 0.5
                let freq = 200 + lfo * (800 * depthValue)
                let g = tan(Double.pi * freq / sampleRate)
                let a = Float((1 - g) / (1 + g))
                for channel in 0..<channelCount {
                    var sample = processedAudio[channel][frame]
                    for stage in 0..<phaserStageCount {
                        var state = states[channel][stage]
                        sample = allPassProcess(x: sample, coefficient: a, state: &state)
                        states[channel][stage] = state
                    }
                    let mix = Float(depthValue)
                    processedAudio[channel][frame] = processedAudio[channel][frame] * (1 - mix) + sample * mix
                }
                phase += rateValue * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
            }

            if let id = targetId {
                phaserStatesByNode[id] = states
                phaserPhaseByNode[id] = phase
            } else {
                phaserStates = states
                phaserPhase = phase
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .flanger:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.flangerEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let rateValue = nodeParams(for: nodeId, snapshot: snapshot)?.flangerRate ?? snapshot.flangerRate
            let depthValue = nodeParams(for: nodeId, snapshot: snapshot)?.flangerDepth ?? snapshot.flangerDepth
            let feedbackValue = nodeParams(for: nodeId, snapshot: snapshot)?.flangerFeedback ?? snapshot.flangerFeedback
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.flangerMix ?? snapshot.flangerMix
            guard mixValue > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
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
                let lfo = (sin(phase) + 1) * 0.5
                let delaySamples = (baseDelay + depthDelay * lfo) * sampleRate
                for channel in 0..<channelCount {
                    let dry = processedAudio[channel][frame]
                    let wet = readDelaySample(buffer: buffer, writeIndex: writeIndex, delaySamples: delaySamples, channel: channel)
                    let mix = Float(mixValue)
                    processedAudio[channel][frame] = dry * (1 - mix) + wet * mix
                    buffer[channel][writeIndex] = dry + wet * Float(feedbackValue)
                }
                writeIndex = (writeIndex + 1) % bufferLength
                phase += rateValue * 2.0 * .pi / sampleRate
                if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
            }

            if let id = targetId {
                flangerBuffersByNode[id] = buffer
                flangerWriteIndexByNode[id] = writeIndex
                flangerPhaseByNode[id] = phase
            } else {
                flangerBuffer = buffer
                flangerWriteIndex = writeIndex
                flangerPhase = phase
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .bitcrusher:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.bitcrusherEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let bitDepthValue = Int(nodeParams(for: nodeId, snapshot: snapshot)?.bitcrusherBitDepth ?? snapshot.bitcrusherBitDepth)
            let downsampleValue = Int(nodeParams(for: nodeId, snapshot: snapshot)?.bitcrusherDownsample ?? snapshot.bitcrusherDownsample)
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.bitcrusherMix ?? snapshot.bitcrusherMix
            guard mixValue > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
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
                for channel in 0..<channelCount {
                    if counters[channel] == 0 {
                        holds[channel] = processedAudio[channel][frame]
                        counters[channel] = ds - 1
                    } else {
                        counters[channel] -= 1
                    }
                    let crushed = quantizeSample(holds[channel], bitDepth: bitDepthValue)
                    let dry = processedAudio[channel][frame]
                    processedAudio[channel][frame] = dry * (1 - mix) + crushed * mix
                }
            }

            if let id = targetId {
                bitcrusherHoldCountersByNode[id] = counters
                bitcrusherHoldValuesByNode[id] = holds
            } else {
                bitcrusherHoldCounters = counters
                bitcrusherHoldValues = holds
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .tapeSaturation:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.tapeSaturationEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let driveValue = nodeParams(for: nodeId, snapshot: snapshot)?.tapeSaturationDrive ?? snapshot.tapeSaturationDrive
            let mixValue = nodeParams(for: nodeId, snapshot: snapshot)?.tapeSaturationMix ?? snapshot.tapeSaturationMix
            guard mixValue > 0 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let drive = Float(1 + driveValue * 4)
            let mix = Float(mixValue)
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    let dry = processedAudio[channel][frame]
                    let wet = tanhf(dry * drive) / tanhf(drive)
                    processedAudio[channel][frame] = dry * (1 - mix) + wet * mix
                }
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .stereoWidth:
            if let id = nodeId, !nodeIsEnabled(id, snapshot: snapshot) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? snapshot.stereoWidthEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let amount = nodeParams(for: nodeId, snapshot: snapshot)?.stereoWidthAmount ?? snapshot.stereoWidthAmount
            guard amount > 0, channelCount == 2 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            for frame in 0..<frameLength {
                let left = processedAudio[0][frame]
                let right = processedAudio[1][frame]
                let mid = (left + right) * 0.5
                let side = (left - right) * 0.5
                let width = Float(amount)
                let wideSide = side * (1.0 + width)
                processedAudio[0][frame] = mid + wideSide
                processedAudio[1][frame] = mid - wideSide
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
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
        var sumSquares: Float = 0
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                let sample = processedAudio[channel][frame]
                sumSquares += sample * sample
            }
        }
        let mean = sumSquares / Float(frameLength * channelCount)
        return sqrt(mean)
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

    func applyPendingResetsUnlocked() {
        guard pendingResets != [] else { return }

        let resets = pendingResets
        pendingResets = []

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
}
