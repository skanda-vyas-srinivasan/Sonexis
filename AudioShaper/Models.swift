import Foundation
import CoreGraphics

// MARK: - Effect Type

enum EffectType: String, Codable, CaseIterable {
    case bassBoost = "Bass Boost"
    case clarity = "Clarity"
    case reverb = "Reverb"
    case compressor = "Soft Compression"
    case stereoWidth = "Stereo Widening"
    case pitchShift = "Pitch Effect"
    case rubberBandPitch = "Pitch (Rubber Band)"
    case simpleEQ = "Simple EQ"
    case tenBandEQ = "10-Band EQ"
    case deMud = "De-Mud"
    case delay = "Delay"
    case distortion = "Distortion"
    case tremolo = "Tremolo"
    case chorus = "Chorus"
    case phaser = "Phaser"
    case flanger = "Flanger"
    case bitcrusher = "Bitcrusher"
    case tapeSaturation = "Tape Saturation"
    case resampling = "Resampling"

    var description: String {
        switch self {
        case .bassBoost:
            return "Makes low frequencies more powerful"
        case .clarity:
            return "Makes voices and instruments clearer"
        case .reverb:
            return "Adds space and depth"
        case .compressor:
            return "Evens out quiet and loud parts"
        case .stereoWidth:
            return "Makes sound feel wider and more spacious"
        case .pitchShift:
            return "Changes the pitch up or down"
        case .rubberBandPitch:
            return "High-quality pitch shift"
        case .simpleEQ:
            return "Adjust bass, middle, and treble"
        case .tenBandEQ:
            return "Fine-tune 10 frequency bands"
        case .deMud:
            return "Removes muddiness and boxiness"
        case .delay:
            return "Repeating echoes and rhythmic delays"
        case .distortion:
            return "Adds warmth, grit, and harmonic saturation"
        case .tremolo:
            return "Pulsing volume modulation"
        case .chorus:
            return "Thickens sound with lush modulation"
        case .phaser:
            return "Swirling, sweeping movement"
        case .flanger:
            return "Jet-like sweeping comb filter"
        case .bitcrusher:
            return "Retro digital grit and crunch"
        case .tapeSaturation:
            return "Warm, smooth analog saturation"
        case .resampling:
            return "Pitch and speed shift by resampling"
        }
    }

