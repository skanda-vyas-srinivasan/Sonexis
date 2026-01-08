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
    case simpleEQ = "Simple EQ"
    case tenBandEQ = "10-Band EQ"
    case deMud = "De-Mud"
    case delay = "Delay"
    case distortion = "Distortion"
    case tremolo = "Tremolo"

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
        }
    }

    var icon: String {
        switch self {
        case .bassBoost:
            return "speaker.wave.3.fill"
        case .clarity:
            return "sparkles"
        case .reverb:
            return "building.columns.fill"
        case .compressor:
            return "waveform.path.ecg"
        case .stereoWidth:
            return "arrow.left.and.right"
        case .pitchShift:
            return "hare.fill"
        case .simpleEQ:
            return "slider.horizontal.3"
        case .tenBandEQ:
            return "slider.horizontal.2.square"
        case .deMud:
            return "bandage.fill"
        case .delay:
            return "arrow.3.trianglepath"
        case .distortion:
            return "waveform.path.badge.plus"
        case .tremolo:
            return "waveform"
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

struct BeginnerNode: Identifiable, Codable {
    let id: UUID
    let type: EffectType
    var position: CGPoint

    init(type: EffectType, position: CGPoint = .zero) {
        self.id = UUID()
        self.type = type
        self.position = position
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

struct GraphSnapshot: Codable {
    var wiringMode: GraphWiringMode
    var nodes: [BeginnerNode]
    var connections: [BeginnerConnection]
    var startNodeID: UUID
    var endNodeID: UUID
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
