import AVFoundation
import Combine
import CoreAudio
import AudioToolbox

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
    }

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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

}
