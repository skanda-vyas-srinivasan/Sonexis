import AVFoundation
import Combine
import CoreAudio

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
    let effectChainOrder: [AudioGraphProcessor.EffectNode]
    let nodeParameters: [UUID: NodeEffectParameters]
    let nodeEnabled: [UUID: Bool]
    /// Retains the exact prepared render generation used by this graph snapshot.
    /// Older snapshots keep older Audio Units alive through in-flight blocks.
    let pluginRenderStates: [UUID: PluginRenderState]
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
    let compressorThresholdDB: Double
    let compressorRatio: Double
    let compressorAttackMS: Double
    let compressorReleaseMS: Double
    let compressorMakeupDB: Double
    let compressorMix: Double
    let reverbEnabled: Bool
    let reverbMix: Double
    let reverbSize: Double
    let delayEnabled: Bool
    let delayTime: Double
    let delayFeedback: Double
    let delayMix: Double
    let ampEnabled: Bool
    let ampInputGain: Double
    let ampDrive: Double
    let ampOutputGain: Double
    let ampMix: Double
    let distortionEnabled: Bool
    let distortionDrive: Double
    let distortionMix: Double
    let tremoloEnabled: Bool
    let tremoloRate: Double
    let tremoloDepth: Double
    let autoPanEnabled: Bool
    let autoPanRate: Double
    let autoPanDepth: Double
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
    let manualRoutingPlan: GraphRoutingPlan
    let splitLeftRoutingPlan: GraphRoutingPlan
    let splitRightRoutingPlan: GraphRoutingPlan

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
        pluginRenderStates: [:],
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
        compressorThresholdDB: -18,
        compressorRatio: 3,
        compressorAttackMS: 10,
        compressorReleaseMS: 120,
        compressorMakeupDB: 0,
        compressorMix: 1,
        reverbEnabled: false,
        reverbMix: 0,
        reverbSize: 0,
        delayEnabled: false,
        delayTime: 0,
        delayFeedback: 0,
        delayMix: 0,
        ampEnabled: false,
        ampInputGain: 0,
        ampDrive: 0,
        ampOutputGain: 0,
        ampMix: 0,
        distortionEnabled: false,
        distortionDrive: 0,
        distortionMix: 0,
        tremoloEnabled: false,
        tremoloRate: 0,
        tremoloDepth: 0,
        autoPanEnabled: false,
        autoPanRate: 0,
        autoPanDepth: 0,
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
        graphSignature: 0,
        manualRoutingPlan: .unconfigured,
        splitLeftRoutingPlan: .unconfigured,
        splitRightRoutingPlan: .unconfigured
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
    static let rubberBand = ResetFlags(rawValue: 1 << 12)
    static let autoPan = ResetFlags(rawValue: 1 << 13)
    static let tremolo = ResetFlags(rawValue: 1 << 14)
    static let all = ResetFlags(rawValue: 1 << 15)
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

struct ReverbTankState {
    private static let baseCombLengths = [1116, 1188, 1277, 1356]
    private static let baseAllPassLengths = [556, 441]

    var sampleRate: Double = 0
    var channelCount: Int = 0
    var combBuffers: [[[Float]]] = []
    var combWriteIndices: [[Int]] = []
    var combDampState: [[Float]] = []
    var allPassBuffers: [[[Float]]] = []
    var allPassWriteIndices: [[Int]] = []

    mutating func configure(sampleRate: Double, channelCount: Int) {
        guard sampleRate > 0, channelCount > 0 else { return }
        guard self.sampleRate != sampleRate || self.channelCount != channelCount else { return }

        let scale = sampleRate / 44_100.0
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        combBuffers = []
        combWriteIndices = []
        combDampState = []
        allPassBuffers = []
        allPassWriteIndices = []

        for channel in 0..<channelCount {
            let stereoOffset = channel * 23
            let combLengths = Self.baseCombLengths.map { max(1, Int(Double($0) * scale) + stereoOffset) }
            let allPassLengths = Self.baseAllPassLengths.map { max(1, Int(Double($0) * scale) + stereoOffset) }
            combBuffers.append(combLengths.map { [Float](repeating: 0, count: $0) })
            combWriteIndices.append([Int](repeating: 0, count: combLengths.count))
            combDampState.append([Float](repeating: 0, count: combLengths.count))
            allPassBuffers.append(allPassLengths.map { [Float](repeating: 0, count: $0) })
            allPassWriteIndices.append([Int](repeating: 0, count: allPassLengths.count))
        }
    }

