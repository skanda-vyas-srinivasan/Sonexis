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

    // Pitch Shift effect (Nightcore) - now uses AVAudioUnitTimePitch
    @Published var nightcoreEnabled = false {
        didSet {
            if !nightcoreEnabled && !clarityEnabled {
                resetClarityState()
            }
        }
    }
    @Published var nightcoreIntensity: Double = 0.6 // 0 to 1, maps to 0 to +12 semitones

    @Published var bassBoostEnabled = false {
        didSet {
            // Debug output removed.
            if !bassBoostEnabled {
                resetBassBoostState()
            }
        }
    }
    @Published var bassBoostAmount: Double = 0.6

    // Clarity effect
    @Published var clarityEnabled = false {
        didSet {
            if !clarityEnabled && !nightcoreEnabled {
                resetClarityState()
            }
        }
    }
    @Published var clarityAmount: Double = 0.5

    // Reverb effect
    @Published var reverbEnabled = false {
        didSet {
            if !reverbEnabled {
                resetReverbState()
            }
        }
    }
    @Published var reverbMix: Double = 0.3
    @Published var reverbSize: Double = 0.5

    // Compressor effect
    @Published var compressorEnabled = false {
        didSet {
            if !compressorEnabled {
                resetCompressorState()
            }
        }
    }
    @Published var compressorStrength: Double = 0.4

    // Stereo width effect
    @Published var stereoWidthEnabled = false
    @Published var stereoWidthAmount: Double = 0.3

    // Simple EQ effect
    @Published var simpleEQEnabled = false {
        didSet {
            if !simpleEQEnabled {
                resetEQState()
            }
        }
    }
    @Published var eqBass: Double = 0 // -1 to 1
    @Published var eqMids: Double = 0 // -1 to 1
    @Published var eqTreble: Double = 0 // -1 to 1

    // 10-Band EQ
    @Published var tenBandEQEnabled = false {
        didSet {
            if !tenBandEQEnabled {
                resetTenBandEQState()
            }
        }
    }
    @Published var tenBand31: Double = 0
    @Published var tenBand62: Double = 0
    @Published var tenBand125: Double = 0
    @Published var tenBand250: Double = 0
    @Published var tenBand500: Double = 0
    @Published var tenBand1k: Double = 0
    @Published var tenBand2k: Double = 0
    @Published var tenBand4k: Double = 0
    @Published var tenBand8k: Double = 0
    @Published var tenBand16k: Double = 0

    // De-mud effect
    @Published var deMudEnabled = false {
        didSet {
            if !deMudEnabled {
                resetDeMudState()
            }
        }
    }
    @Published var deMudStrength: Double = 0.5

    // Delay effect
    @Published var delayEnabled = false {
        didSet {
            if !delayEnabled {
                resetDelayState()
            }
        }
    }
    @Published var delayTime: Double = 0.25 // seconds (0.01 to 2.0)
    @Published var delayFeedback: Double = 0.4 // 0 to 1
    @Published var delayMix: Double = 0.3 // 0 to 1

    // Distortion effect
    @Published var distortionEnabled = false
    @Published var distortionDrive: Double = 0.5 // 0 to 1
    @Published var distortionMix: Double = 0.5 // 0 to 1

    // Tremolo effect
    @Published var tremoloEnabled = false {
        didSet {
            if !tremoloEnabled {
                tremoloPhase = 0
            }
        }
    }
    @Published var tremoloRate: Double = 5.0 // Hz (0.1 to 20)
    @Published var tremoloDepth: Double = 0.5 // 0 to 1

    // Chorus effect
    @Published var chorusEnabled = false {
        didSet {
            if !chorusEnabled {
                resetChorusState()
            }
        }
    }
    @Published var chorusRate: Double = 0.8
    @Published var chorusDepth: Double = 0.4
    @Published var chorusMix: Double = 0.35

    // Phaser effect
    @Published var phaserEnabled = false {
        didSet {
            if !phaserEnabled {
                resetPhaserState()
            }
        }
    }
    @Published var phaserRate: Double = 0.6
    @Published var phaserDepth: Double = 0.5

    // Flanger effect
    @Published var flangerEnabled = false {
        didSet {
            if !flangerEnabled {
                resetFlangerState()
            }
        }
    }
    @Published var flangerRate: Double = 0.6
    @Published var flangerDepth: Double = 0.4
    @Published var flangerFeedback: Double = 0.25
    @Published var flangerMix: Double = 0.4

    // Bitcrusher effect
    @Published var bitcrusherEnabled = false {
        didSet {
            if !bitcrusherEnabled {
                resetBitcrusherState()
            }
        }
    }
    @Published var bitcrusherBitDepth: Double = 8
    @Published var bitcrusherDownsample: Double = 4
    @Published var bitcrusherMix: Double = 0.6

    // Tape saturation effect
    @Published var tapeSaturationEnabled = false
    @Published var tapeSaturationDrive: Double = 0.35
    @Published var tapeSaturationMix: Double = 0.5

    // Resampling effect (pitch+speed)
    @Published var resampleEnabled = false
    @Published var resampleRate: Double = 1.0
    @Published var resampleCrossfade: Double = 0.3

    @Published var rubberBandPitchEnabled = false
    @Published var rubberBandPitchSemitones: Double = 0.0

    @Published var processingEnabled = true {
        didSet {
            if !processingEnabled {
                resetEffectState()
            }
        }
    }
    @Published var limiterEnabled = true

    @Published var effectLevels: [UUID: Float] = [:]

    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedOutputDeviceID: AudioDeviceID? {
        didSet {
            if let deviceID = selectedOutputDeviceID {
                setOutputDeviceVolume(deviceID: deviceID, volume: 1.0)
            }
            if isRunning {
                reconfigureAudio()
            }
        }
    }
    @Published var setupReady = true
    @Published var pendingGraphSnapshot: GraphSnapshot?

    private(set) var currentGraphSnapshot: GraphSnapshot?

    private var outputQueue: AudioQueueRef?
    private var outputDeviceID: AudioDeviceID?
    private var outputQueueStarted = false
    private let outputQueueStartLock = NSLock()
    private var chainLogTimer: DispatchSourceTimer?
    private var setupMonitorTimer: DispatchSourceTimer?
    private var nightcoreRestartWorkItem: DispatchWorkItem?
    private var effectChainOrder: [BeginnerNode] = []
    private var manualGraphNodes: [BeginnerNode] = []
    private var manualGraphConnections: [BeginnerConnection] = []
    private var manualGraphStartID: UUID?
    private var manualGraphEndID: UUID?
    private var useManualGraph = false
    private var splitLeftNodes: [BeginnerNode] = []
    private var splitLeftConnections: [BeginnerConnection] = []
    private var splitLeftStartID: UUID?
    private var splitLeftEndID: UUID?
    private var splitRightNodes: [BeginnerNode] = []
    private var splitRightConnections: [BeginnerConnection] = []
    private var splitRightStartID: UUID?
    private var splitRightEndID: UUID?
    private var useSplitGraph = false
    private var nodeParameters: [UUID: NodeEffectParameters] = [:]
    private var nodeEnabled: [UUID: Bool] = [:]
    private var levelUpdateCounter = 0
    private let effectStateLock = NSLock()
    private var isReconfiguring = false
    private var restartWorkItem: DispatchWorkItem?
    private let restartDebounceInterval: TimeInterval = 0.25

    // Bass boost state
    private var bassBoostState: [BiquadState] = []
    private var bassBoostCoefficients = BiquadCoefficients()
    private var bassBoostLastSampleRate: Double = 0
    private var bassBoostLastAmount: Double = -1
    private var bassBoostStatesByNode: [UUID: [BiquadState]] = [:]

    // Clarity state (high shelf boost)
    private var clarityState: [BiquadState] = []
    private var clarityCoefficients = BiquadCoefficients()
    private var clarityLastSampleRate: Double = 0
    private var clarityLastAmount: Double = -1
    private var clarityStatesByNode: [UUID: [BiquadState]] = [:]
    private var nightcoreStatesByNode: [UUID: [BiquadState]] = [:]

    // De-mud state (mid frequency cut)
    private var deMudState: [BiquadState] = []
    private var deMudCoefficients = BiquadCoefficients()
    private var deMudLastSampleRate: Double = 0
    private var deMudLastStrength: Double = -1
    private var deMudStatesByNode: [UUID: [BiquadState]] = [:]

    // Simple EQ state (3 bands)
    private var eqBassState: [BiquadState] = []
    private var eqBassCoefficients = BiquadCoefficients()
    private var eqMidsState: [BiquadState] = []
    private var eqMidsCoefficients = BiquadCoefficients()
    private var eqTrebleState: [BiquadState] = []
    private var eqTrebleCoefficients = BiquadCoefficients()
    private var eqLastSampleRate: Double = 0
    private var eqBassStatesByNode: [UUID: [BiquadState]] = [:]
    private var eqMidsStatesByNode: [UUID: [BiquadState]] = [:]
    private var eqTrebleStatesByNode: [UUID: [BiquadState]] = [:]

    // 10-band EQ state (peaking filters)
    private let tenBandFrequencies: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    private var tenBandStates: [[BiquadState]] = []
    private var tenBandCoefficients: [BiquadCoefficients] = []
    private var tenBandLastSampleRate: Double = 0
    private var tenBandLastGains: [Double] = []
    private var tenBandStatesByNode: [UUID: [[BiquadState]]] = [:]

    // Compressor state (simple dynamic range compression)
    private var compressorEnvelope: [Float] = []

    // Reverb buffer (simple delay-based reverb)
    private var reverbBuffer: [[Float]] = []
    private var reverbWriteIndex = 0
    private var reverbBuffersByNode: [UUID: [[Float]]] = [:]
    private var reverbWriteIndexByNode: [UUID: Int] = [:]

    // Delay buffer (circular buffer for echo)
    private var delayBuffer: [[Float]] = []
    private var delayWriteIndex = 0
    private var delayBuffersByNode: [UUID: [[Float]]] = [:]
    private var delayWriteIndexByNode: [UUID: Int] = [:]

    // Tremolo state (LFO phase)
    private var tremoloPhase: Double = 0
    private var tremoloPhaseByNode: [UUID: Double] = [:]

    // Chorus state (delay modulation)
    private var chorusBuffer: [[Float]] = []
    private var chorusWriteIndex = 0
    private var chorusPhase: Double = 0
    private var chorusBuffersByNode: [UUID: [[Float]]] = [:]
    private var chorusWriteIndexByNode: [UUID: Int] = [:]
    private var chorusPhaseByNode: [UUID: Double] = [:]

    // Flanger state (short delay modulation with feedback)
    private var flangerBuffer: [[Float]] = []
    private var flangerWriteIndex = 0
    private var flangerPhase: Double = 0
    private var flangerBuffersByNode: [UUID: [[Float]]] = [:]
    private var flangerWriteIndexByNode: [UUID: Int] = [:]
    private var flangerPhaseByNode: [UUID: Double] = [:]

    // Phaser state (all-pass)
    private let phaserStageCount = 2
    private var phaserStates: [[AllPassState]] = []
    private var phaserStatesByNode: [UUID: [[AllPassState]]] = [:]
    private var phaserPhase: Double = 0
    private var phaserPhaseByNode: [UUID: Double] = [:]

    // Resampling state
    private var resampleBuffer: [[Float]] = []
    private var resampleWriteIndex = 0
    private var resampleReadPhase: Double = 0
    private var resampleCrossfadeRemaining = 0
    private var resampleCrossfadeTotal = 0
    private var resampleCrossfadeStartPhase: Double = 0
    private var resampleCrossfadeTargetPhase: Double = 0
    private var resampleBuffersByNode: [UUID: [[Float]]] = [:]
    private var resampleWriteIndexByNode: [UUID: Int] = [:]
    private var resampleReadPhaseByNode: [UUID: Double] = [:]
    private var resampleCrossfadeRemainingByNode: [UUID: Int] = [:]
    private var resampleCrossfadeTotalByNode: [UUID: Int] = [:]
    private var resampleCrossfadeStartPhaseByNode: [UUID: Double] = [:]
    private var resampleCrossfadeTargetPhaseByNode: [UUID: Double] = [:]

    // Rubber Band state
    private var rubberBandNodes: [UUID: RubberBandWrapper] = [:]
    private var rubberBandGlobalByType: [EffectType: RubberBandWrapper] = [:]

    // Bitcrusher state
    private var bitcrusherHoldCounters: [Int] = []
    private var bitcrusherHoldValues: [Float] = []
    private var bitcrusherHoldCountersByNode: [UUID: [Int]] = [:]
    private var bitcrusherHoldValuesByNode: [UUID: [Float]] = [:]


    // Audio format: 48kHz, stereo, Float32 (matches what we're seeing in console)
    private let audioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 2,
        interleaved: false
    )!

    init() {
        setupNotifications()
        refreshOutputDevices()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Engine Control

    func start() {
        // First, request microphone permission
        if !refreshSetupStatus() {
            errorMessage = "System Input/Output must be set to BlackHole 2ch to start."
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

            setOutputDeviceVolume(deviceID: speakerDeviceID, volume: 1.0)

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
            AudioQueueSetParameter(outputQueue, kAudioQueueParam_Volume, 1.0)

            // Allocate buffers for the queue (match tap buffer size to avoid truncation)
            let bufferFrameCount = max(UInt32(4096), UInt32(inputFormat.sampleRate / 10.0))
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

    private func processManualGraph(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameLength: Int,
        channelCount: Int,
        sampleRate: Double
    ) -> [Float] {
        let inputBuffer = deinterleavedInput(channelData: channelData, frameLength: frameLength, channelCount: channelCount)
        let (processed, levelSnapshot) = processGraph(
            inputBuffer: inputBuffer,
            channelCount: channelCount,
            sampleRate: sampleRate,
            nodes: manualGraphNodes,
            connections: manualGraphConnections,
            startID: manualGraphStartID,
            endID: manualGraphEndID
        )
        updateEffectLevelsIfNeeded(levelSnapshot)
        return interleaveBuffer(processed, frameLength: frameLength, channelCount: channelCount)
    }

    private func processGraph(
        inputBuffer: [[Float]],
        channelCount: Int,
        sampleRate: Double,
        nodes: [BeginnerNode],
        connections: [BeginnerConnection],
        startID: UUID?,
        endID: UUID?
    ) -> ([[Float]], [UUID: Float]) {
        guard let startID, let endID else {
            return (inputBuffer, [:])
        }

        var outEdges: [UUID: [UUID]] = [:]
        var inEdges: [UUID: [(UUID, Double)]] = [:]
        for connection in connections {
            outEdges[connection.fromNodeId, default: []].append(connection.toNodeId)
            inEdges[connection.toNodeId, default: []].append((connection.fromNodeId, connection.gain))
        }

        let reachable = reachableNodes(from: startID, outEdges: outEdges)

        var sinkNodes: [UUID] = []
        for nodeID in reachable where nodeID != startID && nodeID != endID {
            let outs = outEdges[nodeID] ?? []
            let hasReachableOut = outs.contains(where: { reachable.contains($0) && $0 != endID })
            let hasEndOut = outs.contains(endID)
            if !hasReachableOut && !hasEndOut {
                sinkNodes.append(nodeID)
            }
        }

        for sink in sinkNodes {
            outEdges[sink, default: []].append(endID)
            inEdges[endID, default: []].append((sink, 1.0))
        }

        var indegree: [UUID: Int] = [:]
        for node in nodes where reachable.contains(node.id) {
            let incoming = inEdges[node.id] ?? []
            let count = incoming.filter { $0.0 != startID }.count
            indegree[node.id] = count
        }

        var queue: [UUID] = nodes.compactMap { node in
            guard reachable.contains(node.id) else { return nil }
            return (indegree[node.id] ?? 0) == 0 ? node.id : nil
        }

        var outputBuffers: [UUID: [[Float]]] = [:]
        var levelSnapshot: [UUID: Float] = [:]

        while let nodeID = queue.first {
            queue.removeFirst()
            guard let node = nodes.first(where: { $0.id == nodeID }) else { continue }

            let inputs = inEdges[nodeID] ?? []
            let merged = mergeInputs(
                inputs: inputs,
                startID: startID,
                inputBuffer: inputBuffer,
                outputBuffers: outputBuffers,
                frameLength: inputBuffer.first?.count ?? 0,
                channelCount: channelCount
            )

            var processed = merged
            applyEffect(
                node.type,
                to: &processed,
                sampleRate: sampleRate,
                channelCount: channelCount,
                frameLength: inputBuffer.first?.count ?? 0,
                nodeId: node.id,
                levelSnapshot: &levelSnapshot
            )
            outputBuffers[nodeID] = processed

            for next in outEdges[nodeID] ?? [] {
                guard reachable.contains(next), next != endID else { continue }
                indegree[next, default: 0] -= 1
                if indegree[next] == 0 {
                    queue.append(next)
                }
            }
        }

        let endInputs = inEdges[endID] ?? []
        let mixed = mergeInputs(
            inputs: endInputs,
            startID: startID,
            inputBuffer: inputBuffer,
            outputBuffers: outputBuffers,
            frameLength: inputBuffer.first?.count ?? 0,
            channelCount: channelCount
        )
        let limited = limiterEnabled ? applySoftLimiter(mixed) : mixed

        return (limited, levelSnapshot)
    }

    private func updateEffectLevelsIfNeeded(_ levelSnapshot: [UUID: Float]) {
        guard !levelSnapshot.isEmpty else { return }
        levelUpdateCounter += 1
        if levelUpdateCounter % 8 == 0 {
            let snapshot = levelSnapshot
            DispatchQueue.main.async {
                self.effectLevels = snapshot
            }
        }
    }

    private func reachableNodes(from startID: UUID, outEdges: [UUID: [UUID]]) -> Set<UUID> {
        var visited: Set<UUID> = [startID]
        var queue: [UUID] = [startID]

        while let current = queue.first {
            queue.removeFirst()
            for next in outEdges[current] ?? [] {
                if !visited.contains(next) {
                    visited.insert(next)
                    queue.append(next)
                }
            }
        }
        return visited
    }

    private func mergeInputs(
        inputs: [(UUID, Double)],
        startID: UUID,
        inputBuffer: [[Float]],
        outputBuffers: [UUID: [[Float]]],
        frameLength: Int,
        channelCount: Int
    ) -> [[Float]] {
        var merged = [[Float]](repeating: [Float](repeating: 0, count: frameLength), count: channelCount)
        guard !inputs.isEmpty else { return merged }

        for (source, gain) in inputs {
            let sourceBuffer: [[Float]]?
            if source == startID {
                sourceBuffer = inputBuffer
            } else {
                sourceBuffer = outputBuffers[source]
            }

            guard let buffer = sourceBuffer else { continue }
            let gainValue = Float(gain)
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    merged[channel][frame] += buffer[channel][frame] * gainValue
                }
            }
        }
        return merged
    }

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

    private func applySoftLimiter(_ buffer: [[Float]]) -> [[Float]] {
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

    private func deinterleavedInput(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameLength: Int,
        channelCount: Int
    ) -> [[Float]] {
        var output = [[Float]](repeating: [Float](repeating: 0, count: frameLength), count: channelCount)
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                output[channel][frame] = channelData[channel][frame]
            }
        }
        return output
    }

    private func interleaveInput(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameLength: Int,
        channelCount: Int
    ) -> [Float] {
        var interleaved = [Float](repeating: 0, count: frameLength * channelCount)
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                interleaved[frame * channelCount + channel] = channelData[channel][frame]
            }
        }
        return interleaved
    }

    private func interleaveBuffer(_ buffer: [[Float]], frameLength: Int, channelCount: Int) -> [Float] {
        var interleaved = [Float](repeating: 0, count: frameLength * channelCount)
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                interleaved[frame * channelCount + channel] = buffer[channel][frame]
            }
        }
        return interleaved
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

    private func interleavedData(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        effectStateLock.lock()
        defer { effectStateLock.unlock() }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate

        if isReconfiguring {
            var interleaved = [Float](repeating: 0, count: frameLength * channelCount)
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    interleaved[frame * channelCount + channel] = channelData[channel][frame]
                }
            }
            return interleaved
        }

        if !processingEnabled {
            var interleaved = [Float](repeating: 0, count: frameLength * channelCount)
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    interleaved[frame * channelCount + channel] = channelData[channel][frame]
                }
            }
            return interleaved
        }

        // Initialize effect states
        initializeEffectStates(channelCount: channelCount)

        if useSplitGraph {
            let inputBuffer = deinterleavedInput(
                channelData: channelData,
                frameLength: frameLength,
                channelCount: channelCount
            )

            if channelCount < 2 {
                let (processed, snapshot) = processGraph(
                    inputBuffer: inputBuffer,
                    channelCount: channelCount,
                    sampleRate: sampleRate,
                    nodes: splitLeftNodes,
                    connections: splitLeftConnections,
                    startID: splitLeftStartID,
                    endID: splitLeftEndID
                )
                updateEffectLevelsIfNeeded(snapshot)
                return interleaveBuffer(processed, frameLength: frameLength, channelCount: channelCount)
            }

            let leftInput = [inputBuffer[0]]
            let rightInput = [inputBuffer[1]]

            let (leftProcessed, leftSnapshot) = processGraph(
                inputBuffer: leftInput,
                channelCount: 1,
                sampleRate: sampleRate,
                nodes: splitLeftNodes,
                connections: splitLeftConnections,
                startID: splitLeftStartID,
                endID: splitLeftEndID
            )
            let (rightProcessed, rightSnapshot) = processGraph(
                inputBuffer: rightInput,
                channelCount: 1,
                sampleRate: sampleRate,
                nodes: splitRightNodes,
                connections: splitRightConnections,
                startID: splitRightStartID,
                endID: splitRightEndID
            )

            var combined = inputBuffer
            if let leftChannel = leftProcessed.first {
                combined[0] = leftChannel
            }
            if combined.count > 1, let rightChannel = rightProcessed.first {
                combined[1] = rightChannel
            }

            var mergedSnapshot = leftSnapshot
            for (key, value) in rightSnapshot {
                mergedSnapshot[key] = value
            }
            updateEffectLevelsIfNeeded(mergedSnapshot)

            return interleaveBuffer(combined, frameLength: frameLength, channelCount: channelCount)
        }

        if useManualGraph {
            return processManualGraph(
                channelData: channelData,
                frameLength: frameLength,
                channelCount: channelCount,
                sampleRate: sampleRate
            )
        }

        // Process audio through effect chain
        var processedAudio = [[Float]](repeating: [Float](repeating: 0, count: frameLength), count: channelCount)

        // Copy input to processed audio
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                processedAudio[channel][frame] = channelData[channel][frame]
            }
        }

        let orderedNodes: [EffectNode]
        if effectChainOrder.isEmpty {
            orderedNodes = defaultEffectOrder.map { EffectNode(id: nil, type: $0) }
        } else {
            orderedNodes = effectChainOrder.map { EffectNode(id: $0.id, type: $0.type) }
        }

        var levelSnapshot: [UUID: Float] = [:]
        for node in orderedNodes {
            applyEffect(
                node.type,
                to: &processedAudio,
                sampleRate: sampleRate,
                channelCount: channelCount,
                frameLength: frameLength,
                nodeId: node.id,
                levelSnapshot: &levelSnapshot
            )
        }

        if !levelSnapshot.isEmpty {
            levelUpdateCounter += 1
            if levelUpdateCounter % 8 == 0 {
                let snapshot = levelSnapshot
                DispatchQueue.main.async {
                    self.effectLevels = snapshot
                }
            }
        }

        // Convert to interleaved format
        var interleaved = [Float](repeating: 0, count: frameLength * channelCount)
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                interleaved[frame * channelCount + channel] = processedAudio[channel][frame]
            }
        }

        return interleaved
    }

    private var defaultEffectOrder: [EffectType] {
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

    private struct EffectNode {
        let id: UUID?
        let type: EffectType
    }

    private func nodeParams(for nodeId: UUID?) -> NodeEffectParameters? {
        guard let nodeId else { return nil }
        return nodeParameters[nodeId]
    }

    private func nodeIsEnabled(_ nodeId: UUID?) -> Bool {
        guard let nodeId else { return true }
        return nodeEnabled[nodeId] ?? true
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

    private func applyRubberBand(
        _ processor: RubberBandWrapper,
        to processedAudio: inout [[Float]],
        frameLength: Int,
        channelCount: Int
    ) {
        guard frameLength > 0, channelCount > 0 else { return }
        var interleaved = [Float](repeating: 0, count: frameLength * channelCount)
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                interleaved[frame * channelCount + channel] = processedAudio[channel][frame]
            }
        }

        var output = [Float](repeating: 0, count: frameLength * channelCount)
        interleaved.withUnsafeBufferPointer { inputPtr in
            output.withUnsafeMutableBufferPointer { outputPtr in
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
                processedAudio[channel][frame] = output[index]
                index += 1
            }
        }
    }

    private var tenBandGains: [Double] {
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

    private func applyEffect(
        _ effect: EffectType,
        to processedAudio: inout [[Float]],
        sampleRate: Double,
        channelCount: Int,
        frameLength: Int,
        nodeId: UUID?,
        levelSnapshot: inout [UUID: Float]
    ) {
        switch effect {
        case .bassBoost:
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? bassBoostEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let amount = nodeParams(for: nodeId)?.bassBoostAmount ?? bassBoostAmount
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? nightcoreEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }
            return

        case .clarity:
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? clarityEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let amount = nodeParams(for: nodeId)?.clarityAmount ?? clarityAmount
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? deMudEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let strength = nodeParams(for: nodeId)?.deMudStrength ?? deMudStrength
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? simpleEQEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let params = nodeParams(for: nodeId)
            let bass = params?.eqBass ?? eqBass
            let mids = params?.eqMids ?? eqMids
            let treble = params?.eqTreble ?? eqTreble
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? tenBandEQEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let gains = nodeParams(for: nodeId)?.tenBandGains ?? tenBandGains
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? compressorEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let strength = nodeParams(for: nodeId)?.compressorStrength ?? compressorStrength
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? reverbEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let mixValue = nodeParams(for: nodeId)?.reverbMix ?? reverbMix
            let sizeValue = nodeParams(for: nodeId)?.reverbSize ?? reverbSize
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? delayEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let mixValue = nodeParams(for: nodeId)?.delayMix ?? delayMix
            let feedbackValue = nodeParams(for: nodeId)?.delayFeedback ?? delayFeedback
            let timeValue = nodeParams(for: nodeId)?.delayTime ?? delayTime
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? distortionEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let driveValue = nodeParams(for: nodeId)?.distortionDrive ?? distortionDrive
            let mixValue = nodeParams(for: nodeId)?.distortionMix ?? distortionMix
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? tremoloEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let rateValue = nodeParams(for: nodeId)?.tremoloRate ?? tremoloRate
            let depthValue = nodeParams(for: nodeId)?.tremoloDepth ?? tremoloDepth
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? chorusEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let rateValue = nodeParams(for: nodeId)?.chorusRate ?? chorusRate
            let depthValue = nodeParams(for: nodeId)?.chorusDepth ?? chorusDepth
            let mixValue = nodeParams(for: nodeId)?.chorusMix ?? chorusMix
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? phaserEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let rateValue = nodeParams(for: nodeId)?.phaserRate ?? phaserRate
            let depthValue = nodeParams(for: nodeId)?.phaserDepth ?? phaserDepth
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? flangerEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let rateValue = nodeParams(for: nodeId)?.flangerRate ?? flangerRate
            let depthValue = nodeParams(for: nodeId)?.flangerDepth ?? flangerDepth
            let feedbackValue = nodeParams(for: nodeId)?.flangerFeedback ?? flangerFeedback
            let mixValue = nodeParams(for: nodeId)?.flangerMix ?? flangerMix
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? bitcrusherEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let bitDepthValue = Int(nodeParams(for: nodeId)?.bitcrusherBitDepth ?? bitcrusherBitDepth)
            let downsampleValue = Int(nodeParams(for: nodeId)?.bitcrusherDownsample ?? bitcrusherDownsample)
            let mixValue = nodeParams(for: nodeId)?.bitcrusherMix ?? bitcrusherMix
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? tapeSaturationEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let driveValue = nodeParams(for: nodeId)?.tapeSaturationDrive ?? tapeSaturationDrive
            let mixValue = nodeParams(for: nodeId)?.tapeSaturationMix ?? tapeSaturationMix
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? stereoWidthEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let amount = nodeParams(for: nodeId)?.stereoWidthAmount ?? stereoWidthAmount
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
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? rubberBandPitchEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let semitones = nodeParams(for: nodeId)?.rubberBandPitchSemitones ?? rubberBandPitchSemitones
            guard abs(semitones) > 0.01 else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let processor = rubberBandProcessor(for: nodeId, type: .rubberBandPitch, sampleRate: sampleRate, channels: channelCount)
            processor.setPitchSemitones(semitones)
            applyRubberBand(processor, to: &processedAudio, frameLength: frameLength, channelCount: channelCount)
            if let id = nodeId {
                levelSnapshot[id] = computeRMS(processedAudio, frameLength: frameLength, channelCount: channelCount)
            }

        case .resampling:
            if let id = nodeId, !nodeIsEnabled(id) {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            guard nodeId == nil ? resampleEnabled : true else {
                if let id = nodeId { levelSnapshot[id] = 0 }
                return
            }
            let rateValue = nodeParams(for: nodeId)?.resampleRate ?? resampleRate
            let crossfadeValue = nodeParams(for: nodeId)?.resampleCrossfade ?? resampleCrossfade
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

    private func initializeEffectStates(channelCount: Int) {
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

    private func withEffectStateLock(_ work: () -> Void) {
        effectStateLock.lock()
        defer { effectStateLock.unlock() }
        work()
    }

    private func resetBassBoostState() {
        withEffectStateLock {
            resetBassBoostStateUnlocked()
        }
    }

    private func resetBassBoostStateUnlocked() {
        if !bassBoostState.isEmpty {
            for index in bassBoostState.indices {
                bassBoostState[index] = BiquadState()
            }
        }
    }

    private func resetClarityState() {
        withEffectStateLock {
            resetClarityStateUnlocked()
        }
    }

    private func resetClarityStateUnlocked() {
        clarityState = clarityState.map { _ in BiquadState() }
    }

    private func resetDeMudState() {
        withEffectStateLock {
            resetDeMudStateUnlocked()
        }
    }

    private func resetDeMudStateUnlocked() {
        deMudState = deMudState.map { _ in BiquadState() }
    }

    private func resetEQState() {
        withEffectStateLock {
            resetEQStateUnlocked()
        }
    }

    private func resetEQStateUnlocked() {
        eqBassState = eqBassState.map { _ in BiquadState() }
        eqMidsState = eqMidsState.map { _ in BiquadState() }
        eqTrebleState = eqTrebleState.map { _ in BiquadState() }
    }

    private func resetTenBandEQState() {
        withEffectStateLock {
            resetTenBandEQStateUnlocked()
        }
    }

    private func resetTenBandEQStateUnlocked() {
        tenBandStates = tenBandStates.map { bandStates in
            bandStates.map { _ in BiquadState() }
        }
    }

    private func resetTenBandValues() {
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

    private func resetCompressorState() {
        withEffectStateLock {
            resetCompressorStateUnlocked()
        }
    }

    private func resetCompressorStateUnlocked() {
        compressorEnvelope = compressorEnvelope.map { _ in 0 }
    }

    private func resetReverbState() {
        withEffectStateLock {
            resetReverbStateUnlocked()
        }
    }

    private func resetReverbStateUnlocked() {
        reverbBuffer.removeAll()
        reverbWriteIndex = 0
    }

    private func resetDelayState() {
        withEffectStateLock {
            resetDelayStateUnlocked()
        }
    }

    private func resetDelayStateUnlocked() {
        delayBuffer.removeAll()
        delayWriteIndex = 0
    }

    private func resetChorusState() {
        withEffectStateLock {
            chorusBuffer.removeAll()
            chorusWriteIndex = 0
            chorusPhase = 0
            chorusBuffersByNode.removeAll()
            chorusWriteIndexByNode.removeAll()
            chorusPhaseByNode.removeAll()
        }
    }

    private func resetFlangerState() {
        withEffectStateLock {
            flangerBuffer.removeAll()
            flangerWriteIndex = 0
            flangerPhase = 0
            flangerBuffersByNode.removeAll()
            flangerWriteIndexByNode.removeAll()
            flangerPhaseByNode.removeAll()
        }
    }

    private func resetPhaserState() {
        withEffectStateLock {
            phaserStates = Array(
                repeating: Array(repeating: AllPassState(), count: phaserStageCount),
                count: phaserStates.count
            )
            phaserPhase = 0
            phaserStatesByNode.removeAll()
            phaserPhaseByNode.removeAll()
        }
    }

    private func resetBitcrusherState() {
        withEffectStateLock {
            bitcrusherHoldCounters = bitcrusherHoldCounters.map { _ in 0 }
            bitcrusherHoldValues = bitcrusherHoldValues.map { _ in 0 }
            bitcrusherHoldCountersByNode.removeAll()
            bitcrusherHoldValuesByNode.removeAll()
        }
    }

    private func resetEffectState() {
        withEffectStateLock {
            resetBassBoostStateUnlocked()
            resetClarityStateUnlocked()
            resetDeMudStateUnlocked()
            resetEQStateUnlocked()
            resetTenBandEQStateUnlocked()
            resetCompressorStateUnlocked()
            tremoloPhase = 0
            resetReverbStateUnlocked()
            resetDelayStateUnlocked()
            chorusBuffer.removeAll()
            chorusWriteIndex = 0
            chorusPhase = 0
            flangerBuffer.removeAll()
            flangerWriteIndex = 0
            flangerPhase = 0
            phaserPhase = 0
            bitcrusherHoldCounters = bitcrusherHoldCounters.map { _ in 0 }
            bitcrusherHoldValues = bitcrusherHoldValues.map { _ in 0 }
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
        DispatchQueue.main.async {
            self.effectLevels = [:]
        }
    }

    // Note: Proper pitch shifting without tempo change requires complex DSP (phase vocoder, etc.)
    // For now, nightcore is implemented as a simple brightness/clarity boost
    // True pitch shifting will be added in a future update

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

    func systemDefaultInputDeviceName() -> String? {
        guard let deviceID = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice),
              let device = AudioDevice(id: deviceID) else {
            return nil
        }
        return device.name
    }

    func systemDefaultOutputDeviceName() -> String? {
        guard let deviceID = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice),
              let device = AudioDevice(id: deviceID) else {
            return nil
        }
        return device.name
    }

    private func systemDefaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else { return nil }
        return deviceID
    }

    @discardableResult
    func refreshSetupStatus() -> Bool {
        let inputName = systemDefaultInputDeviceName()
        let outputName = systemDefaultOutputDeviceName()
        let ready = (inputName?.localizedCaseInsensitiveContains("BlackHole") == true) &&
            (outputName?.localizedCaseInsensitiveContains("BlackHole") == true)
        if setupReady != ready {
            DispatchQueue.main.async {
                self.setupReady = ready
            }
        }
        return ready
    }

    private func startSetupMonitor() {
        guard setupMonitorTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let ready = self.refreshSetupStatus()
            if !ready && self.isRunning {
                DispatchQueue.main.async {
                    self.errorMessage = "Input or output changed. Set System Input/Output to BlackHole 2ch to resume."
                    self.stop()
                }
            }
        }
        setupMonitorTimer = timer
        timer.resume()
    }

    private func stopSetupMonitor() {
        setupMonitorTimer?.cancel()
        setupMonitorTimer = nil
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

    private func setOutputDeviceVolume(deviceID: AudioDeviceID, volume: Float) {
        var vol = volume
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float>.size),
            &vol
        )

        if status == noErr {
            // Debug output removed.
            return
        }

        // Fallback to per-channel volume when virtual master isn't supported.
        for channel in 1...2 {
            var channelAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(channel)
            )
            var channelVol = volume
            status = AudioObjectSetPropertyData(
                deviceID,
                &channelAddress,
                0,
                nil,
                UInt32(MemoryLayout<Float>.size),
                &channelVol
            )
        }

        if status == noErr {
            // Debug output removed.
        } else {
            // Debug output removed.
        }
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

    private func refreshOutputDevices() {
        let devices = getAllAudioDevices().filter { $0.hasOutput }
        outputDevices = devices

        if selectedOutputDeviceID == nil {
            selectedOutputDeviceID = findRealOutputDevice()?.id
        }
    }

    func stop() {
        stopInternal(setReconfiguringFlag: false)
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
        audioRingBuffer.removeAll()
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

    private func reconfigureAudio() {
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

    private func setupNotifications() {
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

    // MARK: - Preset Support

    func getCurrentEffectChain() -> EffectChainSnapshot {
        var activeEffects: [EffectChainSnapshot.EffectSnapshot] = []

        // Bass Boost
        if bassBoostEnabled {
            let params = EffectChainSnapshot.EffectParameters(bassBoostAmount: bassBoostAmount)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .bassBoost, isEnabled: true, parameters: params))
        }

        // Nightcore
        if nightcoreEnabled {
            let params = EffectChainSnapshot.EffectParameters(nightcoreIntensity: nightcoreIntensity)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .pitchShift, isEnabled: true, parameters: params))
        }

        // Clarity
        if clarityEnabled {
            let params = EffectChainSnapshot.EffectParameters(clarityAmount: clarityAmount)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .clarity, isEnabled: true, parameters: params))
        }

        // De-Mud
        if deMudEnabled {
            let params = EffectChainSnapshot.EffectParameters(deMudStrength: deMudStrength)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .deMud, isEnabled: true, parameters: params))
        }

        // Simple EQ
        if simpleEQEnabled {
            let params = EffectChainSnapshot.EffectParameters(eqBass: eqBass, eqMids: eqMids, eqTreble: eqTreble)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .simpleEQ, isEnabled: true, parameters: params))
        }

        // 10-Band EQ
        if tenBandEQEnabled {
            let params = EffectChainSnapshot.EffectParameters(tenBandGains: tenBandGains)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .tenBandEQ, isEnabled: true, parameters: params))
        }

        // Compressor
        if compressorEnabled {
            let params = EffectChainSnapshot.EffectParameters(compressorStrength: compressorStrength)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .compressor, isEnabled: true, parameters: params))
        }

        // Reverb
        if reverbEnabled {
            let params = EffectChainSnapshot.EffectParameters(reverbMix: reverbMix, reverbSize: reverbSize)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .reverb, isEnabled: true, parameters: params))
        }

        // Stereo Width
        if stereoWidthEnabled {
            let params = EffectChainSnapshot.EffectParameters(stereoWidthAmount: stereoWidthAmount)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .stereoWidth, isEnabled: true, parameters: params))
        }

        // Resampling
        if resampleEnabled {
            let params = EffectChainSnapshot.EffectParameters(resampleRate: resampleRate, resampleCrossfade: resampleCrossfade)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .resampling, isEnabled: true, parameters: params))
        }

        // Rubber Band Pitch
        if rubberBandPitchEnabled {
            let params = EffectChainSnapshot.EffectParameters(rubberBandPitchSemitones: rubberBandPitchSemitones)
            activeEffects.append(EffectChainSnapshot.EffectSnapshot(type: .rubberBandPitch, isEnabled: true, parameters: params))
        }

        return EffectChainSnapshot(activeEffects: activeEffects)
    }

    func applyEffectChain(_ chain: EffectChainSnapshot) {
        // First disable all effects
        bassBoostEnabled = false
        nightcoreEnabled = false
        clarityEnabled = false
        deMudEnabled = false
        simpleEQEnabled = false
        tenBandEQEnabled = false
        compressorEnabled = false
        reverbEnabled = false
        stereoWidthEnabled = false
        delayEnabled = false
        distortionEnabled = false
        tremoloEnabled = false
        chorusEnabled = false
        phaserEnabled = false
        flangerEnabled = false
        bitcrusherEnabled = false
        tapeSaturationEnabled = false
        resampleEnabled = false
        rubberBandPitchEnabled = false
        resetTenBandValues()

        // Then apply each effect from the chain
        for effect in chain.activeEffects {
            let params = effect.parameters

            switch effect.type {
            case .bassBoost:
                bassBoostEnabled = effect.isEnabled
                if let amount = params.bassBoostAmount {
                    bassBoostAmount = amount
                }

            case .pitchShift: // Nightcore
                nightcoreEnabled = effect.isEnabled
                if let intensity = params.nightcoreIntensity {
                    nightcoreIntensity = intensity
                }

            case .clarity:
                clarityEnabled = effect.isEnabled
                if let amount = params.clarityAmount {
                    clarityAmount = amount
                }

            case .deMud:
                deMudEnabled = effect.isEnabled
                if let strength = params.deMudStrength {
                    deMudStrength = strength
                }

            case .simpleEQ:
                simpleEQEnabled = effect.isEnabled
                if let bass = params.eqBass { eqBass = bass }
                if let mids = params.eqMids { eqMids = mids }
                if let treble = params.eqTreble { eqTreble = treble }

            case .tenBandEQ:
                tenBandEQEnabled = effect.isEnabled
                if let gains = params.tenBandGains, gains.count == tenBandFrequencies.count {
                    tenBand31 = gains[0]
                    tenBand62 = gains[1]
                    tenBand125 = gains[2]
                    tenBand250 = gains[3]
                    tenBand500 = gains[4]
                    tenBand1k = gains[5]
                    tenBand2k = gains[6]
                    tenBand4k = gains[7]
                    tenBand8k = gains[8]
                    tenBand16k = gains[9]
                }

            case .compressor:
                compressorEnabled = effect.isEnabled
                if let strength = params.compressorStrength {
                    compressorStrength = strength
                }

            case .reverb:
                reverbEnabled = effect.isEnabled
                if let mix = params.reverbMix { reverbMix = mix }
                if let size = params.reverbSize { reverbSize = size }

            case .stereoWidth:
                stereoWidthEnabled = effect.isEnabled
                if let amount = params.stereoWidthAmount {
                    stereoWidthAmount = amount
                }

            case .delay:
                delayEnabled = effect.isEnabled
                // Delay parameters will be added to EffectParameters later

            case .distortion:
                distortionEnabled = effect.isEnabled
                // Distortion parameters will be added to EffectParameters later

            case .tremolo:
                tremoloEnabled = effect.isEnabled
                // Tremolo parameters will be added to EffectParameters later

            case .chorus:
                chorusEnabled = effect.isEnabled

            case .phaser:
                phaserEnabled = effect.isEnabled

            case .flanger:
                flangerEnabled = effect.isEnabled

            case .bitcrusher:
                bitcrusherEnabled = effect.isEnabled

            case .tapeSaturation:
                tapeSaturationEnabled = effect.isEnabled

            case .resampling:
                resampleEnabled = effect.isEnabled

            case .rubberBandPitch:
                rubberBandPitchEnabled = effect.isEnabled
                if let semitones = params.rubberBandPitchSemitones {
                    rubberBandPitchSemitones = semitones
                }
            }
        }

        // Debug output removed.
    }

    func updateEffectChain(_ chain: [BeginnerNode]) {
        withEffectStateLock {
            effectChainOrder = chain
            useManualGraph = false
            useSplitGraph = false
            syncNodeState(chain)
        }

        let activeTypes = Set(chain.filter { $0.isEnabled }.map { $0.type })

        bassBoostEnabled = activeTypes.contains(.bassBoost)
        nightcoreEnabled = activeTypes.contains(.pitchShift)
        clarityEnabled = activeTypes.contains(.clarity)
        deMudEnabled = activeTypes.contains(.deMud)
        simpleEQEnabled = activeTypes.contains(.simpleEQ)
        tenBandEQEnabled = activeTypes.contains(.tenBandEQ)
        compressorEnabled = activeTypes.contains(.compressor)
        reverbEnabled = activeTypes.contains(.reverb)
        stereoWidthEnabled = activeTypes.contains(.stereoWidth)
        delayEnabled = activeTypes.contains(.delay)
        distortionEnabled = activeTypes.contains(.distortion)
        tremoloEnabled = activeTypes.contains(.tremolo)
        chorusEnabled = activeTypes.contains(.chorus)
        phaserEnabled = activeTypes.contains(.phaser)
        flangerEnabled = activeTypes.contains(.flanger)
        bitcrusherEnabled = activeTypes.contains(.bitcrusher)
        tapeSaturationEnabled = activeTypes.contains(.tapeSaturation)
        resampleEnabled = activeTypes.contains(.resampling)
        rubberBandPitchEnabled = activeTypes.contains(.rubberBandPitch)

        if !activeTypes.contains(.tenBandEQ) {
            resetTenBandValues()
        }

        if chain.isEmpty {
            resetEffectState()
            DispatchQueue.main.async {
                self.effectLevels = [:]
            }
        }
        // Debug output removed.
    }

    func updateEffectGraph(nodes: [BeginnerNode], connections: [BeginnerConnection], startID: UUID, endID: UUID) {
        withEffectStateLock {
            manualGraphNodes = nodes
            manualGraphConnections = connections
            manualGraphStartID = startID
            manualGraphEndID = endID
            useManualGraph = true
            useSplitGraph = false
            syncNodeState(nodes)
        }

        let activeTypes = Set(nodes.filter { $0.isEnabled }.map { $0.type })
        bassBoostEnabled = activeTypes.contains(.bassBoost)
        nightcoreEnabled = activeTypes.contains(.pitchShift)
        clarityEnabled = activeTypes.contains(.clarity)
        deMudEnabled = activeTypes.contains(.deMud)
        simpleEQEnabled = activeTypes.contains(.simpleEQ)
        tenBandEQEnabled = activeTypes.contains(.tenBandEQ)
        compressorEnabled = activeTypes.contains(.compressor)
        reverbEnabled = activeTypes.contains(.reverb)
        stereoWidthEnabled = activeTypes.contains(.stereoWidth)
        delayEnabled = activeTypes.contains(.delay)
        distortionEnabled = activeTypes.contains(.distortion)
        tremoloEnabled = activeTypes.contains(.tremolo)
        chorusEnabled = activeTypes.contains(.chorus)
        phaserEnabled = activeTypes.contains(.phaser)
        flangerEnabled = activeTypes.contains(.flanger)
        bitcrusherEnabled = activeTypes.contains(.bitcrusher)
        tapeSaturationEnabled = activeTypes.contains(.tapeSaturation)
        resampleEnabled = activeTypes.contains(.resampling)
        rubberBandPitchEnabled = activeTypes.contains(.rubberBandPitch)
    }

    func updateEffectGraphSplit(
        leftNodes: [BeginnerNode],
        leftConnections: [BeginnerConnection],
        leftStartID: UUID,
        leftEndID: UUID,
        rightNodes: [BeginnerNode],
        rightConnections: [BeginnerConnection],
        rightStartID: UUID,
        rightEndID: UUID
    ) {
        withEffectStateLock {
            splitLeftNodes = leftNodes
            splitLeftConnections = leftConnections
            splitLeftStartID = leftStartID
            splitLeftEndID = leftEndID
            splitRightNodes = rightNodes
            splitRightConnections = rightConnections
            splitRightStartID = rightStartID
            splitRightEndID = rightEndID
            useSplitGraph = true
            useManualGraph = false
            syncNodeState(leftNodes + rightNodes)
        }

        let activeTypes = Set((leftNodes + rightNodes).filter { $0.isEnabled }.map { $0.type })
        bassBoostEnabled = activeTypes.contains(.bassBoost)
        nightcoreEnabled = activeTypes.contains(.pitchShift)
        clarityEnabled = activeTypes.contains(.clarity)
        deMudEnabled = activeTypes.contains(.deMud)
        simpleEQEnabled = activeTypes.contains(.simpleEQ)
        tenBandEQEnabled = activeTypes.contains(.tenBandEQ)
        compressorEnabled = activeTypes.contains(.compressor)
        reverbEnabled = activeTypes.contains(.reverb)
        stereoWidthEnabled = activeTypes.contains(.stereoWidth)
        delayEnabled = activeTypes.contains(.delay)
        distortionEnabled = activeTypes.contains(.distortion)
        tremoloEnabled = activeTypes.contains(.tremolo)
        chorusEnabled = activeTypes.contains(.chorus)
        phaserEnabled = activeTypes.contains(.phaser)
        flangerEnabled = activeTypes.contains(.flanger)
        bitcrusherEnabled = activeTypes.contains(.bitcrusher)
        tapeSaturationEnabled = activeTypes.contains(.tapeSaturation)
        resampleEnabled = activeTypes.contains(.resampling)
        rubberBandPitchEnabled = activeTypes.contains(.rubberBandPitch)
    }

    func updateGraphSnapshot(_ snapshot: GraphSnapshot?) {
        currentGraphSnapshot = snapshot
    }

    func requestGraphLoad(_ snapshot: GraphSnapshot?) {
        pendingGraphSnapshot = snapshot
    }

    private func syncNodeState(_ nodes: [BeginnerNode]) {
        let ids = Set(nodes.map { $0.id })
        nodeParameters = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.parameters) })
        nodeEnabled = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.isEnabled) })
        bassBoostStatesByNode = bassBoostStatesByNode.filter { ids.contains($0.key) }
        clarityStatesByNode = clarityStatesByNode.filter { ids.contains($0.key) }
        nightcoreStatesByNode = nightcoreStatesByNode.filter { ids.contains($0.key) }
        deMudStatesByNode = deMudStatesByNode.filter { ids.contains($0.key) }
        eqBassStatesByNode = eqBassStatesByNode.filter { ids.contains($0.key) }
        eqMidsStatesByNode = eqMidsStatesByNode.filter { ids.contains($0.key) }
        eqTrebleStatesByNode = eqTrebleStatesByNode.filter { ids.contains($0.key) }
        tenBandStatesByNode = tenBandStatesByNode.filter { ids.contains($0.key) }
        reverbBuffersByNode = reverbBuffersByNode.filter { ids.contains($0.key) }
        reverbWriteIndexByNode = reverbWriteIndexByNode.filter { ids.contains($0.key) }
        delayBuffersByNode = delayBuffersByNode.filter { ids.contains($0.key) }
        delayWriteIndexByNode = delayWriteIndexByNode.filter { ids.contains($0.key) }
        tremoloPhaseByNode = tremoloPhaseByNode.filter { ids.contains($0.key) }
        chorusBuffersByNode = chorusBuffersByNode.filter { ids.contains($0.key) }
        chorusWriteIndexByNode = chorusWriteIndexByNode.filter { ids.contains($0.key) }
        chorusPhaseByNode = chorusPhaseByNode.filter { ids.contains($0.key) }
        flangerBuffersByNode = flangerBuffersByNode.filter { ids.contains($0.key) }
        flangerWriteIndexByNode = flangerWriteIndexByNode.filter { ids.contains($0.key) }
        flangerPhaseByNode = flangerPhaseByNode.filter { ids.contains($0.key) }
        phaserStatesByNode = phaserStatesByNode.filter { ids.contains($0.key) }
        phaserPhaseByNode = phaserPhaseByNode.filter { ids.contains($0.key) }
        bitcrusherHoldCountersByNode = bitcrusherHoldCountersByNode.filter { ids.contains($0.key) }
        bitcrusherHoldValuesByNode = bitcrusherHoldValuesByNode.filter { ids.contains($0.key) }
        resampleBuffersByNode = resampleBuffersByNode.filter { ids.contains($0.key) }
        resampleWriteIndexByNode = resampleWriteIndexByNode.filter { ids.contains($0.key) }
        resampleReadPhaseByNode = resampleReadPhaseByNode.filter { ids.contains($0.key) }
        resampleCrossfadeRemainingByNode = resampleCrossfadeRemainingByNode.filter { ids.contains($0.key) }
        resampleCrossfadeTotalByNode = resampleCrossfadeTotalByNode.filter { ids.contains($0.key) }
        resampleCrossfadeStartPhaseByNode = resampleCrossfadeStartPhaseByNode.filter { ids.contains($0.key) }
        resampleCrossfadeTargetPhaseByNode = resampleCrossfadeTargetPhaseByNode.filter { ids.contains($0.key) }
        rubberBandNodes = rubberBandNodes.filter { ids.contains($0.key) }
    }

}

// MARK: - Audio Device Helper

struct AudioDevice: Identifiable, Hashable {
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

// MARK: - Bass Boost Biquad

private struct BiquadState {
    var x1: Float = 0
    var x2: Float = 0
    var y1: Float = 0
    var y2: Float = 0
}

private struct AllPassState {
    var x1: Float = 0
    var y1: Float = 0
}

private struct BiquadCoefficients {
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
        } else {
            // Buffer too small, fill with silence
            memset(inBuffer.pointee.mAudioData, 0, bufferSize)
            inBuffer.pointee.mAudioDataByteSize = UInt32(bufferSize)
        }
    } else {
        // No audio data available, output silence
        let bufferSize = Int(inBuffer.pointee.mAudioDataBytesCapacity)
        memset(inBuffer.pointee.mAudioData, 0, bufferSize)
        inBuffer.pointee.mAudioDataByteSize = UInt32(bufferSize)
        DebugCounter.emptyCount += 1
        if DebugCounter.emptyCount % 50 == 0 {
            // Debug output removed.
        }
    }

    // Re-enqueue the buffer
    AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
}
