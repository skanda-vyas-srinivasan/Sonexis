import AVFoundation
import Combine
import CoreAudio
import AudioToolbox

class AudioEngine: ObservableObject {
    private let engine = AVAudioEngine()
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var inputDeviceName: String = "Searching..."
    @Published var outputDeviceName: String = "Searching..."

    private var outputQueue: AudioQueueRef?
    private var outputDeviceID: AudioDeviceID?

    // Audio format: 48kHz, stereo, Float32 (matches what we're seeing in console)
    private let audioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 2,
        interleaved: false
    )!

    init() {
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Engine Control

    func start() {
        // First, request microphone permission
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
            print("✅ Microphone permission already granted")
            completion(true)
        case .notDetermined:
            print("🔐 Requesting microphone permission...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    print(granted ? "✅ Microphone permission granted" : "❌ Microphone permission denied")
                    completion(granted)
                }
            }
        case .denied, .restricted:
            print("❌ Microphone permission denied or restricted")
            completion(false)
        @unknown default:
            completion(false)
        }
        #endif
    }

    private func startAudioEngine() {
        do {
            // Configure audio devices FIRST
            try configureAudioDevices()

            guard let speakerDeviceID = outputDeviceID else {
                throw NSError(domain: "AudioEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "No output device configured"])
            }

            // Create AudioQueue for output to speakers
            let inputFormat = engine.inputNode.outputFormat(forBus: 0)

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
                    print("🔊 AudioQueue output set to: \(deviceUID)")
                } else {
                    print("⚠️ Warning: Could not set AudioQueue output device (error: \(setDeviceStatus))")
                }
            } else {
                print("⚠️ Warning: Could not get device UID for speakers")
            }

            // Ensure output volume is audible
            AudioQueueSetParameter(outputQueue, kAudioQueueParam_Volume, 1.0)

            // Allocate buffers for the queue (match tap buffer size to avoid truncation)
            let bufferFrameCount = max(UInt32(4096), UInt32(inputFormat.sampleRate / 10.0))
            let bufferSize: UInt32 = bufferFrameCount * UInt32(MemoryLayout<Float>.size) * UInt32(inputFormat.channelCount)
            for i in 0..<3 {
                var bufferRef: AudioQueueBufferRef?
                let allocStatus = AudioQueueAllocateBuffer(outputQueue, bufferSize, &bufferRef)
                if allocStatus != noErr {
                    print("⚠️ AudioQueue buffer alloc failed \(i): \(allocStatus)")
                }
                if let buffer = bufferRef {
                    // Prime with silence so the callback starts running.
                    memset(buffer.pointee.mAudioData, 0, Int(bufferSize))
                    buffer.pointee.mAudioDataByteSize = bufferSize
                    let enqueueStatus = AudioQueueEnqueueBuffer(outputQueue, buffer, 0, nil)
                    if enqueueStatus != noErr {
                        print("⚠️ AudioQueue enqueue failed \(i): \(enqueueStatus)")
                    }
                }
            }

            // Install tap to capture audio and send to AudioQueue
            var tapCallCount = 0
            engine.inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferFrameCount), format: inputFormat) { [weak self] buffer, time in
                guard let self = self, let queue = self.outputQueue else { return }

                // Get audio data from buffer
                guard let channelData = buffer.floatChannelData else { return }
                let frameLength = Int(buffer.frameLength)
                let channelCount = Int(buffer.format.channelCount)

                tapCallCount += 1
                if tapCallCount % 50 == 0 {
                    print("🎤 Tap called \(tapCallCount) times, frames: \(frameLength)")
                }

                // Interleave the audio for AudioQueue (it expects interleaved format)
                var interleavedData = [Float](repeating: 0, count: frameLength * channelCount)

                for frame in 0..<frameLength {
                    for channel in 0..<channelCount {
                        interleavedData[frame * channelCount + channel] = channelData[channel][frame]
                    }
                }

                // Write to AudioQueue buffer
                self.enqueueAudioData(interleavedData, queue: queue)
            }

            // Start the AudioQueue
            let startStatus = AudioQueueStart(outputQueue, nil)
            if startStatus != noErr {
                print("⚠️ AudioQueue start failed: \(startStatus)")
            }

            // Start the AVAudioEngine (for input only)
            engine.prepare()
            try engine.start()

            isRunning = true
            errorMessage = nil
            print("✅ Audio engine started successfully")
            print("   Input: AVAudioEngine (\(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch)")
            print("   Output: AudioQueue → Speakers")
        } catch {
            errorMessage = "Failed to start: \(error.localizedDescription)"
            isRunning = false
            print("❌ Audio engine failed to start: \(error)")
        }
    }

    // Ring buffer for audio data
    private var audioRingBuffer: [[Float]] = []
    private let ringBufferLock = NSLock()
    private let maxRingBufferSize = 10

    private func enqueueAudioData(_ data: [Float], queue: AudioQueueRef) {
        ringBufferLock.lock()
        audioRingBuffer.append(data)

        // Keep buffer from growing too large
        if audioRingBuffer.count > maxRingBufferSize {
            audioRingBuffer.removeFirst()
        }
        ringBufferLock.unlock()
    }

    fileprivate func getAudioDataForOutput() -> [Float]? {
        ringBufferLock.lock()
        defer { ringBufferLock.unlock() }

        if audioRingBuffer.isEmpty {
            return nil
        }
        return audioRingBuffer.removeFirst()
    }

    // MARK: - Device Configuration

    private func configureAudioDevices() throws {
        // Debug: List all available devices
        let allDevices = getAllAudioDevices()
        print("🔍 Available audio devices:")
        for device in allDevices {
            print("   - \(device.name) (ID: \(device.id)) [Input: \(device.hasInput), Output: \(device.hasOutput)]")
        }

        // Find BlackHole for input - we'll use system default which should be Multi-Output→BlackHole
        if let blackholeDevice = findDevice(matching: "BlackHole") {
            inputDeviceName = blackholeDevice.name
            print("📥 Will use BlackHole for input: \(blackholeDevice.name)")
            do {
                try engine.inputNode.auAudioUnit.setDeviceID(blackholeDevice.id)
                print("🎛️ Input device set to: \(blackholeDevice.name)")
            } catch {
                throw NSError(
                    domain: "AudioEngine",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to set input device: \(error.localizedDescription)"]
                )
            }
        } else {
            let inputDevices = allDevices.filter { $0.hasInput }
            print("❌ BlackHole not found. Available input devices:")
            for device in inputDevices {
                print("   - \(device.name)")
            }
            throw NSError(
                domain: "AudioEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "BlackHole not found. Please install BlackHole 2ch."]
            )
        }

        // Find real speakers for output (not BlackHole, not Multi-Output)
        guard let speakersDevice = findRealOutputDevice() else {
            throw NSError(
                domain: "AudioEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No output device found. Please connect speakers or headphones."]
            )
        }

        outputDeviceName = speakersDevice.name
        outputDeviceID = speakersDevice.id
        print("📤 Will output to: \(speakersDevice.name) (ID: \(speakersDevice.id))")

        // DON'T change system defaults - we'll handle device routing in the audio pipeline
    }

    private func findDevice(matching name: String) -> AudioDevice? {
        let devices = getAllAudioDevices()
        return devices.first { $0.name.contains(name) }
    }

    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return nil }

        var uid: CFString = "" as CFString
        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uid
        )

        guard status == noErr else { return nil }
        return uid as String
    }

    private func findRealOutputDevice() -> AudioDevice? {
        let devices = getAllAudioDevices()

        // Filter to output devices only
        let outputDevices = devices.filter { $0.hasOutput }

        // Exclude virtual devices (BlackHole, Multi-Output, Aggregate)
        let realDevices = outputDevices.filter { device in
            !device.name.contains("BlackHole") &&
            !device.name.contains("Multi-Output") &&
            !device.name.contains("Aggregate")
        }

        // Prefer built-in devices (MacBook speakers, headphone jack)
        if let builtIn = realDevices.first(where: { $0.name.contains("Built-in") || $0.name.contains("MacBook") }) {
            return builtIn
        }

        // Otherwise return first real device
        return realDevices.first
    }

    private func getAllAudioDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            AudioDevice(id: deviceID)
        }
    }

    func stop() {
        // Stop AudioQueue first
        if let queue = outputQueue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
            outputQueue = nil
        }

        // Clear ring buffer
        ringBufferLock.lock()
        audioRingBuffer.removeAll()
        ringBufferLock.unlock()

        // Stop AVAudioEngine
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        print("⏸️ Audio engine stopped")
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    @objc private func handleConfigurationChange(notification: Notification) {
        print("⚙️ Audio engine configuration changed")

        // If engine was running, attempt to restart
        if isRunning {
            stop()

            // Small delay to let hardware settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.start()
            }
        }
    }
}

