import AVFoundation
import Foundation

/// Single owner for mutable graph-rendering state. Instances are driven by one
/// processing worker; the main-thread facade communicates only through immutable
/// snapshots and bounded reset or node-retirement commands.
final class AudioGraphProcessor {
    private let snapshotLock = NSLock()
    private var processingSnapshot = ProcessingSnapshot.empty
    private let commandLock = NSLock()
    private var pendingResets: ResetFlags = []
    private var pendingActiveNodeIDs: Set<UUID>?

    var onEffectLevels: (([UUID: Float]) -> Void)?
    var levelUpdateCounter = 0

    // Bass boost state
    var bassBoostState: [BiquadState] = []
    var bassBoostCoefficients = BiquadCoefficients()
    var bassBoostLastSampleRate: Double = 0
    var bassBoostLastAmount: Double = -1
    var bassBoostStatesByNode: [UUID: [BiquadState]] = [:]
    var bassBoostSmoothedGain: Float = 0
    var bassBoostSmoothedGainByNode: [UUID: Float] = [:]
    var bassBoostVDSPDelay: [[Float]] = []
    var bassBoostVDSPDelayByNode: [UUID: [[Float]]] = [:]
    var biquadScratchBuffer: [Float] = []
    var biquadScratchBuffer2: [Float] = []

    // Enhancer state
    var enhancerSmoothedGain: Float = 0
    var enhancerSmoothedGainByNode: [UUID: Float] = [:]
    var enhancerLowVDSPDelay: [[Float]] = []
    var enhancerMidVDSPDelay: [[Float]] = []
    var enhancerHighVDSPDelay: [[Float]] = []
    var enhancerLowVDSPDelayByNode: [UUID: [[Float]]] = [:]
    var enhancerMidVDSPDelayByNode: [UUID: [[Float]]] = [:]
    var enhancerHighVDSPDelayByNode: [UUID: [[Float]]] = [:]

    // Clarity and pitch brightness state
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

    // De-mud state
    var deMudState: [BiquadState] = []
    var deMudCoefficients = BiquadCoefficients()
    var deMudLastSampleRate: Double = 0
    var deMudLastStrength: Double = -1
    var deMudStatesByNode: [UUID: [BiquadState]] = [:]
    var deMudSmoothedGain: Float = 0
    var deMudSmoothedGainByNode: [UUID: Float] = [:]
    var deMudVDSPDelay: [[Float]] = []
    var deMudVDSPDelayByNode: [UUID: [[Float]]] = [:]

    // EQ state
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
    var appleThreeBandEQProcessorsByNode: [UUID: AppleThreeBandEQProcessor] = [:]
    var appleThreeBandEQDryScratchByNode: [UUID: [[Float]]] = [:]
    var appleThreeBandEQSmoothedGainByNode: [UUID: Float] = [:]
    let tenBandFrequencies: [Double] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    var tenBandStates: [[BiquadState]] = []
    var tenBandCoefficients: [BiquadCoefficients] = []
    var tenBandLastSampleRate: Double = 0
    var tenBandLastGains: [Double] = []
    var tenBandStatesByNode: [UUID: [[BiquadState]]] = [:]
    var tenBandEQSmoothedGain: Float = 0
    var tenBandEQSmoothedGainByNode: [UUID: Float] = [:]
    var tenBandVDSPDelays: [[[Float]]] = []
    var tenBandVDSPDelaysByNode: [UUID: [[[Float]]]] = [:]

    // Dynamics, space, and modulation state
    var compressorEnvelope: Float = 1
    var compressorEnvelopeByNode: [UUID: Float] = [:]
    var compressorSmoothedGain: Float = 0
    var compressorSmoothedGainByNode: [UUID: Float] = [:]
    var reverbState = ReverbTankState()
    var reverbStatesByNode: [UUID: ReverbTankState] = [:]
    var reverbSmoothedGain: Float = 0
    var reverbSmoothedGainByNode: [UUID: Float] = [:]
    var delayBuffer: [[Float]] = []
    var delayWriteIndex = 0
    var delayBuffersByNode: [UUID: [[Float]]] = [:]
    var delayWriteIndexByNode: [UUID: Int] = [:]
    var delaySmoothedGain: Float = 0
    var delaySmoothedGainByNode: [UUID: Float] = [:]
    var delayParameterState = ModulatedEffectParameterState()
    var delayParameterStateByNode: [UUID: ModulatedEffectParameterState] = [:]
    var tremoloPhase: Double = 0
    var tremoloPhaseByNode: [UUID: Double] = [:]
    var tremoloSmoothedGain: Float = 0
    var tremoloSmoothedGainByNode: [UUID: Float] = [:]
    var autoPanPhase: Double = 0
    var autoPanPhaseByNode: [UUID: Double] = [:]
    var autoPanSmoothedGain: Float = 0
    var autoPanSmoothedGainByNode: [UUID: Float] = [:]
    var autoPanParameterState = ModulatedEffectParameterState()
    var autoPanParameterStateByNode: [UUID: ModulatedEffectParameterState] = [:]
    var chorusBuffer: [[Float]] = []
    var chorusWriteIndex = 0
    var chorusPhase: Double = 0
    var chorusBuffersByNode: [UUID: [[Float]]] = [:]
    var chorusWriteIndexByNode: [UUID: Int] = [:]
    var chorusPhaseByNode: [UUID: Double] = [:]
    var chorusSmoothedGain: Float = 0
    var chorusSmoothedGainByNode: [UUID: Float] = [:]
    var chorusParameterState = ModulatedEffectParameterState()
    var chorusParameterStateByNode: [UUID: ModulatedEffectParameterState] = [:]
    var flangerBuffer: [[Float]] = []
    var flangerWriteIndex = 0
    var flangerPhase: Double = 0
    var flangerBuffersByNode: [UUID: [[Float]]] = [:]
    var flangerWriteIndexByNode: [UUID: Int] = [:]
    var flangerPhaseByNode: [UUID: Double] = [:]
    var flangerSmoothedGain: Float = 0
    var flangerSmoothedGainByNode: [UUID: Float] = [:]
    var flangerParameterState = ModulatedEffectParameterState()
    var flangerParameterStateByNode: [UUID: ModulatedEffectParameterState] = [:]
    let phaserStageCount = 4
    var phaserStates: [[AllPassState]] = []
    var phaserStatesByNode: [UUID: [[AllPassState]]] = [:]
    var phaserPhase: Double = 0
    var phaserPhaseByNode: [UUID: Double] = [:]
    var phaserFeedbackSamples: [Float] = []
    var phaserFeedbackSamplesByNode: [UUID: [Float]] = [:]
    var phaserSmoothedGain: Float = 0
    var phaserSmoothedGainByNode: [UUID: Float] = [:]
    var phaserParameterState = ModulatedEffectParameterState()
    var phaserParameterStateByNode: [UUID: ModulatedEffectParameterState] = [:]

