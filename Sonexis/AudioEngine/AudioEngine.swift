import AVFoundation
import Combine
import CoreAudio

class AudioEngine: ObservableObject {
    // Connected by the multi-chain workspace; nil preserves standalone behavior.
    var onPowerStart: (() -> Void)?
    var onPowerStop: (() -> Void)?
    var onEffectsToggle: (() -> Void)?
    @Published var globalBypassActive = false
    @Published var captureTarget = AudioCaptureTarget.restore()
    var processTapEngine: ProcessTapDSPEngine?
    var processTapStopInProgress = false
    @Published var isRunning = false
    @Published var isPowerTransitioning = false
    @Published var errorMessage: String?
    @Published var inputDeviceName: String = "Searching..."
    @Published var outputDeviceName: String = "Searching..."
    @Published var signalFlowToken: Int = 0
    @Published var betaRecordingUnlocked = false
    private let recordingSinkLock = NSLock()
    private var _recordingSink: ((UnsafePointer<Float>, Int, Int, Double) -> Void)?
    /// Set by MultiChainAudioEngine while a combined recording is active; called
    /// unconditionally from the audio worker thread on every processed buffer.
    /// Read and written across threads, so access is guarded like the old
    /// per-chain recording session lookup was.
    var recordingSink: ((UnsafePointer<Float>, Int, Int, Double) -> Void)? {
        get { recordingSinkLock.lock(); defer { recordingSinkLock.unlock() }; return _recordingSink }
        set { recordingSinkLock.lock(); _recordingSink = newValue; recordingSinkLock.unlock() }
    }
    @Published var pluginStatusToken: Int = 0
    @Published var outputMeterLevel: Float = 0
    @Published var outputMeterPeakDBFS: Float = -96
    @Published var processTapInputTrimDB: Double = ProcessTapRuntimeSettings.defaults.inputTrimDB {
        didSet {
            let clampedValue = min(max(processTapInputTrimDB, -30), 0)
            if processTapInputTrimDB != clampedValue {
                processTapInputTrimDB = clampedValue
            }
            updateProcessTapRuntimeSettings()
        }
    }
    @Published var processTapOutputMakeupDB: Double = ProcessTapRuntimeSettings.defaults.outputMakeupDB {
        didSet {
            let clampedValue = min(max(processTapOutputMakeupDB, -12), 30)
            if processTapOutputMakeupDB != clampedValue {
                processTapOutputMakeupDB = clampedValue
            }
            updateProcessTapRuntimeSettings()
        }
    }
    @Published var processTapOutputCeilingEnabled: Bool = ProcessTapRuntimeSettings.defaults.outputCeilingEnabled {
        didSet {
            updateProcessTapRuntimeSettings()
        }
    }
    @Published var processTapRawInputPeakDBFS: Float = -96
    @Published var processTapTrimmedInputPeakDBFS: Float = -96
    @Published var processTapWarningText: String?

    private let tapFormatLock = NSLock()
    private var tapFrameLength: Int = 0
    private var tapChannelCount: Int = 0
    private var tapSampleRate: Double = 0
    private var processTapWarningClearTask: DispatchWorkItem?
    private var processTapInputMeterRawPeak: Float = 0
    private var processTapInputMeterTrimmedPeak: Float = 0
    private var processTapInputMeterUpdateCounter: Int = 0
    let processTapSettingsLock = NSLock()
    var processTapRuntimeSettings = ProcessTapRuntimeSettings.defaults

