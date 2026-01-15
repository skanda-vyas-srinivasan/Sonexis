import AVFoundation
import Combine
import CoreAudio
import AudioToolbox

struct ProcessingSnapshot {
    let useSplitGraph: Bool
    let useManualGraph: Bool
    let splitLeftNodes: [BeginnerNode]
    let splitLeftConnections: [BeginnerConnection]
    let splitLeftStartID: UUID?
    let splitLeftEndID: UUID?
    let splitRightNodes: [BeginnerNode]
    let splitRightConnections: [BeginnerConnection]
    let splitRightStartID: UUID?
    let splitRightEndID: UUID?
    let splitAutoConnectEnd: Bool
    let manualGraphNodes: [BeginnerNode]
    let manualGraphConnections: [BeginnerConnection]
    let manualGraphStartID: UUID?
    let manualGraphEndID: UUID?
    let manualGraphAutoConnectEnd: Bool
    let effectChainOrder: [AudioEngine.EffectNode]
    let nodeParameters: [UUID: NodeEffectParameters]
    let nodeEnabled: [UUID: Bool]
    let processingEnabled: Bool
    let limiterEnabled: Bool
    let isReconfiguring: Bool
    let bassBoostEnabled: Bool
    let bassBoostAmount: Double
    let nightcoreEnabled: Bool
    let nightcoreIntensity: Double
    let clarityEnabled: Bool
    let clarityAmount: Double
    let deMudEnabled: Bool
    let deMudStrength: Double
    let simpleEQEnabled: Bool
    let eqBass: Double
    let eqMids: Double
    let eqTreble: Double
    let tenBandEQEnabled: Bool
    let tenBandGains: [Double]
    let compressorEnabled: Bool
    let compressorStrength: Double
    let reverbEnabled: Bool
    let reverbMix: Double
    let reverbSize: Double
    let delayEnabled: Bool
    let delayTime: Double
    let delayFeedback: Double
    let delayMix: Double
    let distortionEnabled: Bool
    let distortionDrive: Double
    let distortionMix: Double
    let tremoloEnabled: Bool
    let tremoloRate: Double
    let tremoloDepth: Double
    let chorusEnabled: Bool
    let chorusRate: Double
    let chorusDepth: Double
    let chorusMix: Double
    let phaserEnabled: Bool
    let phaserRate: Double
    let phaserDepth: Double
    let flangerEnabled: Bool
    let flangerRate: Double
    let flangerDepth: Double
    let flangerFeedback: Double
    let flangerMix: Double
    let bitcrusherEnabled: Bool
    let bitcrusherBitDepth: Double
    let bitcrusherDownsample: Double
    let bitcrusherMix: Double
    let tapeSaturationEnabled: Bool
    let tapeSaturationDrive: Double
    let tapeSaturationMix: Double
    let stereoWidthEnabled: Bool
    let stereoWidthAmount: Double
    let resampleEnabled: Bool
    let resampleRate: Double
    let resampleCrossfade: Double
    let rubberBandPitchEnabled: Bool
    let rubberBandPitchSemitones: Double

