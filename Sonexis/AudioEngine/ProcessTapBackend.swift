import Foundation
import AVFoundation

private enum ProcessTapGainStage {
    static let inputTrimGain: Float = 0.70794576 // -3 dB
    static let softLimitThreshold: Float = 0.90
    static let outputCeiling: Float = 0.98
}

enum ProcessTapBackendFlag {
    static var isEnabled: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SONEXIS_USE_BLACKHOLE"] == "1" {
            return false
        }
        return true
        #else
        if ProcessInfo.processInfo.environment["SONEXIS_USE_PROCESS_TAP"] == "1" {
            return true
        }

        return UserDefaults.standard.bool(forKey: "SonexisUseProcessTapEngine")
        #endif
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

        do {
            try engine.start()
            processTapStopInProgress = false
            inputDeviceName = "System Audio"
            outputDeviceName = "Default Output"
            errorMessage = nil
            isRunning = true
            print("Process Tap gain staging: input trim -3 dB, output ceiling -0.2 dBFS.")
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
        scheduleSnapshotUpdate()
    }
}

extension AudioEngine: ProcessTapAudioProcessor {
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
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                let sampleIndex = (frame * channelCount) + channel
                channelData[channel][frame] = input[sampleIndex] * ProcessTapGainStage.inputTrimGain
            }
        }

        let sampleCount = frameCount * channelCount
        let processed = interleavedData(from: buffer)
        processed.withUnsafeBufferPointer { processedBuffer in
            guard let processedBase = processedBuffer.baseAddress else {
                copyProcessTapBypass(input: input, output: output, sampleCount: sampleCount)
                return
            }

            let copiedSamples = min(processed.count, sampleCount)
            for sampleIndex in 0..<copiedSamples {
                output[sampleIndex] = protectProcessTapOutputSample(processedBase[sampleIndex])
            }
            if copiedSamples < sampleCount {
                for sampleIndex in copiedSamples..<sampleCount {
                    output[sampleIndex] = 0.0
                }
            }
        }
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
        for sampleIndex in 0..<sampleCount {
            let trimmed = input[sampleIndex] * ProcessTapGainStage.inputTrimGain
            output[sampleIndex] = protectProcessTapOutputSample(trimmed)
        }
    }

    private func protectProcessTapOutputSample(_ sample: Float) -> Float {
        guard sample.isFinite else { return 0 }

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
