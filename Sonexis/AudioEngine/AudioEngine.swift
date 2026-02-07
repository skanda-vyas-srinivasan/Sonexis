import AVFoundation
import Combine
import CoreAudio
import AudioToolbox
import os

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
    let enhancerEnabled: Bool
    let enhancerAmount: Double
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
    let graphSignature: Int

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
        enhancerEnabled: false,
        enhancerAmount: 0,
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
        rubberBandPitchSemitones: 0,
        graphSignature: 0
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
    var engine = AVAudioEngine()
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var inputDeviceName: String = "Searching..."
    @Published var outputDeviceName: String = "Searching..."
    @Published var signalFlowToken: Int = 0
    @Published var betaRecordingUnlocked = false
    @Published var isRecording = false
    @Published var pluginStatusToken: Int = 0

    private var recordingFile: AVAudioFile?
    private let recordingLock = NSLock()
    private var recordingSampleRate: Double = 44100
    private var recordingChannelCount: AVAudioChannelCount = 2
    private var recordingFormat: AVAudioFormat?
    private var recordingBuffer: AVAudioPCMBuffer?
    private var recordingFrameCapacity: Int = 0
    private var tapFrameLength: Int = 0
    private var tapChannelCount: Int = 0
    private var tapSampleRate: Double = 0

    init() {
        setupNotifications()
        refreshOutputDevices()
        updateProcessingSnapshot()
        startDeviceListMonitor()
        pluginHost.onPluginReady = { [weak self] _ in
            DispatchQueue.main.async {
                self?.pluginStatusToken += 1
            }
        }
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

    // Enhancer effect
    @Published var enhancerEnabled = false {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var enhancerAmount: Double = 0.4 {
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
    var setupMonitorListener: AudioObjectPropertyListenerBlock?
    let setupMonitorQueue = DispatchQueue(label: "AudioEngine.SetupMonitor", qos: .utility)
    var deviceListMonitorTimer: DispatchSourceTimer?
    var deviceListMonitorListener: AudioObjectPropertyListenerBlock?
    let deviceListMonitorQueue = DispatchQueue(label: "AudioEngine.DeviceListMonitor", qos: .utility)

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
    let pluginHost = PluginHost()
    var levelUpdateCounter = 0
    let effectStateLock = NSLock()
    private let snapshotLock = NSLock()
    private var snapshotUpdateScheduled = false
    private var processingSnapshot = ProcessingSnapshot.empty
    var pendingResets: ResetFlags = []
    let pendingResetsLock = NSLock()
    var isReconfiguring = false
    var restartWorkItem: DispatchWorkItem?
    let restartDebounceInterval: TimeInterval = 0.25

    // Bass boost state
    var bassBoostState: [BiquadState] = []
    var bassBoostCoefficients = BiquadCoefficients()
    var bassBoostLastSampleRate: Double = 0
    var bassBoostLastAmount: Double = -1
    var bassBoostStatesByNode: [UUID: [BiquadState]] = [:]
    var bassBoostSmoothedGain: Float = 0
    var bassBoostSmoothedGainByNode: [UUID: Float] = [:]
    // vDSP biquad delay states (4 floats per channel)
    var bassBoostVDSPDelay: [[Float]] = []
    var bassBoostVDSPDelayByNode: [UUID: [[Float]]] = [:]
    var biquadScratchBuffer: [Float] = []  // Scratch for wet signal
    var biquadScratchBuffer2: [Float] = [] // Second scratch for multi-band EQ

    // Enhancer state
    var enhancerSmoothedGain: Float = 0
    var enhancerSmoothedGainByNode: [UUID: Float] = [:]
    var enhancerLowVDSPDelay: [[Float]] = []
    var enhancerMidVDSPDelay: [[Float]] = []
    var enhancerHighVDSPDelay: [[Float]] = []
    var enhancerLowVDSPDelayByNode: [UUID: [[Float]]] = [:]
    var enhancerMidVDSPDelayByNode: [UUID: [[Float]]] = [:]
    var enhancerHighVDSPDelayByNode: [UUID: [[Float]]] = [:]


    // Clarity state (high shelf boost)
    var clarityState: [BiquadState] = []
    var clarityCoefficients = BiquadCoefficients()
    var clarityLastSampleRate: Double = 0
    var clarityLastAmount: Double = -1
    var clarityStatesByNode: [UUID: [BiquadState]] = [:]
    var claritySmoothedGain: Float = 0
    var claritySmoothedGainByNode: [UUID: Float] = [:]
    var clarityVDSPDelay: [[Float]] = []
    var clarityVDSPDelayByNode: [UUID: [[Float]]] = [:]
    var nightcoreStatesByNode: [UUID: [BiquadState]] = [:]
    var nightcoreSmoothedGain: Float = 0
    var nightcoreSmoothedGainByNode: [UUID: Float] = [:]

    // De-mud state (mid frequency cut)
    var deMudState: [BiquadState] = []
    var deMudCoefficients = BiquadCoefficients()
    var deMudLastSampleRate: Double = 0
    var deMudLastStrength: Double = -1
    var deMudStatesByNode: [UUID: [BiquadState]] = [:]
    var deMudSmoothedGain: Float = 0
    var deMudSmoothedGainByNode: [UUID: Float] = [:]
    var deMudVDSPDelay: [[Float]] = []
    var deMudVDSPDelayByNode: [UUID: [[Float]]] = [:]

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
    var eqBassVDSPDelay: [[Float]] = []
    var eqMidsVDSPDelay: [[Float]] = []
    var eqTrebleVDSPDelay: [[Float]] = []
    var eqBassVDSPDelayByNode: [UUID: [[Float]]] = [:]
    var eqMidsVDSPDelayByNode: [UUID: [[Float]]] = [:]
    var eqTrebleVDSPDelayByNode: [UUID: [[Float]]] = [:]
    var eqTrebleStatesByNode: [UUID: [BiquadState]] = [:]
    var simpleEQSmoothedGain: Float = 0
    var simpleEQSmoothedGainByNode: [UUID: Float] = [:]

    // 10-band EQ state (peaking filters)
    let tenBandFrequencies: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    var tenBandStates: [[BiquadState]] = []
    var tenBandCoefficients: [BiquadCoefficients] = []
    var tenBandLastSampleRate: Double = 0
    var tenBandLastGains: [Double] = []
    var tenBandStatesByNode: [UUID: [[BiquadState]]] = [:]
    var tenBandEQSmoothedGain: Float = 0
    var tenBandEQSmoothedGainByNode: [UUID: Float] = [:]
    // vDSP delays: [band][channel][4 floats]
    var tenBandVDSPDelays: [[[Float]]] = []
    var tenBandVDSPDelaysByNode: [UUID: [[[Float]]]] = [:]

    // Compressor state (simple dynamic range compression)
    var compressorEnvelope: [Float] = []
    var compressorSmoothedGain: Float = 0
    var compressorSmoothedGainByNode: [UUID: Float] = [:]

    // Reverb buffer (simple delay-based reverb)
    var reverbBuffer: [[Float]] = []
    var reverbWriteIndex = 0
    var reverbBuffersByNode: [UUID: [[Float]]] = [:]
    var reverbWriteIndexByNode: [UUID: Int] = [:]
    var reverbSmoothedGain: Float = 0
    var reverbSmoothedGainByNode: [UUID: Float] = [:]

    // Delay buffer (circular buffer for echo)
    var delayBuffer: [[Float]] = []
    var delayWriteIndex = 0
    var delayBuffersByNode: [UUID: [[Float]]] = [:]
    var delayWriteIndexByNode: [UUID: Int] = [:]
    var delaySmoothedGain: Float = 0
    var delaySmoothedGainByNode: [UUID: Float] = [:]

    // Tremolo state (LFO phase)
    var tremoloPhase: Double = 0
    var tremoloPhaseByNode: [UUID: Double] = [:]
    var tremoloSmoothedGain: Float = 0
    var tremoloSmoothedGainByNode: [UUID: Float] = [:]

    // Chorus state (delay modulation)
    var chorusBuffer: [[Float]] = []
    var chorusWriteIndex = 0
    var chorusPhase: Double = 0
    var chorusBuffersByNode: [UUID: [[Float]]] = [:]
    var chorusWriteIndexByNode: [UUID: Int] = [:]
    var chorusPhaseByNode: [UUID: Double] = [:]
    var chorusSmoothedGain: Float = 0
    var chorusSmoothedGainByNode: [UUID: Float] = [:]

    // Flanger state (short delay modulation with feedback)
    var flangerBuffer: [[Float]] = []
    var flangerWriteIndex = 0
    var flangerPhase: Double = 0
    var flangerBuffersByNode: [UUID: [[Float]]] = [:]
    var flangerWriteIndexByNode: [UUID: Int] = [:]
    var flangerPhaseByNode: [UUID: Double] = [:]
    var flangerSmoothedGain: Float = 0
    var flangerSmoothedGainByNode: [UUID: Float] = [:]

    // Phaser state (all-pass)
    let phaserStageCount = 2
    var phaserStates: [[AllPassState]] = []
    var phaserStatesByNode: [UUID: [[AllPassState]]] = [:]
    var phaserPhase: Double = 0
    var phaserPhaseByNode: [UUID: Double] = [:]
    var phaserSmoothedGain: Float = 0
    var phaserSmoothedGainByNode: [UUID: Float] = [:]

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
    var resampleSmoothedGain: Float = 0
    var resampleSmoothedGainByNode: [UUID: Float] = [:]

    // Rubber Band state
    var rubberBandNodes: [UUID: RubberBandWrapper] = [:]
    var rubberBandGlobalByType: [EffectType: RubberBandWrapper] = [:]
    var rubberBandScratchByNode: [UUID: RubberBandScratch] = [:]
    var rubberBandScratchGlobal = RubberBandScratch()
    var rubberBandSmoothedGain: Float = 0
    var rubberBandSmoothedGainByNode: [UUID: Float] = [:]

    // Bitcrusher state
    var bitcrusherHoldCounters: [Int] = []
    var bitcrusherHoldValues: [Float] = []
    var bitcrusherHoldCountersByNode: [UUID: [Int]] = [:]
    var bitcrusherHoldValuesByNode: [UUID: [Float]] = [:]
    var bitcrusherSmoothedGain: Float = 0
    var bitcrusherSmoothedGainByNode: [UUID: Float] = [:]

    // Distortion state (stateless effect, but needs smoothing)
    var distortionSmoothedGain: Float = 0
    var distortionSmoothedGainByNode: [UUID: Float] = [:]

    // Tape Saturation state
    var tapeSaturationSmoothedGain: Float = 0
    var tapeSaturationSmoothedGainByNode: [UUID: Float] = [:]

    // Stereo Width state
    var stereoWidthSmoothedGain: Float = 0
    var stereoWidthSmoothedGainByNode: [UUID: Float] = [:]

    // Plugin crossfade state
    var pluginDryScratchByNode: [UUID: [[Float]]] = [:]
    var pluginWetScratchByNode: [UUID: [[Float]]] = [:]
    var pluginCrossfadeRemainingByNode: [UUID: Int] = [:]
    var pluginCrossfadeTotalByNode: [UUID: Int] = [:]
    var pluginCrossfadeOutRemainingByNode: [UUID: Int] = [:]
    var pluginCrossfadeOutTotalByNode: [UUID: Int] = [:]
    var pluginWasEnabledByNode: [UUID: Bool] = [:]
    var pluginWasReadyByNode: [UUID: Bool] = [:]

    // Pre-allocated buffers
    var interleavedOutputBuffer: [Float] = []
    var interleavedOutputCapacity: Int = 0
    var processingBuffer: [[Float]] = []
    var processingFrameCapacity: Int = 0
    var deinterleavedInputBuffer: [[Float]] = []
    var deinterleavedInputCapacity: Int = 0
    // Graph processing scratch buffers (reused to avoid allocations)
    var graphOutEdges: [UUID: [UUID]] = [:]
    var graphInEdges: [UUID: [(UUID, Double)]] = [:]
    var graphOutputBuffers: [UUID: [[Float]]] = [:]
    var graphIndegree: [UUID: Int] = [:]
    var graphQueue: [UUID] = []
    var graphTransitionSamplesRemaining: Int = 0
    var graphTransitionSamplesTotal: Int = 0
    var graphTransitionFromManual: Bool = false
    var lastUseManualGraph: Bool = false
    var lastGraphSignature: Int = 0
    var graphChangeSamplesRemaining: Int = 0
    var graphChangeSamplesTotal: Int = 0
    var graphChangePrevOutput: [[Float]] = []
    var lastOutputBuffer: [[Float]] = []

    // Ring buffer for audio data (interleaved frames)
    var ringBuffer: UnsafeMutablePointer<Float>?
    var ringBufferFrameSize: Int = 0
    var ringBufferCapacity: Int = 0
    var ringWriteIndex: Int = 0
    var ringReadIndex: Int = 0
    var ringBufferLock = os_unfair_lock()  // Real-time safe lock (no priority inversion)
    let maxRingBufferSize = 10

    // Track whether we have a retained reference in the AudioQueue callback
    var audioQueueRetainedSelf = false

    // Audio format: 48kHz, stereo, Float32 (matches what we're seeing in console)
    let audioFormat: AVAudioFormat? = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 2,
        interleaved: false
    )

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
        let graphSignature = computeGraphSignature(
            manualNodes: manualNodes,
            manualConnections: manualConnections,
            manualStartID: manualStartID,
            manualEndID: manualEndID,
            splitLeftNodes: splitLeftNodes,
            splitLeftConnections: splitLeftConnections,
            splitLeftStartID: splitLeftStartID,
            splitLeftEndID: splitLeftEndID,
            splitRightNodes: splitRightNodes,
            splitRightConnections: splitRightConnections,
            splitRightStartID: splitRightStartID,
            splitRightEndID: splitRightEndID,
            chainOrder: chainOrder,
            nodeEnabled: localNodeEnabled
        )

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
            enhancerEnabled: enhancerEnabled,
            enhancerAmount: enhancerAmount,
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
            rubberBandPitchSemitones: rubberBandPitchSemitones,
            graphSignature: graphSignature
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

    private func computeGraphSignature(
        manualNodes: [BeginnerNode],
        manualConnections: [BeginnerConnection],
        manualStartID: UUID?,
        manualEndID: UUID?,
        splitLeftNodes: [BeginnerNode],
        splitLeftConnections: [BeginnerConnection],
        splitLeftStartID: UUID?,
        splitLeftEndID: UUID?,
        splitRightNodes: [BeginnerNode],
        splitRightConnections: [BeginnerConnection],
        splitRightStartID: UUID?,
        splitRightEndID: UUID?,
        chainOrder: [EffectNode],
        nodeEnabled: [UUID: Bool]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(manualStartID)
        hasher.combine(manualEndID)
        for node in manualNodes {
            hasher.combine(node.id)
            hasher.combine(node.type.rawValue)
            hasher.combine(nodeEnabled[node.id] ?? true)
        }
        for connection in manualConnections {
            hasher.combine(connection.fromNodeId)
            hasher.combine(connection.toNodeId)
            hasher.combine(connection.gain)
        }
        hasher.combine(splitLeftStartID)
        hasher.combine(splitLeftEndID)
        for node in splitLeftNodes {
            hasher.combine(node.id)
            hasher.combine(node.type.rawValue)
            hasher.combine(nodeEnabled[node.id] ?? true)
        }
        for connection in splitLeftConnections {
            hasher.combine(connection.fromNodeId)
            hasher.combine(connection.toNodeId)
            hasher.combine(connection.gain)
        }
        hasher.combine(splitRightStartID)
        hasher.combine(splitRightEndID)
        for node in splitRightNodes {
            hasher.combine(node.id)
            hasher.combine(node.type.rawValue)
            hasher.combine(nodeEnabled[node.id] ?? true)
        }
        for connection in splitRightConnections {
            hasher.combine(connection.fromNodeId)
            hasher.combine(connection.toNodeId)
            hasher.combine(connection.gain)
        }
        for node in chainOrder {
            hasher.combine(node.id)
            hasher.combine(node.type.rawValue)
            if let id = node.id {
                hasher.combine(nodeEnabled[id] ?? true)
            }
        }
        return hasher.finalize()
    }

    func enqueueReset(_ reset: ResetFlags) {
        pendingResetsLock.lock()
        pendingResets.insert(reset)
        pendingResetsLock.unlock()
    }

    func updateRecordingFormat(sampleRate: Double, channelCount: AVAudioChannelCount) {
        recordingLock.lock()
        recordingSampleRate = sampleRate
        recordingChannelCount = channelCount
        recordingLock.unlock()
    }

    func updateTapFormat(frameLength: Int, channelCount: Int, sampleRate: Double) {
        recordingLock.lock()
        tapFrameLength = frameLength
        tapChannelCount = channelCount
        tapSampleRate = sampleRate
        recordingLock.unlock()
    }

    func isRecordingActive() -> Bool {
        recordingLock.lock()
        let active = isRecording
        recordingLock.unlock()
        return active
    }

    func startRecording(url: URL) {
        recordingLock.lock()
        if isRecording {
            recordingLock.unlock()
            return
        }
        let targetSampleRate = recordingSampleRate
        let targetChannelCount = recordingChannelCount
        let targetFrameLength = tapFrameLength
        recordingLock.unlock()

        guard targetFrameLength > 0 else {
            errorMessage = "Recording is not ready yet. Start audio first."
            return
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: false
        ) else {
            errorMessage = "Unable to create recording format."
            return
        }

        do {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(targetFrameLength)
            ) else {
                errorMessage = "Unable to create recording buffer."
                return
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            recordingLock.lock()
            recordingFile = file
            recordingFormat = format
            recordingBuffer = buffer
            recordingFrameCapacity = targetFrameLength
            isRecording = true
            recordingLock.unlock()
        } catch {
            errorMessage = "Recording failed: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        recordingLock.lock()
        recordingFile = nil
        recordingFormat = nil
        recordingBuffer = nil
        recordingFrameCapacity = 0
        isRecording = false
        recordingLock.unlock()
    }

    func recordIfNeeded(
        _ buffer: [[Float]],
        frameLength: Int,
        channelCount: Int,
        sampleRate: Double
    ) {
        recordingLock.lock()
        let active = isRecording
        let targetSampleRate = recordingSampleRate
        let targetChannelCount = recordingChannelCount
        let cachedFormat = recordingFormat
        let cachedBuffer = recordingBuffer
        recordingLock.unlock()
        guard active else { return }
        guard channelCount > 0, frameLength > 0 else { return }

        if sampleRate != targetSampleRate || AVAudioChannelCount(channelCount) != targetChannelCount {
            DispatchQueue.main.async {
                self.errorMessage = "Recording format changed. Stop and start recording again."
                self.stopRecording()
            }
            return
        }

        guard let format = cachedFormat,
              let pcmBuffer = cachedBuffer,
              pcmBuffer.frameCapacity >= AVAudioFrameCount(frameLength),
              format.sampleRate == sampleRate,
              format.channelCount == AVAudioChannelCount(channelCount)
        else {
            DispatchQueue.main.async {
                self.errorMessage = "Recording format changed. Stop and start recording again."
                self.stopRecording()
            }
            return
        }

        pcmBuffer.frameLength = AVAudioFrameCount(frameLength)

        if let channelData = pcmBuffer.floatChannelData {
            for channel in 0..<channelCount {
                buffer[channel].withUnsafeBufferPointer { src in
                    guard let base = src.baseAddress else { return }
                    channelData[channel].assign(from: base, count: frameLength)
                }
            }
        }

        var writeError: Error?
        recordingLock.lock()
        if let recordingFile {
            do {
                try recordingFile.write(from: pcmBuffer)
            } catch {
                writeError = error
            }
        }
        recordingLock.unlock()

        if let writeError {
            DispatchQueue.main.async {
                self.errorMessage = "Recording failed: \(writeError.localizedDescription)"
                self.stopRecording()
            }
        }
    }

    deinit {
        engine.inputNode.removeTap(onBus: 0)
        // Stop audio queue before deallocation to prevent callback accessing freed memory
        if let queue = outputQueue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
            // Note: We don't release the retained self here because if we're in deinit,
            // the retain count is already being decremented by ARC. Releasing here would
            // cause a double-release. The audioQueueRetainedSelf flag tracks this for
            // explicit stop() calls, but deinit means ARC is handling it.
        }
        engine.stop()

        // Clean up ring buffer
        os_unfair_lock_lock(&ringBufferLock)
        if let buffer = ringBuffer {
            buffer.deallocate()
        }
        os_unfair_lock_unlock(&ringBufferLock)

        NotificationCenter.default.removeObserver(self)
    }

}