    var icon: String {
        switch self {
        case .bassBoost:
            return "speaker.wave.3"
        case .clarity:
            return "sparkles"
        case .reverb:
            return "building.columns"
        case .compressor:
            return "waveform.path.ecg"
        case .stereoWidth:
            return "arrow.left.and.right"
        case .pitchShift:
            return "hare"
        case .rubberBandPitch:
            return "music.note.list"
        case .simpleEQ:
            return "slider.horizontal.3"
        case .tenBandEQ:
            return "slider.horizontal.2.square"
        case .deMud:
            return "bandage"
        case .delay:
            return "arrow.3.trianglepath"
        case .distortion:
            return "waveform.path.badge.plus"
        case .tremolo:
            return "waveform"
        case .chorus:
            return "waveform.circle"
        case .phaser:
            return "circle.dotted.and.circle"
        case .flanger:
            return "waveform.path"
        case .bitcrusher:
            return "square.grid.3x3"
        case .tapeSaturation:
            return "record.circle"
        case .resampling:
            return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Effect Block

struct EffectBlock: Identifiable, Codable {
    let id: UUID
    let type: EffectType
    var parameters: [String: Float]
    var isEnabled: Bool
    var order: Int

    init(type: EffectType, order: Int = 0) {
        self.id = UUID()
        self.type = type
        self.parameters = Self.defaultParameters(for: type)
        self.isEnabled = true
        self.order = order
    }

    static func defaultParameters(for type: EffectType) -> [String: Float] {
        switch type {
        case .bassBoost:
            return ["gain": 6.0] // +6dB default
        case .clarity:
            return ["amount": 50.0, "brightness": 50.0] // 0-100 scale
        case .reverb:
            return ["mix": 30.0, "size": 50.0] // 0-100 scale
        case .compressor:
            return ["strength": 40.0] // 0-100 scale
        case .stereoWidth:
            return ["width": 30.0] // 0-100 scale
        case .pitchShift:
            return ["pitch": 0.0, "preserveTiming": 1.0] // -12 to +12 semitones
        case .rubberBandPitch:
            return ["semitones": 0.0]
        case .simpleEQ:
            return ["bass": 0.0, "mids": 0.0, "treble": 0.0] // -12 to +12 dB
        case .tenBandEQ:
            return [
                "31": 0.0, "62": 0.0, "125": 0.0, "250": 0.0, "500": 0.0,
                "1k": 0.0, "2k": 0.0, "4k": 0.0, "8k": 0.0, "16k": 0.0
            ]
        case .deMud:
            return ["strength": 50.0] // 0-100 scale
        case .delay:
            return ["time": 250.0, "feedback": 40.0, "mix": 30.0] // time in ms, feedback/mix 0-100
        case .distortion:
            return ["drive": 50.0, "mix": 50.0] // 0-100 scale
        case .tremolo:
            return ["rate": 5.0, "depth": 50.0] // rate in Hz, depth 0-100
        case .chorus:
            return ["rate": 0.8, "depth": 40.0, "mix": 35.0]
        case .phaser:
            return ["rate": 0.6, "depth": 50.0]
        case .flanger:
            return ["rate": 0.6, "depth": 40.0, "feedback": 25.0, "mix": 40.0]
        case .bitcrusher:
            return ["bitDepth": 8.0, "downsample": 4.0, "mix": 60.0]
        case .tapeSaturation:
            return ["drive": 35.0, "mix": 50.0]
        case .resampling:
            return ["rate": 1.0]
        }
    }
}

// MARK: - Effect Chain

struct EffectChain: Identifiable, Codable {
    var id: UUID
    var name: String
    var blocks: [EffectBlock]
    var createdDate: Date
    var modifiedDate: Date

    init(name: String = "New Chain") {
        self.id = UUID()
        self.name = name
        self.blocks = []
        self.createdDate = Date()
        self.modifiedDate = Date()
    }

    mutating func updateModifiedDate() {
        self.modifiedDate = Date()
    }
}

// MARK: - Beginner Mode Graph

enum GraphLane: String, Codable {
    case left
    case right
}

struct NodeEffectParameters: Codable, Equatable {
    var bassBoostAmount: Double
    var nightcoreIntensity: Double
    var clarityAmount: Double
    var deMudStrength: Double
    var eqBass: Double
    var eqMids: Double
    var eqTreble: Double
    var tenBandGains: [Double]
    var compressorStrength: Double
    var reverbMix: Double
    var reverbSize: Double
    var stereoWidthAmount: Double
    var delayTime: Double
    var delayFeedback: Double
    var delayMix: Double
    var distortionDrive: Double
    var distortionMix: Double
    var tremoloRate: Double
    var tremoloDepth: Double
    var chorusRate: Double
    var chorusDepth: Double
    var chorusMix: Double
    var phaserRate: Double
    var phaserDepth: Double
    var flangerRate: Double
    var flangerDepth: Double
    var flangerFeedback: Double
    var flangerMix: Double
    var bitcrusherBitDepth: Double
    var bitcrusherDownsample: Double
    var bitcrusherMix: Double
    var tapeSaturationDrive: Double
    var tapeSaturationMix: Double
    var resampleRate: Double
    var resampleCrossfade: Double
    var rubberBandPitchSemitones: Double

    init(
        bassBoostAmount: Double,
        nightcoreIntensity: Double,
        clarityAmount: Double,
        deMudStrength: Double,
        eqBass: Double,
        eqMids: Double,
        eqTreble: Double,
        tenBandGains: [Double],
        compressorStrength: Double,
        reverbMix: Double,
        reverbSize: Double,
        stereoWidthAmount: Double,
        delayTime: Double,
        delayFeedback: Double,
        delayMix: Double,
        distortionDrive: Double,
        distortionMix: Double,
        tremoloRate: Double,
        tremoloDepth: Double,
        chorusRate: Double,
        chorusDepth: Double,
        chorusMix: Double,
        phaserRate: Double,
        phaserDepth: Double,
        flangerRate: Double,
        flangerDepth: Double,
        flangerFeedback: Double,
        flangerMix: Double,
        bitcrusherBitDepth: Double,
        bitcrusherDownsample: Double,
        bitcrusherMix: Double,
        tapeSaturationDrive: Double,
        tapeSaturationMix: Double,
        resampleRate: Double,
        resampleCrossfade: Double,
        rubberBandPitchSemitones: Double
    ) {
        self.bassBoostAmount = bassBoostAmount
        self.nightcoreIntensity = nightcoreIntensity
        self.clarityAmount = clarityAmount
        self.deMudStrength = deMudStrength
        self.eqBass = eqBass
        self.eqMids = eqMids
        self.eqTreble = eqTreble
        self.tenBandGains = tenBandGains
        self.compressorStrength = compressorStrength
        self.reverbMix = reverbMix
        self.reverbSize = reverbSize
        self.stereoWidthAmount = stereoWidthAmount
        self.delayTime = delayTime
        self.delayFeedback = delayFeedback
        self.delayMix = delayMix
        self.distortionDrive = distortionDrive
        self.distortionMix = distortionMix
        self.tremoloRate = tremoloRate
        self.tremoloDepth = tremoloDepth
        self.chorusRate = chorusRate
        self.chorusDepth = chorusDepth
        self.chorusMix = chorusMix
        self.phaserRate = phaserRate
        self.phaserDepth = phaserDepth
        self.flangerRate = flangerRate
        self.flangerDepth = flangerDepth
        self.flangerFeedback = flangerFeedback
        self.flangerMix = flangerMix
        self.bitcrusherBitDepth = bitcrusherBitDepth
        self.bitcrusherDownsample = bitcrusherDownsample
        self.bitcrusherMix = bitcrusherMix
        self.tapeSaturationDrive = tapeSaturationDrive
        self.tapeSaturationMix = tapeSaturationMix
        self.resampleRate = resampleRate
        self.resampleCrossfade = resampleCrossfade
        self.rubberBandPitchSemitones = rubberBandPitchSemitones
    }

    static func defaults() -> NodeEffectParameters {
        NodeEffectParameters(
            bassBoostAmount: 0.6,
            nightcoreIntensity: 0.6,
            clarityAmount: 0.5,
            deMudStrength: 0.5,
            eqBass: 0,
            eqMids: 0,
            eqTreble: 0,
            tenBandGains: Array(repeating: 0, count: 10),
            compressorStrength: 0.4,
            reverbMix: 0.3,
            reverbSize: 0.5,
            stereoWidthAmount: 0.3,
            delayTime: 0.25,
            delayFeedback: 0.4,
            delayMix: 0.3,
            distortionDrive: 0.5,
            distortionMix: 0.5,
            tremoloRate: 5.0,
            tremoloDepth: 0.5,
            chorusRate: 0.8,
            chorusDepth: 0.4,
            chorusMix: 0.35,
            phaserRate: 0.6,
            phaserDepth: 0.5,
            flangerRate: 0.6,
            flangerDepth: 0.4,
            flangerFeedback: 0.25,
            flangerMix: 0.4,
            bitcrusherBitDepth: 8,
            bitcrusherDownsample: 4,
            bitcrusherMix: 0.6,
            tapeSaturationDrive: 0.35,
            tapeSaturationMix: 0.5,
            resampleRate: 1.0,
            resampleCrossfade: 0.3,
            rubberBandPitchSemitones: 0.0
        )
    }

    enum CodingKeys: String, CodingKey {
        case bassBoostAmount
        case nightcoreIntensity
        case clarityAmount
        case deMudStrength
        case eqBass
        case eqMids
        case eqTreble
        case tenBandGains
        case compressorStrength
        case reverbMix
        case reverbSize
        case stereoWidthAmount
        case delayTime
        case delayFeedback
        case delayMix
        case distortionDrive
        case distortionMix
        case tremoloRate
        case tremoloDepth
        case chorusRate
        case chorusDepth
        case chorusMix
        case phaserRate
        case phaserDepth
        case flangerRate
        case flangerDepth
        case flangerFeedback
        case flangerMix
        case bitcrusherBitDepth
        case bitcrusherDownsample
        case bitcrusherMix
        case tapeSaturationDrive
        case tapeSaturationMix
        case resampleRate
        case resampleCrossfade
        case rubberBandPitchSemitones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NodeEffectParameters.defaults()
        bassBoostAmount = try container.decodeIfPresent(Double.self, forKey: .bassBoostAmount) ?? defaults.bassBoostAmount
        nightcoreIntensity = try container.decodeIfPresent(Double.self, forKey: .nightcoreIntensity) ?? defaults.nightcoreIntensity
        clarityAmount = try container.decodeIfPresent(Double.self, forKey: .clarityAmount) ?? defaults.clarityAmount
        deMudStrength = try container.decodeIfPresent(Double.self, forKey: .deMudStrength) ?? defaults.deMudStrength
        eqBass = try container.decodeIfPresent(Double.self, forKey: .eqBass) ?? defaults.eqBass
        eqMids = try container.decodeIfPresent(Double.self, forKey: .eqMids) ?? defaults.eqMids
        eqTreble = try container.decodeIfPresent(Double.self, forKey: .eqTreble) ?? defaults.eqTreble
        tenBandGains = try container.decodeIfPresent([Double].self, forKey: .tenBandGains) ?? defaults.tenBandGains
        compressorStrength = try container.decodeIfPresent(Double.self, forKey: .compressorStrength) ?? defaults.compressorStrength
        reverbMix = try container.decodeIfPresent(Double.self, forKey: .reverbMix) ?? defaults.reverbMix
        reverbSize = try container.decodeIfPresent(Double.self, forKey: .reverbSize) ?? defaults.reverbSize
        stereoWidthAmount = try container.decodeIfPresent(Double.self, forKey: .stereoWidthAmount) ?? defaults.stereoWidthAmount
        delayTime = try container.decodeIfPresent(Double.self, forKey: .delayTime) ?? defaults.delayTime
        delayFeedback = try container.decodeIfPresent(Double.self, forKey: .delayFeedback) ?? defaults.delayFeedback
        delayMix = try container.decodeIfPresent(Double.self, forKey: .delayMix) ?? defaults.delayMix
        distortionDrive = try container.decodeIfPresent(Double.self, forKey: .distortionDrive) ?? defaults.distortionDrive
        distortionMix = try container.decodeIfPresent(Double.self, forKey: .distortionMix) ?? defaults.distortionMix
        tremoloRate = try container.decodeIfPresent(Double.self, forKey: .tremoloRate) ?? defaults.tremoloRate
        tremoloDepth = try container.decodeIfPresent(Double.self, forKey: .tremoloDepth) ?? defaults.tremoloDepth
        chorusRate = try container.decodeIfPresent(Double.self, forKey: .chorusRate) ?? defaults.chorusRate
        chorusDepth = try container.decodeIfPresent(Double.self, forKey: .chorusDepth) ?? defaults.chorusDepth
        chorusMix = try container.decodeIfPresent(Double.self, forKey: .chorusMix) ?? defaults.chorusMix
        phaserRate = try container.decodeIfPresent(Double.self, forKey: .phaserRate) ?? defaults.phaserRate
        phaserDepth = try container.decodeIfPresent(Double.self, forKey: .phaserDepth) ?? defaults.phaserDepth
        flangerRate = try container.decodeIfPresent(Double.self, forKey: .flangerRate) ?? defaults.flangerRate
        flangerDepth = try container.decodeIfPresent(Double.self, forKey: .flangerDepth) ?? defaults.flangerDepth
        flangerFeedback = try container.decodeIfPresent(Double.self, forKey: .flangerFeedback) ?? defaults.flangerFeedback
        flangerMix = try container.decodeIfPresent(Double.self, forKey: .flangerMix) ?? defaults.flangerMix
        bitcrusherBitDepth = try container.decodeIfPresent(Double.self, forKey: .bitcrusherBitDepth) ?? defaults.bitcrusherBitDepth
        bitcrusherDownsample = try container.decodeIfPresent(Double.self, forKey: .bitcrusherDownsample) ?? defaults.bitcrusherDownsample
        bitcrusherMix = try container.decodeIfPresent(Double.self, forKey: .bitcrusherMix) ?? defaults.bitcrusherMix
        tapeSaturationDrive = try container.decodeIfPresent(Double.self, forKey: .tapeSaturationDrive) ?? defaults.tapeSaturationDrive
        tapeSaturationMix = try container.decodeIfPresent(Double.self, forKey: .tapeSaturationMix) ?? defaults.tapeSaturationMix
        resampleRate = try container.decodeIfPresent(Double.self, forKey: .resampleRate) ?? defaults.resampleRate
        resampleCrossfade = try container.decodeIfPresent(Double.self, forKey: .resampleCrossfade) ?? defaults.resampleCrossfade
        rubberBandPitchSemitones = try container.decodeIfPresent(Double.self, forKey: .rubberBandPitchSemitones) ?? defaults.rubberBandPitchSemitones
    }
}

struct BeginnerNode: Identifiable, Codable {
    let id: UUID
    let type: EffectType
    var position: CGPoint
    var lane: GraphLane
    var isEnabled: Bool
    var parameters: NodeEffectParameters
    var accentIndex: Int

    init(
        type: EffectType,
        position: CGPoint = .zero,
        lane: GraphLane = .left,
        isEnabled: Bool = true,
        parameters: NodeEffectParameters = NodeEffectParameters.defaults(),
        accentIndex: Int = 0
    ) {
        self.id = UUID()
        self.type = type
        self.position = position
        self.lane = lane
        self.isEnabled = isEnabled
        self.parameters = parameters
        self.accentIndex = accentIndex
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case position
        case lane
        case isEnabled
        case parameters
        case accentIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.type = try container.decode(EffectType.self, forKey: .type)
        self.position = try container.decodeIfPresent(CGPoint.self, forKey: .position) ?? .zero
        self.lane = try container.decodeIfPresent(GraphLane.self, forKey: .lane) ?? .left
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.parameters = try container.decodeIfPresent(NodeEffectParameters.self, forKey: .parameters) ?? NodeEffectParameters.defaults()
        self.accentIndex = try container.decodeIfPresent(Int.self, forKey: .accentIndex) ?? 0
    }
}

struct BeginnerConnection: Identifiable, Codable {
    let id: UUID
    let fromNodeId: UUID
    let toNodeId: UUID
    var gain: Double

    init(fromNodeId: UUID, toNodeId: UUID, gain: Double = 1.0) {
        self.id = UUID()
        self.fromNodeId = fromNodeId
        self.toNodeId = toNodeId
        self.gain = gain
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fromNodeId
        case toNodeId
        case gain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.fromNodeId = try container.decode(UUID.self, forKey: .fromNodeId)
        self.toNodeId = try container.decode(UUID.self, forKey: .toNodeId)
        self.gain = try container.decodeIfPresent(Double.self, forKey: .gain) ?? 1.0
    }
}

enum GraphWiringMode: String, Codable {
    case automatic
    case manual
}

enum GraphMode: String, Codable {
    case single
    case split
}

struct GraphSnapshot: Codable {
    var graphMode: GraphMode
    var wiringMode: GraphWiringMode
    var nodes: [BeginnerNode]
    var connections: [BeginnerConnection]
    var startNodeID: UUID
    var endNodeID: UUID
    var leftStartNodeID: UUID?
    var leftEndNodeID: UUID?
    var rightStartNodeID: UUID?
    var rightEndNodeID: UUID?
    var hasNodeParameters: Bool

    init(
        graphMode: GraphMode,
        wiringMode: GraphWiringMode,
        nodes: [BeginnerNode],
        connections: [BeginnerConnection],
        startNodeID: UUID,
        endNodeID: UUID,
        leftStartNodeID: UUID? = nil,
        leftEndNodeID: UUID? = nil,
        rightStartNodeID: UUID? = nil,
        rightEndNodeID: UUID? = nil,
        hasNodeParameters: Bool = true
    ) {
        self.graphMode = graphMode
        self.wiringMode = wiringMode
        self.nodes = nodes
        self.connections = connections
        self.startNodeID = startNodeID
        self.endNodeID = endNodeID
        self.leftStartNodeID = leftStartNodeID
        self.leftEndNodeID = leftEndNodeID
        self.rightStartNodeID = rightStartNodeID
        self.rightEndNodeID = rightEndNodeID
        self.hasNodeParameters = hasNodeParameters
    }

    enum CodingKeys: String, CodingKey {
        case graphMode
        case wiringMode
        case nodes
        case connections
        case startNodeID
        case endNodeID
        case leftStartNodeID
        case leftEndNodeID
        case rightStartNodeID
        case rightEndNodeID
        case hasNodeParameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.graphMode = try container.decodeIfPresent(GraphMode.self, forKey: .graphMode) ?? .single
        self.wiringMode = try container.decodeIfPresent(GraphWiringMode.self, forKey: .wiringMode) ?? .automatic
        self.nodes = try container.decodeIfPresent([BeginnerNode].self, forKey: .nodes) ?? []
        self.connections = try container.decodeIfPresent([BeginnerConnection].self, forKey: .connections) ?? []
        self.startNodeID = try container.decodeIfPresent(UUID.self, forKey: .startNodeID) ?? UUID()
        self.endNodeID = try container.decodeIfPresent(UUID.self, forKey: .endNodeID) ?? UUID()
        self.leftStartNodeID = try container.decodeIfPresent(UUID.self, forKey: .leftStartNodeID)
        self.leftEndNodeID = try container.decodeIfPresent(UUID.self, forKey: .leftEndNodeID)
        self.rightStartNodeID = try container.decodeIfPresent(UUID.self, forKey: .rightStartNodeID)
        self.rightEndNodeID = try container.decodeIfPresent(UUID.self, forKey: .rightEndNodeID)
        self.hasNodeParameters = try container.decodeIfPresent(Bool.self, forKey: .hasNodeParameters) ?? false
    }
}

// MARK: - Preset

struct Preset: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let chain: EffectChain
    let exposedParameters: [ExposedParameter]

    struct ExposedParameter: Codable {
        let name: String // User-facing name like "Intensity"
        let min: Float
        let max: Float
        let defaultValue: Float
        let mappings: [ParameterMapping]
    }

    struct ParameterMapping: Codable {
        let blockId: UUID
        let parameterName: String
        let minValue: Float
        let maxValue: Float

        func mapValue(_ normalizedValue: Float) -> Float {
            // Maps input value to minValue-maxValue range
            let t = (normalizedValue - 0) / (100 - 0) // Normalize to 0-1
            return minValue + t * (maxValue - minValue)
        }
    }
}

// MARK: - Advanced Mode Models

struct AdvancedNode: Identifiable, Codable {
    let id: UUID
    let effectType: EffectType
    var parameters: [String: Float]
    var position: CGPoint
    var isEnabled: Bool

    init(effectType: EffectType, position: CGPoint = .zero) {
        self.id = UUID()
        self.effectType = effectType
        self.parameters = EffectBlock.defaultParameters(for: effectType)
        self.position = position
        self.isEnabled = true
    }
}

struct NodeConnection: Identifiable, Codable {
    let id: UUID
    let fromNodeId: UUID
    let toNodeId: UUID

    init(fromNodeId: UUID, toNodeId: UUID) {
        self.id = UUID()
        self.fromNodeId = fromNodeId
        self.toNodeId = toNodeId
    }
}

struct AdvancedChain: Codable {
    var id: UUID
    var name: String
    var nodes: [AdvancedNode]
    var connections: [NodeConnection]

    init(name: String = "Advanced Chain") {
        self.id = UUID()
        self.name = name
        self.nodes = []
        self.connections = []
    }

    // Check if chain is linear (can be converted to beginner mode)
    func isLinear() -> Bool {
        // Check that each node has at most one input and one output
        for node in nodes {
            let inputs = connections.filter { $0.toNodeId == node.id }.count
            let outputs = connections.filter { $0.fromNodeId == node.id }.count

            if inputs > 1 || outputs > 1 {
                return false
            }
        }
        return true
    }
}

// MARK: - Project

struct Project: Codable {
    var id: UUID
    var name: String
    var chains: [EffectChain]
    var activeChainId: UUID?
    var userPresets: [Preset]
    var settings: ProjectSettings

    init(name: String = "Untitled Project") {
        self.id = UUID()
        self.name = name
        self.chains = [EffectChain(name: "Default Chain")]
        self.activeChainId = chains.first?.id
        self.userPresets = []
        self.settings = ProjectSettings()
    }
}

struct ProjectSettings: Codable {
    var masterVolume: Float
    var processingEnabled: Bool
    var autoGainEnabled: Bool

    init() {
        self.masterVolume = 1.0
        self.processingEnabled = false
        self.autoGainEnabled = true
    }
}