    static let empty = ProcessingSnapshot(
        useSplitGraph: false,
        useManualGraph: false,
        splitLeftNodes: [],
        splitLeftConnections: [],
        splitLeftStartID: nil,
        splitLeftEndID: nil,
        splitRightNodes: [],
        splitRightConnections: [],
        splitRightStartID: nil,
        splitRightEndID: nil,
        splitAutoConnectEnd: true,
        manualGraphNodes: [],
        manualGraphConnections: [],
        manualGraphStartID: nil,
        manualGraphEndID: nil,
        manualGraphAutoConnectEnd: true,
        effectChainOrder: [],
        nodeParameters: [:],
        nodeEnabled: [:],
        processingEnabled: true,
        limiterEnabled: true,
        isReconfiguring: false,
        bassBoostEnabled: false,
        bassBoostAmount: 0,
        nightcoreEnabled: false,
        nightcoreIntensity: 0,
        clarityEnabled: false,
        clarityAmount: 0,
        deMudEnabled: false,
        deMudStrength: 0,
        simpleEQEnabled: false,
        eqBass: 0,
        eqMids: 0,
        eqTreble: 0,
        tenBandEQEnabled: false,
        tenBandGains: [],
        compressorEnabled: false,
        compressorStrength: 0,
        reverbEnabled: false,
        reverbMix: 0,
        reverbSize: 0,
        delayEnabled: false,
        delayTime: 0,
        delayFeedback: 0,
        delayMix: 0,
        distortionEnabled: false,
        distortionDrive: 0,
        distortionMix: 0,
        tremoloEnabled: false,
        tremoloRate: 0,
        tremoloDepth: 0,
        chorusEnabled: false,
        chorusRate: 0,
        chorusDepth: 0,
        chorusMix: 0,
        phaserEnabled: false,
        phaserRate: 0,
        phaserDepth: 0,
        flangerEnabled: false,
        flangerRate: 0,
        flangerDepth: 0,
        flangerFeedback: 0,
        flangerMix: 0,
        bitcrusherEnabled: false,
        bitcrusherBitDepth: 0,
        bitcrusherDownsample: 0,
        bitcrusherMix: 0,
        tapeSaturationEnabled: false,
        tapeSaturationDrive: 0,
        tapeSaturationMix: 0,
        stereoWidthEnabled: false,
        stereoWidthAmount: 0,
        resampleEnabled: false,
        resampleRate: 0,
        resampleCrossfade: 0,
        rubberBandPitchEnabled: false,
        rubberBandPitchSemitones: 0
    )
}

struct ResetFlags: OptionSet {
    let rawValue: Int

    static let bassBoost = ResetFlags(rawValue: 1 << 0)
    static let clarity = ResetFlags(rawValue: 1 << 1)
    static let deMud = ResetFlags(rawValue: 1 << 2)
    static let eq = ResetFlags(rawValue: 1 << 3)
    static let tenBandEQ = ResetFlags(rawValue: 1 << 4)
    static let compressor = ResetFlags(rawValue: 1 << 5)
    static let reverb = ResetFlags(rawValue: 1 << 6)
    static let delay = ResetFlags(rawValue: 1 << 7)
    static let chorus = ResetFlags(rawValue: 1 << 8)
    static let flanger = ResetFlags(rawValue: 1 << 9)
    static let phaser = ResetFlags(rawValue: 1 << 10)
    static let bitcrusher = ResetFlags(rawValue: 1 << 11)
    static let all = ResetFlags(rawValue: 1 << 12)
}

struct RubberBandScratch {
    var interleaved: [Float]
    var output: [Float]
    var capacity: Int
    var channelCount: Int

    init() {
        self.interleaved = []
        self.output = []
        self.capacity = 0
        self.channelCount = 0
    }
}

class AudioEngine: ObservableObject {
    let engine = AVAudioEngine()
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var inputDeviceName: String = "Searching..."
    @Published var outputDeviceName: String = "Searching..."
    @Published var signalFlowToken: Int = 0

    init() {
        setupNotifications()
        refreshOutputDevices()
        updateProcessingSnapshot()
    }

