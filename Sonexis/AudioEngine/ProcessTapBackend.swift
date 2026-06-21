import Foundation
import AVFoundation

private enum ProcessTapGainStage {
    // Process Taps see the system mix before the user's output-device volume.
    // Keep the default conservative; optional makeup happens after the DSP graph.
    static let softLimitThreshold: Float = 0.86
    static let outputCeiling: Float = 0.95
}

enum ProcessTapBackendFlag {
    static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["SONEXIS_USE_BLACKHOLE"] == "1" {
            return false
        }

        return true
    }
}

extension AudioEngine {
    var isProcessTapBackendEnabled: Bool {
        ProcessTapBackendFlag.isEnabled
    }

    var setupReadyForCurrentBackend: Bool {
        if ProcessTapBackendFlag.isEnabled {
            return true
        }

        return outputDevices.contains { $0.name.localizedCaseInsensitiveContains("BlackHole") }
    }

    var activeRouteLabel: String {
        processTapEngine != nil
            ? (processTapStopInProgress ? "Stopping Process Tap" : "Process Tap")
            : "Routed to BlackHole"
    }

    var startHelpText: String {
        ProcessTapBackendFlag.isEnabled
            ? "Start Processing (Process Tap)"
            : "Start Processing (Auto-routes to BlackHole)"
    }

    func startProcessTapBackend() {
        guard processTapEngine == nil, !processTapStopInProgress else {
            return
        }

        guard #available(macOS 14.4, *) else {
            errorMessage = "Process Tap system audio requires macOS 14.4 or newer."
            isRunning = false
            return
        }

        let engine = ProcessTapDSPEngine(
            configuration: .productBaseline,
            audioProcessor: self
        )
        processTapEngine = engine
        resetOutputMeter()
        resetProcessTapInputMeter()

        do {
            try engine.start()
            processTapStopInProgress = false
            inputDeviceName = "System Audio"
            outputDeviceName = "Default Output"
            errorMessage = nil
            isRunning = true
            let ceilingDescription = processTapOutputCeilingEnabled ? "-0.45 dBFS" : "disabled"
            print("Process Tap gain staging: DSP input \(String(format: "%.1f", processTapInputTrimDB)) dB, output makeup \(String(format: "%.1f", processTapOutputMakeupDB)) dB, output ceiling \(ceilingDescription).")
            signalFlowToken += 1
            scheduleSnapshotUpdate()
        } catch {
            processTapEngine = nil
            processTapStopInProgress = false
            errorMessage = "Failed to start Process Tap engine: \(error)"
            isRunning = false
            scheduleSnapshotUpdate()
        }
    }

    func stopProcessTapBackend(
        reason: String = "Sonexis stop",
        completion: (() -> Void)? = nil
    ) {
        guard let engine = processTapEngine else {
            completion?()
            return
        }

        guard !processTapStopInProgress else {
            completion?()
            return
        }

        processTapStopInProgress = true
        scheduleSnapshotUpdate()
        engine.stop(reason: reason) { [weak self] in
            DispatchQueue.main.async {
                guard let self else {
                    completion?()
                    return
                }

                if self.processTapEngine === engine {
                    self.processTapEngine = nil
                }
                self.processTapStopInProgress = false
                self.isRunning = false
                self.resetOutputMeter()
                self.resetProcessTapInputMeter()
                self.scheduleSnapshotUpdate()
                completion?()
            }
        }
    }

    func stopProcessTapBackendImmediately(reason: String = "Sonexis terminate") {
        guard let engine = processTapEngine else { return }

        processTapEngine = nil
        processTapStopInProgress = false
        engine.stopImmediately(reason: reason)
        isRunning = false
        resetOutputMeter()
        resetProcessTapInputMeter()
        scheduleSnapshotUpdate()
    }
}

extension AudioEngine: ProcessTapAudioProcessor {
    private var processTapInputTrimGain: Float {
        let clampedDB = min(max(processTapInputTrimDB, -30), 0)
        return Float(pow(10.0, clampedDB / 20.0))
    }

    private var processTapOutputMakeupGain: Float {
        let clampedDB = min(max(processTapOutputMakeupDB, -12), 30)
        return Float(pow(10.0, clampedDB / 20.0))
    }