    init(observeSystemLifecycle: Bool = true) {
        if observeSystemLifecycle {
            setupNotifications()
            refreshOutputDevices()
            startDeviceListMonitor()
        }
        updateProcessingSnapshot()
        pluginHost.onPluginReady = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pluginStatusToken += 1
                self.scheduleSnapshotUpdate()
            }
        }
        graphProcessor.onEffectLevels = { [weak self] levels in
            DispatchQueue.main.async {
                self?.effectLevels = levels
            }
        }
    }

    func publishOutputMeter(sumSquares: Float, peak: Float, sampleCount: Int) {
        guard sampleCount > 0 else {
            publishOutputMeter(rms: 0, peak: 0)
            return
        }

        let safeSum = sumSquares.isFinite ? max(0, sumSquares) : 0
        let rms = sqrtf(safeSum / Float(sampleCount))
        publishOutputMeter(rms: rms, peak: peak)
    }

    func publishOutputMeter(rms: Float, peak: Float) {
        let safeRMS = rms.isFinite ? min(max(rms, 0), 1.5) : 0
        let safePeak = peak.isFinite ? min(max(peak, 0), 1.5) : 0

        let rmsCoefficient: Float = safeRMS > outputMeterSmoothedRMS ? 0.34 : 0.12
        let peakCoefficient: Float = safePeak > outputMeterSmoothedPeak ? 0.55 : 0.08
        outputMeterSmoothedRMS += (safeRMS - outputMeterSmoothedRMS) * rmsCoefficient
        outputMeterSmoothedPeak += (safePeak - outputMeterSmoothedPeak) * peakCoefficient

        outputMeterUpdateCounter += 1
        guard outputMeterUpdateCounter % 4 == 0 else { return }

        let level = outputMeterSmoothedRMS
        let peakDBFS = 20 * log10f(max(outputMeterSmoothedPeak, 0.000_001))
        DispatchQueue.main.async { [weak self] in
            self?.outputMeterLevel = level
            self?.outputMeterPeakDBFS = peakDBFS
        }
    }

    func publishOutputMeter(samples: [Float], sampleCount: Int) {
        let count = min(sampleCount, samples.count)
        guard count > 0 else {
            publishOutputMeter(rms: 0, peak: 0)
            return
        }

        var sumSquares: Float = 0
        var peak: Float = 0
        for index in 0..<count {
            let sample = samples[index]
            guard sample.isFinite else { continue }
            let magnitude = abs(sample)
            peak = max(peak, magnitude)
            sumSquares += sample * sample
        }
        publishOutputMeter(sumSquares: sumSquares, peak: peak, sampleCount: count)
    }

    func resetOutputMeter() {
        outputMeterSmoothedRMS = 0
        outputMeterSmoothedPeak = 0
        outputMeterUpdateCounter = 0
        DispatchQueue.main.async { [weak self] in
            self?.outputMeterLevel = 0
            self?.outputMeterPeakDBFS = -96
        }
    }

    func resetProcessTapInputMeter() {
        processTapInputMeterRawPeak = 0
        processTapInputMeterTrimmedPeak = 0
        processTapInputMeterUpdateCounter = 0
        DispatchQueue.main.async { [weak self] in
            self?.processTapRawInputPeakDBFS = -96
            self?.processTapTrimmedInputPeakDBFS = -96
        }
    }

    func publishProcessTapInputMeter(rawPeak: Float, trimmedPeak: Float) {
        let safeRawPeak = rawPeak.isFinite ? min(max(rawPeak, 0), 4) : 0
        let safeTrimmedPeak = trimmedPeak.isFinite ? min(max(trimmedPeak, 0), 4) : 0
        let rawCoefficient: Float = safeRawPeak > processTapInputMeterRawPeak ? 0.55 : 0.08
        let trimmedCoefficient: Float = safeTrimmedPeak > processTapInputMeterTrimmedPeak ? 0.55 : 0.08
        processTapInputMeterRawPeak += (safeRawPeak - processTapInputMeterRawPeak) * rawCoefficient
        processTapInputMeterTrimmedPeak += (safeTrimmedPeak - processTapInputMeterTrimmedPeak) * trimmedCoefficient

        processTapInputMeterUpdateCounter += 1
        guard processTapInputMeterUpdateCounter % 4 == 0 else { return }

        let rawDBFS = 20 * log10f(max(processTapInputMeterRawPeak, 0.000_001))
        let trimmedDBFS = 20 * log10f(max(processTapInputMeterTrimmedPeak, 0.000_001))
        DispatchQueue.main.async { [weak self] in
            self?.processTapRawInputPeakDBFS = rawDBFS
            self?.processTapTrimmedInputPeakDBFS = trimmedDBFS
        }
    }

    func publishProcessTapWarning(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            processTapWarningClearTask?.cancel()
            processTapWarningText = message

            let clearTask = DispatchWorkItem { [weak self] in
                self?.processTapWarningText = nil
            }
            processTapWarningClearTask = clearTask
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: clearTask)
        }
    }

    // Legacy global pitch controls. Node-based pitch processing uses Rubber Band.
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
    @Published var compressorThresholdDB: Double = -18.0 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var compressorRatio: Double = 3.0 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var compressorAttackMS: Double = 10.0 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var compressorReleaseMS: Double = 120.0 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var compressorMakeupDB: Double = 0.0 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var compressorMix: Double = 1.0 {
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

    // Amp effect
    @Published var ampEnabled = false {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var ampInputGain: Double = 0.0 { // dB
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var ampDrive: Double = 0.25 { // 0 to 1
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var ampOutputGain: Double = 0.0 { // dB
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var ampMix: Double = 1.0 { // 0 to 1
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
                resetTremoloState()
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

    // Auto pan effect
    @Published var autoPanEnabled = false {
        didSet {
            if !autoPanEnabled {
                resetAutoPanState()
            }
            scheduleSnapshotUpdate()
        }
    }
    @Published var autoPanRate: Double = 0.35 {
        didSet {
            scheduleSnapshotUpdate()
        }
    }
    @Published var autoPanDepth: Double = 0.7 {
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
    @Published private(set) var limiterEnabled = true {
        didSet {
            scheduleSnapshotUpdate()
        }
    }

    @Published var effectLevels: [UUID: Float] = [:]

    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedOutputDeviceID: AudioDeviceID?
    @Published var setupReady = true
    @Published var pendingGraphLoadRequest: GraphLoadRequest?

    var currentGraphSnapshot: GraphSnapshot?
    @Published var graphSnapshotRevision = 0
    @Published var currentPresetComparisonData: Data?
    let tenBandFrequencies: [Double] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    var deviceListMonitorTimer: DispatchSourceTimer?
    var deviceListMonitorListener: AudioObjectPropertyListenerBlock?
    let deviceListMonitorQueue = DispatchQueue(label: "AudioEngine.DeviceListMonitor", qos: .utility)

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
    let graphProcessor = AudioGraphProcessor()
    var outputMeterUpdateCounter = 0
    var outputMeterSmoothedRMS: Float = 0
    var outputMeterSmoothedPeak: Float = 0
    // Protects facade-side editable graph models during snapshot construction.
    // It is never acquired by AudioGraphProcessor or live plug-in rendering.
    let graphModelLock = NSLock()
    private var snapshotUpdateScheduled = false
    // Main-thread graph bookkeeping. Mutable DSP objects are never inspected here.
    var activeRubberBandPitchNodeIDs: Set<UUID> = []
    var isReconfiguring = false
    var restartWorkItem: DispatchWorkItem?
    let restartDebounceInterval: TimeInterval = 0.25

    // Routing plans are prepared on the main thread and embedded in immutable snapshots.
    private let manualRoutingCache = GraphRoutingPlanCache()
    private let splitLeftRoutingCache = GraphRoutingPlanCache()
    private let splitRightRoutingCache = GraphRoutingPlanCache()

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

    /// Publish a fully configured independent processor before its worker starts.
    func publishProcessingState() {
        precondition(Thread.isMainThread)
        updateProcessingSnapshot()
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

        withGraphModelLock {
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

        let chainOrder = chain.map { AudioGraphProcessor.EffectNode(id: $0.id, type: $0.type) }
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
            pluginRenderStates: pluginHost.processingRenderStates(),
            processingEnabled: processingEnabled,
            limiterEnabled: limiterEnabled,
            isReconfiguring: isReconfiguring,
            bassBoostEnabled: bassBoostEnabled,
            bassBoostAmount: bassBoostAmount,
            enhancerEnabled: false,
            enhancerAmount: 0,
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
            compressorThresholdDB: compressorThresholdDB,
            compressorRatio: compressorRatio,
            compressorAttackMS: compressorAttackMS,
            compressorReleaseMS: compressorReleaseMS,
            compressorMakeupDB: compressorMakeupDB,
            compressorMix: compressorMix,
            reverbEnabled: reverbEnabled,
            reverbMix: reverbMix,
            reverbSize: reverbSize,
            delayEnabled: delayEnabled,
            delayTime: delayTime,
            delayFeedback: delayFeedback,
            delayMix: delayMix,
            ampEnabled: ampEnabled,
            ampInputGain: ampInputGain,
            ampDrive: ampDrive,
            ampOutputGain: ampOutputGain,
            ampMix: ampMix,
            distortionEnabled: distortionEnabled,
            distortionDrive: distortionDrive,
            distortionMix: distortionMix,
            tremoloEnabled: tremoloEnabled,
            tremoloRate: tremoloRate,
            tremoloDepth: tremoloDepth,
            autoPanEnabled: autoPanEnabled,
            autoPanRate: autoPanRate,
            autoPanDepth: autoPanDepth,
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
            resampleEnabled: false,
            resampleRate: 1.0,
            resampleCrossfade: 0,
            rubberBandPitchEnabled: rubberBandPitchEnabled,
            rubberBandPitchSemitones: rubberBandPitchSemitones,
            graphSignature: graphSignature,
            manualRoutingPlan: manualRoutingCache.plan(nodes: manualNodes, connections: manualConnections,
                startID: manualStartID, endID: manualEndID, autoConnectEnd: manualAutoConnect),
            splitLeftRoutingPlan: splitLeftRoutingCache.plan(nodes: splitLeftNodes, connections: splitLeftConnections,
                startID: splitLeftStartID, endID: splitLeftEndID, autoConnectEnd: splitAutoConnect),
            splitRightRoutingPlan: splitRightRoutingCache.plan(nodes: splitRightNodes, connections: splitRightConnections,
                startID: splitRightStartID, endID: splitRightEndID, autoConnectEnd: splitAutoConnect)
        )

        graphProcessor.publish(snapshot)
    }

    func currentProcessingSnapshot() -> ProcessingSnapshot {
        graphProcessor.currentSnapshot()
    }

    func currentProcessTapRuntimeSettings() -> ProcessTapRuntimeSettings {
        processTapSettingsLock.lock()
        let settings = processTapRuntimeSettings
        processTapSettingsLock.unlock()
        return settings
    }

    func updateProcessTapRuntimeSettings() {
        let settings = ProcessTapRuntimeSettings(
            inputTrimDB: processTapInputTrimDB,
            outputMakeupDB: processTapOutputMakeupDB,
            outputCeilingEnabled: processTapOutputCeilingEnabled
        )
        processTapSettingsLock.lock()
        processTapRuntimeSettings = settings
        processTapSettingsLock.unlock()
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
        chainOrder: [AudioGraphProcessor.EffectNode],
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
        graphProcessor.enqueueReset(reset)
    }

    /// Publishes node liveness to the processing worker. The worker applies this
    /// command at the next block boundary, so main-thread graph edits never touch
    /// mutable per-node DSP state.
    func enqueueActiveNodeIDs(_ nodeIDs: Set<UUID>) {
        graphProcessor.enqueueActiveNodeIDs(nodeIDs)
    }

    func withGraphModelLock(_ work: () -> Void) {
        graphModelLock.lock()
        defer { graphModelLock.unlock() }
        work()
    }

    func resetBassBoostState() { enqueueReset(.bassBoost) }
    func resetClarityState() { enqueueReset(.clarity) }
    func resetDeMudState() { enqueueReset(.deMud) }
    func resetEQState() { enqueueReset(.eq) }
    func resetTenBandEQState() { enqueueReset(.tenBandEQ) }
    func resetCompressorState() { enqueueReset(.compressor) }
    func resetReverbState() { enqueueReset(.reverb) }
    func resetDelayState() { enqueueReset(.delay) }
    func resetChorusState() { enqueueReset(.chorus) }
    func resetAutoPanState() { enqueueReset(.autoPan) }
    func resetTremoloState() { enqueueReset(.tremolo) }
    func resetFlangerState() { enqueueReset(.flanger) }
    func resetPhaserState() { enqueueReset(.phaser) }
    func resetBitcrusherState() { enqueueReset(.bitcrusher) }
    func resetEffectState() { enqueueReset(.all) }

    func resetTenBandValues() {
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

    var tenBandGains: [Double] {
        [tenBand31, tenBand62, tenBand125, tenBand250, tenBand500,
         tenBand1k, tenBand2k, tenBand4k, tenBand8k, tenBand16k]
    }

    func updateTapFormat(frameLength: Int, channelCount: Int, sampleRate: Double) {
        tapFormatLock.lock()
        if tapChannelCount == channelCount, tapSampleRate == sampleRate {
            tapFrameLength = max(tapFrameLength, frameLength)
        } else {
            tapFrameLength = frameLength
        }
        tapChannelCount = channelCount
        tapSampleRate = sampleRate
        tapFormatLock.unlock()
    }

    /// Snapshot of the most recently processed buffer's format, if any buffer
    /// has been processed yet. Used by MultiChainAudioEngine to size a combined
    /// recording session without waiting on a specific chain's next callback.
    func currentTapFormat() -> (frames: Int, channels: Int, sampleRate: Double)? {
        tapFormatLock.lock()
        defer { tapFormatLock.unlock() }
        guard tapFrameLength > 0 else { return nil }
        return (tapFrameLength, tapChannelCount, tapSampleRate)
    }

    /// Final post-processing tap into the exact buffer this chain sends to the
    /// output device. Cheap no-op when nothing is recording.
    func recordFinalOutput(_ output: UnsafePointer<Float>, frameCount: Int,
                           channelCount: Int, sampleRate: Double) {
        recordingSink?(output, frameCount, channelCount, sampleRate)
    }

    deinit {
        stopProcessTapBackendImmediately(reason: "Sonexis deinit")
        stopDeviceListMonitor()
        NotificationCenter.default.removeObserver(self)
    }

}