    // Pitch Shift effect (Nightcore) - now uses AVAudioUnitTimePitch
    @Published var nightcoreEnabled = false {
        didSet {
            if !nightcoreEnabled && !clarityEnabled {
                resetClarityState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var nightcoreIntensity: Double = 0.6 { // 0 to 1, maps to 0 to +12 semitones
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    @Published var bassBoostEnabled = false {
        didSet {
            // Debug output removed.
            if !bassBoostEnabled {
                resetBassBoostState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var bassBoostAmount: Double = 0.6 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Clarity effect
    @Published var clarityEnabled = false {
        didSet {
            if !clarityEnabled && !nightcoreEnabled {
                resetClarityState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var clarityAmount: Double = 0.5 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Reverb effect
    @Published var reverbEnabled = false {
        didSet {
            if !reverbEnabled {
                resetReverbState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var reverbMix: Double = 0.3 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var reverbSize: Double = 0.5 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Compressor effect
    @Published var compressorEnabled = false {
        didSet {
            if !compressorEnabled {
                resetCompressorState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var compressorStrength: Double = 0.4 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Stereo width effect
    @Published var stereoWidthEnabled = false {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var stereoWidthAmount: Double = 0.3 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Simple EQ effect
    @Published var simpleEQEnabled = false {
        didSet {
            if !simpleEQEnabled {
                resetEQState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var eqBass: Double = 0 { // -1 to 1
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var eqMids: Double = 0 { // -1 to 1
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var eqTreble: Double = 0 { // -1 to 1
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // 10-Band EQ
    @Published var tenBandEQEnabled = false {
        didSet {
            if !tenBandEQEnabled {
                resetTenBandEQState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var tenBand31: Double = 0 {
        didSet { scheduleSnapshotUpdate() }
    }
    @Published var tenBand62: Double = 0 {
        didSet { scheduleSnapshotUpdate() }
    }
    @Published var tenBand125: Double = 0 {
        didSet { scheduleSnapshotUpdate() }
    }
    @Published var tenBand250: Double = 0 {
        didSet { scheduleSnapshotUpdate() }
    }
    @Published var tenBand500: Double = 0 {
        didSet { scheduleSnapshotUpdate() }
    }
    @Published var tenBand1k: Double = 0 {
        didSet { scheduleSnapshotUpdate() }
    }
    @Published var tenBand2k: Double = 0 {
        didSet { scheduleSnapshotUpdate() }
    }
    @Published var tenBand4k: Double = 0 {
        didSet { scheduleSnapshotUpdate() }
    }
    @Published var tenBand8k: Double = 0 {
        didSet { scheduleSnapshotUpdate() }
    }
    @Published var tenBand16k: Double = 0 {
        didSet { scheduleSnapshotUpdate() }
    }

    // De-mud effect
    @Published var deMudEnabled = false {
        didSet {
            if !deMudEnabled {
                resetDeMudState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var deMudStrength: Double = 0.5 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Delay effect
    @Published var delayEnabled = false {
        didSet {
            if !delayEnabled {
                resetDelayState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var delayTime: Double = 0.25 { // seconds (0.01 to 2.0)
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var delayFeedback: Double = 0.4 { // 0 to 1
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var delayMix: Double = 0.3 { // 0 to 1
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Distortion effect
    @Published var distortionEnabled = false {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var distortionDrive: Double = 0.5 { // 0 to 1
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var distortionMix: Double = 0.5 { // 0 to 1
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Tremolo effect
    @Published var tremoloEnabled = false {
        didSet {
            if !tremoloEnabled {
                tremoloPhase = 0
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var tremoloRate: Double = 5.0 { // Hz (0.1 to 20)
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var tremoloDepth: Double = 0.5 { // 0 to 1
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Chorus effect
    @Published var chorusEnabled = false {
        didSet {
            if !chorusEnabled {
                resetChorusState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var chorusRate: Double = 0.8 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var chorusDepth: Double = 0.4 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var chorusMix: Double = 0.35 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Phaser effect
    @Published var phaserEnabled = false {
        didSet {
            if !phaserEnabled {
                resetPhaserState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var phaserRate: Double = 0.6 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var phaserDepth: Double = 0.5 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Flanger effect
    @Published var flangerEnabled = false {
        didSet {
            if !flangerEnabled {
                resetFlangerState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var flangerRate: Double = 0.6 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var flangerDepth: Double = 0.4 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var flangerFeedback: Double = 0.25 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var flangerMix: Double = 0.4 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Bitcrusher effect
    @Published var bitcrusherEnabled = false {
        didSet {
            if !bitcrusherEnabled {
                resetBitcrusherState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var bitcrusherBitDepth: Double = 8 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var bitcrusherDownsample: Double = 4 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var bitcrusherMix: Double = 0.6 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Tape saturation effect
    @Published var tapeSaturationEnabled = false {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var tapeSaturationDrive: Double = 0.35 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var tapeSaturationMix: Double = 0.5 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    // Resampling effect (pitch+speed)
    @Published var resampleEnabled = false {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var resampleRate: Double = 1.0 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var resampleCrossfade: Double = 0.3 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    @Published var rubberBandPitchEnabled = false {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var rubberBandPitchSemitones: Double = 0.0 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    @Published var processingEnabled = true {
        didSet {
            if !processingEnabled {
                resetEffectState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var limiterEnabled = true {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    @Published var effectLevels: [UUID: Float] = [:]

    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedOutputDeviceID: AudioDeviceID? {
        didSet {
            if let deviceID = selectedOutputDeviceID {
                outputVolume = getOutputDeviceVolume(deviceID: deviceID)
            }
            if isRunning {
                reconfigureAudio()
            }
        }
    }
    @Published var outputVolume: Float = 1.0 {
        didSet {
            if let deviceID = selectedOutputDeviceID ?? outputDeviceID {
                setOutputDeviceVolume(deviceID: deviceID, volume: outputVolume)
            }
            if let queue = outputQueue {
                AudioQueueSetParameter(queue, kAudioQueueParam_Volume, outputVolume)
            }
        }
    }
    @Published var setupReady = true
    @Published var pendingGraphSnapshot: GraphSnapshot?

    var currentGraphSnapshot: GraphSnapshot?

    var outputQueue: AudioQueueRef?
    var outputDeviceID: AudioDeviceID?
    var outputQueueStarted = false
    let outputQueueStartLock = NSLock()
    var chainLogTimer: DispatchSourceTimer?
    var setupMonitorTimer: DispatchSourceTimer?

    // Store original devices before switching to BlackHole
    var originalInputDeviceID: AudioDeviceID?
    var originalOutputDeviceID: AudioDeviceID?
    var nightcoreRestartWorkItem: DispatchWorkItem?
    var effectChainOrder: [BeginnerNode] = []
    var manualGraphNodes: [BeginnerNode] = []
    var manualGraphConnections: [BeginnerConnection] = []
    var manualGraphStartID: UUID?
    var manualGraphEndID: UUID?
    var manualGraphAutoConnectEnd: Bool = true
    var useManualGraph = false
    var splitLeftNodes: [BeginnerNode] = []
    var splitLeftConnections: [BeginnerConnection] = []
    var splitLeftStartID: UUID?
    var splitLeftEndID: UUID?
    var splitRightNodes: [BeginnerNode] = []
    var splitRightConnections: [BeginnerConnection] = []
    var splitRightStartID: UUID?
    var splitRightEndID: UUID?
    var splitAutoConnectEnd: Bool = true
    var useSplitGraph = false
    var nodeParameters: [UUID: NodeEffectParameters] = [:]
    var nodeEnabled: [UUID: Bool] = [:]
    var levelUpdateCounter = 0
    let effectStateLock = NSLock()
    private let snapshotLock = NSLock()
    private var snapshotUpdateScheduled = false
    private var processingSnapshot = ProcessingSnapshot.empty
    var pendingResets: ResetFlags = []
    var isReconfiguring = false
    var restartWorkItem: DispatchWorkItem?
    let restartDebounceInterval: TimeInterval = 0.25

    // Bass boost state
    var bassBoostState: [BiquadState] = []
    var bassBoostCoefficients = BiquadCoefficients()
    var bassBoostLastSampleRate: Double = 0
    var bassBoostLastAmount: Double = -1
    var bassBoostStatesByNode: [UUID: [BiquadState]] = [:]

    // Clarity state (high shelf boost)
    var clarityState: [BiquadState] = []
    var clarityCoefficients = BiquadCoefficients()
    var clarityLastSampleRate: Double = 0
    var clarityLastAmount: Double = -1
    var clarityStatesByNode: [UUID: [BiquadState]] = [:]
    var nightcoreStatesByNode: [UUID: [BiquadState]] = [:]

    // De-mud state (mid frequency cut)
    var deMudState: [BiquadState] = []
    var deMudCoefficients = BiquadCoefficients()
    var deMudLastSampleRate: Double = 0
    var deMudLastStrength: Double = -1
    var deMudStatesByNode: [UUID: [BiquadState]] = [:]

    // Simple EQ state (3 bands)
    var eqBassState: [BiquadState] = []
    var eqBassCoefficients = BiquadCoefficients()
    var eqMidsState: [BiquadState] = []
    var eqMidsCoefficients = BiquadCoefficients()
    var eqTrebleState: [BiquadState] = []
    var eqTrebleCoefficients = BiquadCoefficients()
    var eqLastSampleRate: Double = 0
    var eqBassStatesByNode: [UUID: [BiquadState]] = [:]
    var eqMidsStatesByNode: [UUID: [BiquadState]] = [:]
    var eqTrebleStatesByNode: [UUID: [BiquadState]] = [:]

    // 10-band EQ state (peaking filters)
    let tenBandFrequencies: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    var tenBandStates: [[BiquadState]] = []
    var tenBandCoefficients: [BiquadCoefficients] = []
    var tenBandLastSampleRate: Double = 0
    var tenBandLastGains: [Double] = []
    var tenBandStatesByNode: [UUID: [[BiquadState]]] = [:]

    // Compressor state (simple dynamic range compression)
    var compressorEnvelope: [Float] = []

    // Reverb buffer (simple delay-based reverb)
    var reverbBuffer: [[Float]] = []
    var reverbWriteIndex = 0
    var reverbBuffersByNode: [UUID: [[Float]]] = [:]
    var reverbWriteIndexByNode: [UUID: Int] = [:]

    // Delay buffer (circular buffer for echo)
    var delayBuffer: [[Float]] = []
    var delayWriteIndex = 0
    var delayBuffersByNode: [UUID: [[Float]]] = [:]
    var delayWriteIndexByNode: [UUID: Int] = [:]

    // Tremolo state (LFO phase)
    var tremoloPhase: Double = 0
    var tremoloPhaseByNode: [UUID: Double] = [:]

    // Chorus state (delay modulation)
    var chorusBuffer: [[Float]] = []
    var chorusWriteIndex = 0
    var chorusPhase: Double = 0
    var chorusBuffersByNode: [UUID: [[Float]]] = [:]
    var chorusWriteIndexByNode: [UUID: Int] = [:]
    var chorusPhaseByNode: [UUID: Double] = [:]

    // Flanger state (short delay modulation with feedback)
    var flangerBuffer: [[Float]] = []
    var flangerWriteIndex = 0
    var flangerPhase: Double = 0
    var flangerBuffersByNode: [UUID: [[Float]]] = [:]
    var flangerWriteIndexByNode: [UUID: Int] = [:]
    var flangerPhaseByNode: [UUID: Double] = [:]

    // Phaser state (all-pass)
    let phaserStageCount = 2
    var phaserStates: [[AllPassState]] = []
    var phaserStatesByNode: [UUID: [[AllPassState]]] = [:]
    var phaserPhase: Double = 0
    var phaserPhaseByNode: [UUID: Double] = [:]

    // Resampling state
    var resampleBuffer: [[Float]] = []
    var resampleWriteIndex = 0
    var resampleReadPhase: Double = 0
    var resampleCrossfadeRemaining = 0
    var resampleCrossfadeTotal = 0
    var resampleCrossfadeStartPhase: Double = 0
    var resampleCrossfadeTargetPhase: Double = 0
    var resampleBuffersByNode: [UUID: [[Float]]] = [:]
    var resampleWriteIndexByNode: [UUID: Int] = [:]
    var resampleReadPhaseByNode: [UUID: Double] = [:]
    var resampleCrossfadeRemainingByNode: [UUID: Int] = [:]
    var resampleCrossfadeTotalByNode: [UUID: Int] = [:]
    var resampleCrossfadeStartPhaseByNode: [UUID: Double] = [:]
    var resampleCrossfadeTargetPhaseByNode: [UUID: Double] = [:]

    // Rubber Band state
    var rubberBandNodes: [UUID: RubberBandWrapper] = [:]
    var rubberBandGlobalByType: [EffectType: RubberBandWrapper] = [:]
    var rubberBandScratchByNode: [UUID: RubberBandScratch] = [:]
    var rubberBandScratchGlobal = RubberBandScratch()

    // Bitcrusher state
    var bitcrusherHoldCounters: [Int] = []
    var bitcrusherHoldValues: [Float] = []
    var bitcrusherHoldCountersByNode: [UUID: [Int]] = [:]
    var bitcrusherHoldValuesByNode: [UUID: [Float]] = [:]

    // Pre-allocated buffers
    var interleavedOutputBuffer: [Float] = []
    var interleavedOutputCapacity: Int = 0
    var processingBuffer: [[Float]] = []
    var processingFrameCapacity: Int = 0

    // Ring buffer for audio data (interleaved frames)
    var ringBuffer: UnsafeMutablePointer<Float>?
    var ringBufferFrameSize: Int = 0
    var ringBufferCapacity: Int = 0
    var ringWriteIndex: Int = 0
    var ringReadIndex: Int = 0
    let ringBufferLock = NSLock()
    let maxRingBufferSize = 10

    // Audio format: 48kHz, stereo, Float32 (matches what we're seeing in console)
    let audioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 2,
        interleaved: false
    )!

    func scheduleSnapshotUpdate() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleSnapshotUpdate()
            }
            return
        }
        guard !snapshotUpdateScheduled else { return }
        snapshotUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.snapshotUpdateScheduled = false
            self.updateProcessingSnapshot()
        }
    }

    private func updateProcessingSnapshot() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateProcessingSnapshot()
            }
            return
        }

        var chain: [BeginnerNode] = []
        var manualNodes: [BeginnerNode] = []
        var manualConnections: [BeginnerConnection] = []
        var manualStartID: UUID?
        var manualEndID: UUID?
        var manualAutoConnect = true
        var splitLeftNodes: [BeginnerNode] = []
        var splitLeftConnections: [BeginnerConnection] = []
        var splitLeftStartID: UUID?
        var splitLeftEndID: UUID?
        var splitRightNodes: [BeginnerNode] = []
        var splitRightConnections: [BeginnerConnection] = []
        var splitRightStartID: UUID?
        var splitRightEndID: UUID?
        var splitAutoConnect = true
        var localUseManualGraph = false
        var localUseSplitGraph = false
        var localNodeParameters: [UUID: NodeEffectParameters] = [:]
        var localNodeEnabled: [UUID: Bool] = [:]

        withEffectStateLock {
            chain = effectChainOrder
            manualNodes = manualGraphNodes
            manualConnections = manualGraphConnections
            manualStartID = manualGraphStartID
            manualEndID = manualGraphEndID
            manualAutoConnect = manualGraphAutoConnectEnd
            splitLeftNodes = self.splitLeftNodes
            splitLeftConnections = self.splitLeftConnections
            splitLeftStartID = self.splitLeftStartID
            splitLeftEndID = self.splitLeftEndID
            splitRightNodes = self.splitRightNodes
            splitRightConnections = self.splitRightConnections
            splitRightStartID = self.splitRightStartID
            splitRightEndID = self.splitRightEndID
            splitAutoConnect = splitAutoConnectEnd
            localUseManualGraph = useManualGraph
            localUseSplitGraph = useSplitGraph
            localNodeParameters = nodeParameters
            localNodeEnabled = nodeEnabled
        }

        let chainOrder = chain.map { EffectNode(id: $0.id, type: $0.type) }

        let snapshot = ProcessingSnapshot(
            useSplitGraph: localUseSplitGraph,
            useManualGraph: localUseManualGraph,
            splitLeftNodes: splitLeftNodes,
            splitLeftConnections: splitLeftConnections,
            splitLeftStartID: splitLeftStartID,
            splitLeftEndID: splitLeftEndID,
            splitRightNodes: splitRightNodes,
            splitRightConnections: splitRightConnections,
            splitRightStartID: splitRightStartID,
            splitRightEndID: splitRightEndID,
            splitAutoConnectEnd: splitAutoConnect,
            manualGraphNodes: manualNodes,
            manualGraphConnections: manualConnections,
            manualGraphStartID: manualStartID,
            manualGraphEndID: manualEndID,
            manualGraphAutoConnectEnd: manualAutoConnect,
            effectChainOrder: chainOrder,
            nodeParameters: localNodeParameters,
            nodeEnabled: localNodeEnabled,
            processingEnabled: processingEnabled,
            limiterEnabled: limiterEnabled,
            isReconfiguring: isReconfiguring,
            bassBoostEnabled: bassBoostEnabled,
            bassBoostAmount: bassBoostAmount,
            nightcoreEnabled: nightcoreEnabled,
            nightcoreIntensity: nightcoreIntensity,
            clarityEnabled: clarityEnabled,
            clarityAmount: clarityAmount,
            deMudEnabled: deMudEnabled,
            deMudStrength: deMudStrength,
            simpleEQEnabled: simpleEQEnabled,
            eqBass: eqBass,
            eqMids: eqMids,
            eqTreble: eqTreble,
            tenBandEQEnabled: tenBandEQEnabled,
            tenBandGains: tenBandGains,
            compressorEnabled: compressorEnabled,
            compressorStrength: compressorStrength,
            reverbEnabled: reverbEnabled,
            reverbMix: reverbMix,
            reverbSize: reverbSize,
            delayEnabled: delayEnabled,
            delayTime: delayTime,
            delayFeedback: delayFeedback,
            delayMix: delayMix,
            distortionEnabled: distortionEnabled,
            distortionDrive: distortionDrive,
            distortionMix: distortionMix,
            tremoloEnabled: tremoloEnabled,
            tremoloRate: tremoloRate,
            tremoloDepth: tremoloDepth,
            chorusEnabled: chorusEnabled,
            chorusRate: chorusRate,
            chorusDepth: chorusDepth,
            chorusMix: chorusMix,
            phaserEnabled: phaserEnabled,
            phaserRate: phaserRate,
            phaserDepth: phaserDepth,
            flangerEnabled: flangerEnabled,
            flangerRate: flangerRate,
            flangerDepth: flangerDepth,
            flangerFeedback: flangerFeedback,
            flangerMix: flangerMix,
            bitcrusherEnabled: bitcrusherEnabled,
            bitcrusherBitDepth: bitcrusherBitDepth,
            bitcrusherDownsample: bitcrusherDownsample,
            bitcrusherMix: bitcrusherMix,
            tapeSaturationEnabled: tapeSaturationEnabled,
            tapeSaturationDrive: tapeSaturationDrive,
            tapeSaturationMix: tapeSaturationMix,
            stereoWidthEnabled: stereoWidthEnabled,
            stereoWidthAmount: stereoWidthAmount,
            resampleEnabled: resampleEnabled,
            resampleRate: resampleRate,
            resampleCrossfade: resampleCrossfade,
            rubberBandPitchEnabled: rubberBandPitchEnabled,
            rubberBandPitchSemitones: rubberBandPitchSemitones
        )

        snapshotLock.lock()
        processingSnapshot = snapshot
        snapshotLock.unlock()
    }

    func currentProcessingSnapshot() -> ProcessingSnapshot {
        snapshotLock.lock()
        let snapshot = processingSnapshot
        snapshotLock.unlock()
        return snapshot
    }

    func enqueueReset(_ reset: ResetFlags) {
        withEffectStateLock {
            pendingResets.insert(reset)
        }
    }

    deinit {
        // Stop audio queue before deallocation to prevent callback accessing freed memory
        if let queue = outputQueue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // Clean up ring buffer
        ringBufferLock.lock()
        if let buffer = ringBuffer {
            buffer.deallocate()
        }
        ringBufferLock.unlock()

        NotificationCenter.default.removeObserver(self)
    }

}