    func processSystemAudio(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Double
    ) {
        guard frameCount > 0, channelCount > 0 else { return }

        let buffer = processTapBuffer(
            frameCount: frameCount,
            channelCount: channelCount,
            sampleRate: sampleRate
        )
        guard let buffer,
              let channelData = buffer.floatChannelData else {
            copyProcessTapBypass(input: input, output: output, sampleCount: frameCount * channelCount)
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        let inputTrimGain = processTapInputTrimGain
        var rawInputPeak: Float = 0
        var trimmedInputPeak: Float = 0
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                let sampleIndex = (frame * channelCount) + channel
                let rawSample = input[sampleIndex]
                let trimmedSample = rawSample * inputTrimGain
                channelData[channel][frame] = trimmedSample
                rawInputPeak = max(rawInputPeak, abs(rawSample))
                trimmedInputPeak = max(trimmedInputPeak, abs(trimmedSample))
            }
        }
        publishProcessTapInputMeter(rawPeak: rawInputPeak, trimmedPeak: trimmedInputPeak)

        let sampleCount = frameCount * channelCount
        let processed = interleavedData(from: buffer)
        processed.withUnsafeBufferPointer { processedBuffer in
            guard let processedBase = processedBuffer.baseAddress else {
                copyProcessTapBypass(input: input, output: output, sampleCount: sampleCount)
                return
            }

            let copiedSamples = min(processed.count, sampleCount)
            let outputMakeupGain = processTapOutputMakeupGain
            var sumSquares: Float = 0
            var peak: Float = 0
            for sampleIndex in 0..<copiedSamples {
                let madeUp = processedBase[sampleIndex] * outputMakeupGain
                let finalSample = protectProcessTapOutputSample(madeUp)
                output[sampleIndex] = finalSample
                let magnitude = abs(finalSample)
                peak = max(peak, magnitude)
                sumSquares += finalSample * finalSample
            }
            if copiedSamples < sampleCount {
                for sampleIndex in copiedSamples..<sampleCount {
                    output[sampleIndex] = 0.0
                }
            }
            publishOutputMeter(sumSquares: sumSquares, peak: peak, sampleCount: sampleCount)
        }
    }

    func processTapAudioGapDetected(
        fillFrames: UInt32,
        droppedFrames: UInt64,
        underflowFrames: UInt64
    ) {
        let message = "Processing fell behind: fill \(fillFrames), dropped +\(droppedFrames), underflow +\(underflowFrames)"
        publishProcessTapWarning(message)
    }

    private func processTapBuffer(
        frameCount: Int,
        channelCount: Int,
        sampleRate: Double
    ) -> AVAudioPCMBuffer? {
        let needsNewBuffer = processTapPCMBuffer == nil
            || processTapPCMBufferFrameCapacity < frameCount
            || processTapPCMBufferChannelCount != channelCount
            || processTapPCMBufferSampleRate != sampleRate

        if needsNewBuffer {
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
            ) else {
                return nil
            }

            processTapPCMBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
            processTapPCMBufferFrameCapacity = frameCount
            processTapPCMBufferChannelCount = channelCount
            processTapPCMBufferSampleRate = sampleRate
        }

        return processTapPCMBuffer
    }

    private func copyProcessTapBypass(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        sampleCount: Int
    ) {
        guard sampleCount > 0 else { return }
        let inputTrimGain = processTapInputTrimGain
        var sumSquares: Float = 0
        var peak: Float = 0
        var rawInputPeak: Float = 0
        var trimmedInputPeak: Float = 0
        let outputMakeupGain = processTapOutputMakeupGain
        for sampleIndex in 0..<sampleCount {
            let rawSample = input[sampleIndex]
            let trimmedSample = rawSample * inputTrimGain
            let staged = input[sampleIndex]
                * inputTrimGain
                * outputMakeupGain
            let finalSample = protectProcessTapOutputSample(staged)
            output[sampleIndex] = finalSample
            let magnitude = abs(finalSample)
            peak = max(peak, magnitude)
            sumSquares += finalSample * finalSample
            rawInputPeak = max(rawInputPeak, abs(rawSample))
            trimmedInputPeak = max(trimmedInputPeak, abs(trimmedSample))
        }
        publishProcessTapInputMeter(rawPeak: rawInputPeak, trimmedPeak: trimmedInputPeak)
        publishOutputMeter(sumSquares: sumSquares, peak: peak, sampleCount: sampleCount)
    }

    private func protectProcessTapOutputSample(_ sample: Float) -> Float {
        guard sample.isFinite else { return 0 }
        guard processTapOutputCeilingEnabled else { return sample }

        let threshold = ProcessTapGainStage.softLimitThreshold
        let ceiling = ProcessTapGainStage.outputCeiling

        let magnitude = abs(sample)
        guard magnitude > threshold else {
            return sample
        }

        let sign: Float = sample >= 0 ? 1 : -1
        let over = magnitude - threshold
        let shaped = threshold + (1 - Float(exp(Double(-over * 8)))) * (ceiling - threshold)
        return sign * min(shaped, ceiling)
    }
}
