import Foundation
import AVFoundation

enum SystemAudioBackend: String, CaseIterable, Identifiable {
    case processTap
    case blackHole

    static let userDefaultsKey = "SonexisSelectedAudioBackend"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .processTap:
            return "Process Tap"
        case .blackHole:
            return "BlackHole"
        }
    }

    var startHelpText: String {
        switch self {
        case .processTap:
            return "Start Processing (Process Tap)"
        case .blackHole:
            return "Start Processing (Auto-routes to BlackHole)"
        }
    }

    static func initialSelection() -> SystemAudioBackend {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SONEXIS_PROCESS_TAP_SMOKE"] == "1" ||
            ProcessInfo.processInfo.environment["SONEXIS_USE_PROCESS_TAP"] == "1" {
            return .processTap
        }
        if ProcessInfo.processInfo.environment["SONEXIS_USE_BLACKHOLE"] == "1" {
            return .blackHole
        }
        if let stored = UserDefaults.standard.string(forKey: userDefaultsKey),
           let backend = SystemAudioBackend(rawValue: stored) {
            return backend
        }
        #endif

        return ProcessTapBackendFlag.defaultBackend
    }
}

enum ProcessTapBackendFlag {
    static var defaultBackend: SystemAudioBackend {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SONEXIS_USE_BLACKHOLE"] == "1" {
            return .blackHole
        }
        return .processTap
        #else
        if ProcessInfo.processInfo.environment["SONEXIS_USE_PROCESS_TAP"] == "1" {
            return .processTap
        }

        return UserDefaults.standard.bool(forKey: "SonexisUseProcessTapEngine")
            ? .processTap
            : .blackHole
        #endif
    }

    static var isEnabled: Bool {
        defaultBackend == .processTap
    }
}

extension AudioEngine {
    var isProcessTapBackendEnabled: Bool {
        selectedAudioBackend == .processTap
    }

    var setupReadyForCurrentBackend: Bool {
        if isProcessTapBackendEnabled {
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
        selectedAudioBackend.startHelpText
    }

    func selectAudioBackend(_ backend: SystemAudioBackend) {
        guard selectedAudioBackend != backend else { return }

        let shouldRestart = isRunning || processTapEngine != nil || processTapStopInProgress
        selectedAudioBackend = backend
        UserDefaults.standard.set(backend.rawValue, forKey: SystemAudioBackend.userDefaultsKey)
        errorMessage = nil
        scheduleSnapshotUpdate()

        guard shouldRestart else { return }

        if processTapEngine != nil {
            stopProcessTapBackend(reason: "Switching backend to \(backend.displayName)") { [weak self] in
                guard let self, self.selectedAudioBackend == backend else { return }
                self.start()
            }
        } else {
            stop()
            if selectedAudioBackend == backend {
                start()
            }
        }
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