// MARK: - Audio Device Helper

struct AudioDevice {
    let id: AudioDeviceID
    let name: String
    let hasInput: Bool
    let hasOutput: Bool

    init?(id: AudioDeviceID) {
        self.id = id
        self.name = AudioDevice.getDeviceName(id: id) ?? "Unknown Device"
        self.hasInput = AudioDevice.deviceHasStreams(id: id, scope: kAudioDevicePropertyScopeInput)
        self.hasOutput = AudioDevice.deviceHasStreams(id: id, scope: kAudioDevicePropertyScopeOutput)
    }

    private static func getDeviceName(id: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0

        // First get the size
        var status = AudioObjectGetPropertyDataSize(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            return nil
        }

        // Now get the actual data
        var name: CFString = "" as CFString
        status = AudioObjectGetPropertyData(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr else {
            return nil
        }

        return name as String
    }

    private static func deviceHasStreams(id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }
}

// MARK: - AUAudioUnit Extension for Device Selection

extension AUAudioUnit {
    func setDeviceID(_ deviceID: AudioDeviceID) throws {
        let deviceIDValue = deviceID as NSNumber
        setValue(deviceIDValue, forKey: "deviceID")
    }
}

// MARK: - AudioQueue Callback

private func audioQueueOutputCallback(
    inUserData: UnsafeMutableRawPointer?,
    inAQ: AudioQueueRef,
    inBuffer: AudioQueueBufferRef
) {
    guard let userData = inUserData else { return }

    let audioEngine = Unmanaged<AudioEngine>.fromOpaque(userData).takeUnretainedValue()
    struct DebugCounter {
        static var callbackCount = 0
        static var emptyCount = 0
    }
    DebugCounter.callbackCount += 1

    // Get audio data from ring buffer
    if let audioData = audioEngine.getAudioDataForOutput() {
        let byteCount = audioData.count * MemoryLayout<Float>.size
        let bufferSize = Int(inBuffer.pointee.mAudioDataBytesCapacity)

        if byteCount <= bufferSize {
            // Copy audio data to buffer
            audioData.withUnsafeBytes { rawBufferPointer in
                if let baseAddress = rawBufferPointer.baseAddress {
                    inBuffer.pointee.mAudioData.copyMemory(from: baseAddress, byteCount: byteCount)
                }
            }
            inBuffer.pointee.mAudioDataByteSize = UInt32(byteCount)
            if DebugCounter.callbackCount % 50 == 0 {
                print("🔈 AudioQueue callback \(DebugCounter.callbackCount), bytes: \(byteCount)/\(bufferSize)")
            }
        } else {
            // Buffer too small, fill with silence
            inBuffer.pointee.mAudioDataByteSize = 0
        }
    } else {
        // No audio data available, output silence
        inBuffer.pointee.mAudioDataByteSize = 0
        DebugCounter.emptyCount += 1
        if DebugCounter.emptyCount % 50 == 0 {
            print("🔇 AudioQueue empty buffer x\(DebugCounter.emptyCount)")
        }
    }

    // Re-enqueue the buffer
    AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
}
