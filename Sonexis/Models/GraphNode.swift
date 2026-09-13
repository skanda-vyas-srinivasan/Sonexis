import Foundation
import CoreGraphics

enum GraphLane: String, Codable {
    case left
    case right
}
struct BeginnerNode: Identifiable, Codable {
    let id: UUID
    let type: EffectType
    var position: CGPoint
    var lane: GraphLane
    var isEnabled: Bool
    var parameters: NodeEffectParameters
    var accentIndex: Int
    var plugin: PluginReference?

    init(
        type: EffectType,
        position: CGPoint = .zero,
        lane: GraphLane = .left,
        isEnabled: Bool = true,
        parameters: NodeEffectParameters = NodeEffectParameters.defaults(),
        accentIndex: Int = 0,
        plugin: PluginReference? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.position = position
        self.lane = lane
        self.isEnabled = isEnabled
        self.parameters = parameters
        self.accentIndex = accentIndex
        self.plugin = plugin
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case position
        case lane
        case isEnabled
        case parameters
        case accentIndex
        case plugin
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
        self.plugin = try container.decodeIfPresent(PluginReference.self, forKey: .plugin)
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

extension BeginnerNode {
    var displayName: String {
        if type == .plugin {
            return plugin?.displayName ?? type.rawValue
        }
        return type.rawValue
    }

    var displayIcon: String {
        if type == .plugin {
            return "puzzlepiece.extension"
        }
        return type.icon
    }

    var displayBadge: String? {
        return nil
    }
}
