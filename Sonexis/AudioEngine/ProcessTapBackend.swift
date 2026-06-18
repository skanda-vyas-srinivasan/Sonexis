import Foundation
import AVFoundation

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
        processTapEngine != nil ? "Process Tap" : "Routed to BlackHole"
    }

    var startHelpText: String {
        ProcessTapBackendFlag.isEnabled
            ? "Start Processing (Process Tap)"
            : "Start Processing (Auto-routes to BlackHole)"
    }

    func startProcessTapBackend() {
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
            inputDeviceName = "System Audio"
            outputDeviceName = "Default Output"
            errorMessage = nil
            isRunning = true
            signalFlowToken += 1
            scheduleSnapshotUpdate()
        } catch {
            processTapEngine = nil
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

        processTapEngine = nil
        engine.stop(reason: reason) { [weak self] in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.scheduleSnapshotUpdate()
                completion?()
            }
        }
    }

    func stopProcessTapBackendImmediately(reason: String = "Sonexis terminate") {
        guard let engine = processTapEngine else { return }

        processTapEngine = nil
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
            output.update(from: input, count: frameCount * channelCount)
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                channelData[channel][frame] = input[(frame * channelCount) + channel]
            }
        }

        let sampleCount = frameCount * channelCount
        let processed = interleavedData(from: buffer)
        processed.withUnsafeBufferPointer { processedBuffer in
            guard let processedBase = processedBuffer.baseAddress else {
                output.update(from: input, count: sampleCount)
                return
            }

            let copiedSamples = min(processed.count, sampleCount)
            output.update(from: processedBase, count: copiedSamples)
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
}
