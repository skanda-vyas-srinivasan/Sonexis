import Foundation
import CoreGraphics

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