    // Resampling and pitch state
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
    var rubberBandNodes: [UUID: RubberBandWrapper] = [:]
    var rubberBandGlobalByType: [EffectType: RubberBandWrapper] = [:]
    var rubberBandScratchByNode: [UUID: RubberBandScratch] = [:]
    var rubberBandScratchGlobal = RubberBandScratch()
    var rubberBandSmoothedGain: Float = 0
    var rubberBandSmoothedGainByNode: [UUID: Float] = [:]

    // Remaining effect state
    var bitcrusherHoldCounters: [Int] = []
    var bitcrusherHoldValues: [Float] = []
    var bitcrusherHoldCountersByNode: [UUID: [Int]] = [:]
    var bitcrusherHoldValuesByNode: [UUID: [Float]] = [:]
    var bitcrusherSmoothedGain: Float = 0
    var bitcrusherSmoothedGainByNode: [UUID: Float] = [:]
    var ampSmoothedGain: Float = 0
    var ampSmoothedGainByNode: [UUID: Float] = [:]
    var distortionSmoothedGain: Float = 0
    var distortionSmoothedGainByNode: [UUID: Float] = [:]
    var tapeSaturationSmoothedGain: Float = 0
    var tapeSaturationSmoothedGainByNode: [UUID: Float] = [:]
    var signatureEffectStatesByNode: [UUID: SignatureEffectDSPState] = [:]
    var signatureEffectStatesByType: [EffectType: SignatureEffectDSPState] = [:]
    var stereoWidthSmoothedGain: Float = 0
    var stereoWidthSmoothedGainByNode: [UUID: Float] = [:]

    // Plug-in transition state
    var pluginDryScratchByNode: [UUID: [[Float]]] = [:]
    var pluginWetScratchByNode: [UUID: [[Float]]] = [:]
    var pluginCrossfadeRemainingByNode: [UUID: Int] = [:]
    var pluginCrossfadeTotalByNode: [UUID: Int] = [:]
    var pluginCrossfadeOutRemainingByNode: [UUID: Int] = [:]
    var pluginCrossfadeOutTotalByNode: [UUID: Int] = [:]
    var pluginWasEnabledByNode: [UUID: Bool] = [:]
    var pluginWasReadyByNode: [UUID: Bool] = [:]
    var pluginStableOutputCountByNode: [UUID: Int] = [:]
    var pluginHasStableOutputByNode: [UUID: Bool] = [:]
    var pluginReadyDelaySamplesByNode: [UUID: Int] = [:]

    // Worker-side buffers and graph state
    var interleavedOutputBuffer: [Float] = []
    var interleavedOutputCapacity: Int = 0
    var processingBuffer: [[Float]] = []
    var processingFrameCapacity: Int = 0
    var deinterleavedInputBuffer: [[Float]] = []
    var deinterleavedInputCapacity: Int = 0
    var processTapPCMBuffer: AVAudioPCMBuffer?
    var processTapPCMBufferFrameCapacity: Int = 0
    var processTapPCMBufferChannelCount: Int = 0
    var processTapPCMBufferSampleRate: Double = 0
    var graphOutputBuffers: [UUID: [[Float]]] = [:]
    let graphOutputTransition = GraphOutputTransition()
    var dspFaultCountsByEffect: [EffectType: Int] = [:]
    var dspFaultCountsByNode: [UUID: Int] = [:]

    func publish(_ snapshot: ProcessingSnapshot) {
        snapshotLock.lock()
        processingSnapshot = snapshot
        snapshotLock.unlock()
    }

    func currentSnapshot() -> ProcessingSnapshot {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return processingSnapshot
    }

    func enqueueReset(_ reset: ResetFlags) {
        commandLock.lock()
        pendingResets.insert(reset)
        commandLock.unlock()
    }

    func enqueueActiveNodeIDs(_ nodeIDs: Set<UUID>) {
        commandLock.lock()
        pendingActiveNodeIDs = nodeIDs
        commandLock.unlock()
    }

    func takePendingCommands() -> (ResetFlags, Set<UUID>?) {
        commandLock.lock()
        defer { commandLock.unlock() }
        let commands = (pendingResets, pendingActiveNodeIDs)
        pendingResets = []
        pendingActiveNodeIDs = nil
        return commands
    }
}
