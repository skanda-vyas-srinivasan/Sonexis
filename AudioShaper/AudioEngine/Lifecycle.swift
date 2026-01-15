import AVFoundation
import AudioToolbox
import Foundation

extension AudioEngine {

    // MARK: - Engine Control

    func start() {
        // Automatically set system input and output to BlackHole
        if !switchSystemAudioToBlackHole() {
            errorMessage = "BlackHole 2ch not found. Please install BlackHole 2ch to continue."
            isRunning = false
            return
        }

        // Verify setup after switching
        if !refreshSetupStatus() {
            errorMessage = "Failed to set System Input/Output to BlackHole 2ch."
            isRunning = false
            return
        }

        requestMicrophonePermission { [weak self] granted in
            guard let self = self else { return }

            if granted {
                self.startAudioEngine()
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Microphone permission denied. Please enable in System Settings > Privacy & Security > Microphone"
                    self.isRunning = false
                }
            }
        }
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        #if os(macOS)
        let audioSession = AVCaptureDevice.authorizationStatus(for: .audio)

        switch audioSession {
        case .authorized:
            // Debug output removed.
            completion(true)
        case .notDetermined:
            // Debug output removed.
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    // Debug output removed.
                    completion(granted)
                }
            }
        case .denied, .restricted:
            // Debug output removed.
            completion(false)
        @unknown default:
            completion(false)
        }
        #endif
    }

    private func startAudioEngine() {
        do {
            isReconfiguring = true
            // Configure audio devices FIRST
            refreshOutputDevices()
            try configureAudioDevices()

            guard let speakerDeviceID = outputDeviceID else {
                throw NSError(domain: "AudioEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "No output device configured"])
            }

            // Read current device volume and update slider to reflect it
            outputVolume = getOutputDeviceVolume(deviceID: speakerDeviceID)

            // Create AudioQueue for output to speakers
            let inputFormat = engine.inputNode.inputFormat(forBus: 0)

            // Use fixed sample rate (no more nightcore rate changes)
            var audioFormat = AudioStreamBasicDescription(
                mSampleRate: inputFormat.sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: UInt32(MemoryLayout<Float>.size * Int(inputFormat.channelCount)),
                mFramesPerPacket: 1,
                mBytesPerFrame: UInt32(MemoryLayout<Float>.size * Int(inputFormat.channelCount)),
                mChannelsPerFrame: UInt32(inputFormat.channelCount),
                mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
                mReserved: 0
            )

            // Create output queue
            var queue: AudioQueueRef?
            let status = AudioQueueNewOutput(
                &audioFormat,
                audioQueueOutputCallback,
                Unmanaged.passUnretained(self).toOpaque(),
                nil,
                nil,
                0,
                &queue
            )

            guard status == noErr, let outputQueue = queue else {
                throw NSError(domain: "AudioEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create AudioQueue: \(status)"])
            }

            self.outputQueue = outputQueue
            outputQueueStartLock.lock()
            outputQueueStarted = false
            outputQueueStartLock.unlock()

            // Set the output device to speakers explicitly using device UID
            if let deviceUID = getDeviceUID(deviceID: speakerDeviceID) {
                var uidCFString = deviceUID as CFString
                let setDeviceStatus = AudioQueueSetProperty(
                    outputQueue,
                    kAudioQueueProperty_CurrentDevice,
                    &uidCFString,
                    UInt32(MemoryLayout<CFString>.size)
                )

                if setDeviceStatus == noErr {
                    // Debug output removed.
                } else {
                    // Debug output removed.
                }
            } else {
                // Debug output removed.
            }

            // Ensure output volume is audible
            AudioQueueSetParameter(outputQueue, kAudioQueueParam_Volume, outputVolume)

            // Allocate buffers for the queue (match tap buffer size to avoid truncation)
            let bufferFrameCount = max(UInt32(4096), UInt32(inputFormat.sampleRate / 10.0))
            let frameLength = Int(bufferFrameCount)
            let channelCount = Int(inputFormat.channelCount)
            initializeRingBuffer(frameSize: frameLength * channelCount, capacity: maxRingBufferSize)
            ensureInterleavedCapacity(frameLength: frameLength, channelCount: channelCount)
            ensureProcessingCapacity(frameLength: frameLength, channelCount: channelCount)

            let bufferSize: UInt32 = bufferFrameCount * UInt32(MemoryLayout<Float>.size) * UInt32(inputFormat.channelCount)
            for i in 0..<3 {
                var bufferRef: AudioQueueBufferRef?
                let allocStatus = AudioQueueAllocateBuffer(outputQueue, bufferSize, &bufferRef)
                if allocStatus != noErr {
                    // Debug output removed.
                }
                if let buffer = bufferRef {
                    // Prime with silence so the callback starts running.
                    memset(buffer.pointee.mAudioData, 0, Int(bufferSize))
                    buffer.pointee.mAudioDataByteSize = bufferSize
                    let enqueueStatus = AudioQueueEnqueueBuffer(outputQueue, buffer, 0, nil)
                    if enqueueStatus != noErr {
                        // Debug output removed.
                    }
                }
            }

            // Wire input -> timePitch -> mixer (mute mixer to avoid double output)
            engine.inputNode.removeTap(onBus: 0)
            engine.inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferFrameCount), format: inputFormat) { [weak self] buffer, time in
                guard let self = self, let queue = self.outputQueue else { return }

                let interleavedData = self.interleavedData(from: buffer)

                // Write to AudioQueue buffer
                self.enqueueAudioData(interleavedData, queue: queue)

                self.ensureOutputQueueStarted(queue)
            }

            // Start the AVAudioEngine (for input only)
            engine.prepare()
            try engine.start()

            isRunning = true
            errorMessage = nil
            DispatchQueue.main.async {
                self.signalFlowToken += 1
            }
            startSetupMonitor()
            // Debug output removed.
            startChainLogTimer()
            isReconfiguring = false
        } catch {
            errorMessage = "Failed to start: \(error.localizedDescription)"
            isRunning = false
            isReconfiguring = false
            // Debug output removed.
        }
    }

    private func ensureOutputQueueStarted(_ queue: AudioQueueRef) {
        outputQueueStartLock.lock()
        let shouldStart = !outputQueueStarted
        if shouldStart {
            outputQueueStarted = true
        }
        outputQueueStartLock.unlock()

        guard shouldStart else { return }

        DispatchQueue.main.async { [weak self] in
            let startStatus = AudioQueueStart(queue, nil)
            if startStatus != noErr {
                self?.outputQueueStartLock.lock()
                self?.outputQueueStarted = false
                self?.outputQueueStartLock.unlock()
                // Debug output removed.
            } else {
                // Debug output removed.
            }
        }
    }

    private func startChainLogTimer() {
        chainLogTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.logActiveChain()
        }
        timer.resume()
        chainLogTimer = timer
    }

    private func stopChainLogTimer() {
        chainLogTimer?.cancel()
        chainLogTimer = nil
    }

    private func logActiveChain() {
        if useSplitGraph {
            var leftConnections: [BeginnerConnection] = []
            var rightConnections: [BeginnerConnection] = []
            var leftNodes: [BeginnerNode] = []
            var rightNodes: [BeginnerNode] = []
            let leftStartID = splitLeftStartID
            let leftEndID = splitLeftEndID
            let rightStartID = splitRightStartID
            let rightEndID = splitRightEndID
            withEffectStateLock {
                leftConnections = splitLeftConnections
                rightConnections = splitRightConnections
                leftNodes = splitLeftNodes
                rightNodes = splitRightNodes
            }

            let leftEdges = edgesDescription(
                connections: leftConnections,
                nodes: leftNodes,
                startID: leftStartID,
                endID: leftEndID,
                startLabel: "Start L",
                endLabel: "End L"
            )
            let rightEdges = edgesDescription(
                connections: rightConnections,
                nodes: rightNodes,
                startID: rightStartID,
                endID: rightEndID,
                startLabel: "Start R",
                endLabel: "End R"
            )

            if leftEdges.isEmpty && rightEdges.isEmpty {
                // Debug output removed.
                return
            }
            let leftText = leftEdges.isEmpty ? "Left: (empty)" : "Left: \(leftEdges.joined(separator: " | "))"
            let rightText = rightEdges.isEmpty ? "Right: (empty)" : "Right: \(rightEdges.joined(separator: " | "))"
            // Debug output removed.
            return
        }

        if useManualGraph {
            var connections: [BeginnerConnection] = []
            var nodes: [BeginnerNode] = []
            let startID = manualGraphStartID
            let endID = manualGraphEndID
            withEffectStateLock {
                connections = manualGraphConnections
                nodes = manualGraphNodes
            }

            if connections.isEmpty || startID == nil || endID == nil {
                // Debug output removed.
                return
            }

            let edges = edgesDescription(
                connections: connections,
                nodes: nodes,
                startID: startID,
                endID: endID,
                startLabel: "Start",
                endLabel: "End"
            )
            // Debug output removed.
            return
        }

        var chain: [BeginnerNode] = []
        withEffectStateLock {
            chain = effectChainOrder
        }

        if chain.isEmpty {
            // Debug output removed.
            return
        }

        let names = chain.map { $0.type.rawValue }.joined(separator: " → ")
        // Debug output removed.
    }

    private func edgesDescription(
        connections: [BeginnerConnection],
        nodes: [BeginnerNode],
        startID: UUID?,
        endID: UUID?,
        startLabel: String,
        endLabel: String
    ) -> [String] {
        guard let startID, let endID else { return [] }
        return connections.map { connection -> String in
            let fromName: String
            if connection.fromNodeId == startID {
                fromName = startLabel
            } else {
                fromName = nodes.first(where: { $0.id == connection.fromNodeId })?.type.rawValue ?? "?"
            }

            let toName: String
            if connection.toNodeId == endID {
                toName = endLabel
            } else {
                toName = nodes.first(where: { $0.id == connection.toNodeId })?.type.rawValue ?? "?"
            }

            return "\(fromName)→\(toName)"
        }
    }

    // MARK: - Device Configuration

    private func configureAudioDevices() throws {
        // Debug: List all available devices
        let allDevices = getAllAudioDevices()
        // Debug output removed.
        for device in allDevices {
            // Debug output removed.
        }

        // Find BlackHole for input - we'll use system default which should be Multi-Output→BlackHole
        if let blackholeDevice = findDevice(matching: "BlackHole") {
            inputDeviceName = blackholeDevice.name
            // Debug output removed.
            do {
                try engine.inputNode.auAudioUnit.setDeviceID(blackholeDevice.id)
                // Debug output removed.
            } catch {
                throw NSError(
                    domain: "AudioEngine",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to set input device: \(error.localizedDescription)"]
                )
            }
        } else {
            let inputDevices = allDevices.filter { $0.hasInput }
            // Debug output removed.
            for device in inputDevices {
                // Debug output removed.
            }
            throw NSError(
                domain: "AudioEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "BlackHole not found. Please install BlackHole 2ch."]
            )
        }

        // Use user-selected output device when available
        let selectedDevice = outputDevices.first { $0.id == selectedOutputDeviceID }
        let outputDevice = selectedDevice ?? findRealOutputDevice()

        // Find real speakers for output (not BlackHole, not Multi-Output)
        guard let speakersDevice = outputDevice else {
            throw NSError(
                domain: "AudioEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No output device found. Please connect speakers or headphones."]
            )
        }

        outputDeviceName = speakersDevice.name
        outputDeviceID = speakersDevice.id
        // Debug output removed.

        // DON'T change system defaults - we'll handle device routing in the audio pipeline
    }

    func stop() {
        stopInternal(setReconfiguringFlag: false)

        // Restore original audio devices when stopping
        restoreOriginalAudioDevices()
    }

    private func stopInternal(setReconfiguringFlag: Bool) {
        nightcoreRestartWorkItem?.cancel()
        nightcoreRestartWorkItem = nil
        resetEffectState()

        if setReconfiguringFlag {
            isReconfiguring = true
        }

        // Stop AudioQueue first
        if let queue = outputQueue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
            outputQueue = nil
        }
        outputQueueStartLock.lock()
        outputQueueStarted = false
        outputQueueStartLock.unlock()
        stopChainLogTimer()

        // Clear ring buffer
        ringBufferLock.lock()
        if let buffer = ringBuffer {
            buffer.deallocate()
        }
        ringBuffer = nil
        ringBufferFrameSize = 0
        ringBufferCapacity = 0
        ringWriteIndex = 0
        ringReadIndex = 0
        ringBufferLock.unlock()

        // Stop AVAudioEngine
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        stopSetupMonitor()
        isRunning = false
        if !setReconfiguringFlag {
            isReconfiguring = false
        }
        // Debug output removed.
    }

    func reconfigureAudio() {
        scheduleRestart(reason: "output device change")
    }

    private func scheduleRestart(reason: String) {
        if isReconfiguring {
            return
        }
        isReconfiguring = true
        restartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.stopInternal(setReconfiguringFlag: true)
            self.requestMicrophonePermission { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.startAudioEngine()
                } else {
                    self.errorMessage = "Microphone permission denied. Please enable in System Settings > Privacy & Security > Microphone"
                    self.isRunning = false
                    self.isReconfiguring = false
                }
            }
        }
        restartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDebounceInterval, execute: workItem)
        // Debug output removed.
    }

    // MARK: - Notifications

    func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    @objc private func handleConfigurationChange(notification: Notification) {
        // Debug output removed.

        // If engine was running, attempt to restart
        if isRunning {
            scheduleRestart(reason: "engine configuration change")
        }
    }
}
