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
    case deMud = "De-Mud"

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
        case .deMud:
            return "Removes muddiness and boxiness"
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
            return "waveform.path"
        case .stereoWidth:
            return "arrow.left.and.right"
        case .pitchShift:
            return "tuningfork"
        case .simpleEQ:
            return "slider.horizontal.3"
        case .deMud:
            return "eraser.fill"
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
        case .deMud:
            return ["strength": 50.0] // 0-100 scale
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