    mutating func reset() {
        sampleRate = 0
        channelCount = 0
        combBuffers.removeAll()
        combWriteIndices.removeAll()
        combDampState.removeAll()
        allPassBuffers.removeAll()
        allPassWriteIndices.removeAll()
    }

    mutating func process(input: Float, channel: Int, feedback: Float, damping: Float) -> Float {
        guard channel < combBuffers.count,
              channel < combWriteIndices.count,
              channel < combDampState.count,
              channel < allPassBuffers.count,
              channel < allPassWriteIndices.count else {
            return 0
        }

        var wet: Float = 0
        for index in 0..<combBuffers[channel].count {
            let writeIndex = combWriteIndices[channel][index]
            let delayed = combBuffers[channel][index][writeIndex]
            let damped = delayed * (1 - damping) + combDampState[channel][index] * damping
            combDampState[channel][index] = damped
            combBuffers[channel][index][writeIndex] = input + damped * feedback
            combWriteIndices[channel][index] = (writeIndex + 1) % combBuffers[channel][index].count
            wet += delayed
        }
        wet *= 0.25

        for index in 0..<allPassBuffers[channel].count {
            let writeIndex = allPassWriteIndices[channel][index]
            let delayed = allPassBuffers[channel][index][writeIndex]
            let output = -wet + delayed
            allPassBuffers[channel][index][writeIndex] = wet + delayed * 0.5
            allPassWriteIndices[channel][index] = (writeIndex + 1) % allPassBuffers[channel][index].count
            wet = output
        }

        return wet * 0.7
    }
}

struct ModulatedEffectParameterState {
    var initialized = false
    var delaySamples: Float = 0
    var rate: Float = 0
    var depth: Float = 0
    var feedback: Float = 0
    var mix: Float = 0
}

struct SignatureEffectDSPState {
    var lowStates: [BiquadState] = []
    var midStates: [BiquadState] = []
    var highStates: [BiquadState] = []
    var previousSamples: [Float] = []
    var smoothedGain: Float = 0
    var envelope: Float = 0
    var reverb = ReverbTankState()

    mutating func configure(channelCount: Int) {
        if lowStates.count != channelCount {
            lowStates = [BiquadState](repeating: BiquadState(), count: channelCount)
        }
        if midStates.count != channelCount {
            midStates = [BiquadState](repeating: BiquadState(), count: channelCount)
        }
        if highStates.count != channelCount {
            highStates = [BiquadState](repeating: BiquadState(), count: channelCount)
        }
        if previousSamples.count != channelCount {
            previousSamples = [Float](repeating: 0, count: channelCount)
        }
    }
}

struct ProcessTapRuntimeSettings {
    let inputTrimDB: Double
    let outputMakeupDB: Double
    let outputCeilingEnabled: Bool
    let inputTrimGain: Float
    let outputMakeupGain: Float

    init(
        inputTrimDB: Double,
        outputMakeupDB: Double,
        outputCeilingEnabled: Bool
    ) {
        let clampedInputTrimDB = min(max(inputTrimDB, -30), 0)
        let clampedOutputMakeupDB = min(max(outputMakeupDB, -12), 30)
        self.inputTrimDB = clampedInputTrimDB
        self.outputMakeupDB = clampedOutputMakeupDB
        self.outputCeilingEnabled = outputCeilingEnabled
        self.inputTrimGain = Float(pow(10.0, clampedInputTrimDB / 20.0))
        self.outputMakeupGain = Float(pow(10.0, clampedOutputMakeupDB / 20.0))
    }

    static let defaults = ProcessTapRuntimeSettings(
        inputTrimDB: -15,
        outputMakeupDB: 15,
        outputCeilingEnabled: false
    )
}
