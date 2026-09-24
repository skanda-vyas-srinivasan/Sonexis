import Foundation

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
    var autoConnectEnd: Bool
    var nodes: [BeginnerNode]
    var connections: [BeginnerConnection]
    var autoGainOverrides: [BeginnerConnection]
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
        autoConnectEnd: Bool = false,
        nodes: [BeginnerNode],
        connections: [BeginnerConnection],
        autoGainOverrides: [BeginnerConnection] = [],
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
        self.autoConnectEnd = autoConnectEnd
        self.nodes = nodes
        self.connections = connections
        self.autoGainOverrides = autoGainOverrides
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
        case autoConnectEnd
        case nodes
        case connections
        case autoGainOverrides
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
        self.autoConnectEnd = try container.decodeIfPresent(Bool.self, forKey: .autoConnectEnd) ?? false
        self.nodes = try container.decodeIfPresent([BeginnerNode].self, forKey: .nodes) ?? []
        self.connections = try container.decodeIfPresent([BeginnerConnection].self, forKey: .connections) ?? []
        self.autoGainOverrides = try container.decodeIfPresent([BeginnerConnection].self, forKey: .autoGainOverrides) ?? []
        self.startNodeID = try container.decodeIfPresent(UUID.self, forKey: .startNodeID) ?? UUID()
        self.endNodeID = try container.decodeIfPresent(UUID.self, forKey: .endNodeID) ?? UUID()
        self.leftStartNodeID = try container.decodeIfPresent(UUID.self, forKey: .leftStartNodeID)
        self.leftEndNodeID = try container.decodeIfPresent(UUID.self, forKey: .leftEndNodeID)
        self.rightStartNodeID = try container.decodeIfPresent(UUID.self, forKey: .rightStartNodeID)
        self.rightEndNodeID = try container.decodeIfPresent(UUID.self, forKey: .rightEndNodeID)
        self.hasNodeParameters = try container.decodeIfPresent(Bool.self, forKey: .hasNodeParameters) ?? false
    }
}

enum GraphValidationError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        guard case .invalid(let message) = self else { return nil }
        return message
    }
}

extension GraphSnapshot {
    /// Structural errors are rejected. Numeric effect parameters are sanitized
    /// to their documented domain because older persisted files may predate bounds.
    func validatedForProcessing() throws -> GraphSnapshot {
        var result = self
        let nodeIDs = nodes.map(\.id)
        guard Set(nodeIDs).count == nodeIDs.count else {
            throw GraphValidationError.invalid("The graph contains duplicate node IDs.")
        }
        guard nodes.allSatisfy({ $0.position.x.isFinite && $0.position.y.isFinite }) else {
            throw GraphValidationError.invalid("The graph contains a non-finite node position.")
        }

        let terminals: [UUID]
        if graphMode == .split {
            guard let leftStartNodeID, let leftEndNodeID,
                  let rightStartNodeID, let rightEndNodeID else {
                throw GraphValidationError.invalid("A split graph is missing lane endpoints.")
            }
            terminals = [leftStartNodeID, leftEndNodeID, rightStartNodeID, rightEndNodeID]
        } else {
            terminals = [startNodeID, endNodeID]
        }
        guard Set(terminals).count == terminals.count,
              Set(nodeIDs).isDisjoint(with: terminals) else {
            throw GraphValidationError.invalid("Graph node and endpoint IDs must be unique.")
        }

        func sanitizedEdges(_ edges: [BeginnerConnection], label: String) throws -> [BeginnerConnection] {
            var seen: Set<String> = []
            let allIDs = Set(nodeIDs + terminals)
            return try edges.map { edge in
                guard allIDs.contains(edge.fromNodeId), allIDs.contains(edge.toNodeId) else {
                    throw GraphValidationError.invalid("The \(label) contains an unknown endpoint.")
                }
                guard edge.fromNodeId != edge.toNodeId else {
                    throw GraphValidationError.invalid("The \(label) contains a self-connection.")
                }
                guard edge.gain.isFinite else {
                    throw GraphValidationError.invalid("The \(label) contains a non-finite gain.")
                }
                guard seen.insert("\(edge.fromNodeId.uuidString):\(edge.toNodeId.uuidString)").inserted else {
                    throw GraphValidationError.invalid("The \(label) contains a duplicate connection.")
                }
                var sanitized = edge
                sanitized.gain = min(max(edge.gain, 0), 1)
                return sanitized
            }
        }
        result.connections = try sanitizedEdges(connections, label: "graph")
        result.autoGainOverrides = try sanitizedEdges(
            autoGainOverrides,
            label: "automatic gain overrides"
        )

        if graphMode == .split {
            let leftIDs = Set(nodes.filter { $0.lane == .left }.map(\.id) + [terminals[0], terminals[1]])
            let rightIDs = Set(nodes.filter { $0.lane == .right }.map(\.id) + [terminals[2], terminals[3]])
            guard (connections + autoGainOverrides).allSatisfy({
                (leftIDs.contains($0.fromNodeId) && leftIDs.contains($0.toNodeId))
                    || (rightIDs.contains($0.fromNodeId) && rightIDs.contains($0.toNodeId))
            }) else {
                throw GraphValidationError.invalid("A split graph connection crosses lane endpoints.")
            }
        }

        if wiringMode == .manual {
            var outgoing: [UUID: [UUID]] = [:]
            for edge in connections { outgoing[edge.fromNodeId, default: []].append(edge.toNodeId) }
            var visiting: Set<UUID> = []
            var visited: Set<UUID> = []
            func visit(_ id: UUID) -> Bool {
                if visiting.contains(id) { return false }
                if visited.contains(id) { return true }
                visiting.insert(id)
                for next in outgoing[id] ?? [] where !visit(next) { return false }
                visiting.remove(id)
                visited.insert(id)
                return true
            }
            guard (nodeIDs + terminals).allSatisfy({ visit($0) }) else {
                throw GraphValidationError.invalid("Manual graph cycles are not supported.")
            }
        }

        result.nodes = nodes.map { node in
            var node = node
            node.parameters = node.parameters.sanitized()
            return node
        }
        return result
    }

    func validateForIndependentProcessing() throws {
        _ = try validatedForProcessing()
    }
}

extension GraphSnapshot {
    /// Stable saved-content comparison: wire IDs are transient, and dictionary-backed
    /// gain overrides have no meaningful ordering. Layout only matters when it
    /// changes the effective automatic chain order.
    var presetComparisonData: Data? {
        struct Edge: Codable {
            let from: UUID
            let to: UUID
            let gain: Double
        }
        struct Content: Encodable {
            let graphMode: GraphMode
            let wiringMode: GraphWiringMode
            let autoConnectEnd: Bool
            let nodes: [BeginnerNode]
            let connections: [Edge]
            let gains: [Edge]
            let automaticOrder: [[UUID]]
        }
        let terminals = [startNodeID, endNodeID, leftStartNodeID, leftEndNodeID, rightStartNodeID, rightEndNodeID]
        func canonicalID(_ id: UUID) -> UUID {
            guard let index = terminals.firstIndex(where: { $0 == id }) else { return id }
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
        }
        func edges(_ values: [BeginnerConnection]) -> [Edge] {
            values.map { Edge(from: canonicalID($0.fromNodeId), to: canonicalID($0.toNodeId), gain: $0.gain) }
                .sorted {
                    if $0.from != $1.from { return $0.from.uuidString < $1.from.uuidString }
                    if $0.to != $1.to { return $0.to.uuidString < $1.to.uuidString }
                    return $0.gain < $1.gain
                }
        }
        func automaticPath(lane: GraphLane?, start: UUID?, end: UUID?) -> [UUID] {
            guard let start, let end else { return [] }
            let ordered = nodes.filter { lane == nil || $0.lane == lane }.sorted {
                if $0.position.x == $1.position.x { return $0.position.y < $1.position.y }
                return $0.position.x < $1.position.x
            }
            guard let first = ordered.first else { return [] }
            var next: [UUID: UUID] = [start: first.id]
            for index in ordered.indices {
                next[ordered[index].id] = index + 1 < ordered.count ? ordered[index + 1].id : end
            }
            let ids = Set(ordered.map(\.id))
            var path: [UUID] = []
            var visited: Set<UUID> = [start]
            var current = next[start]
            while let id = current, id != end, ids.contains(id), visited.insert(id).inserted {
                path.append(id)
                current = next[id]
            }
            return path
        }
        let order: [[UUID]] = wiringMode == .manual ? [] : graphMode == .single
            ? [automaticPath(lane: nil, start: startNodeID, end: endNodeID)]
            : [automaticPath(lane: .left, start: leftStartNodeID, end: leftEndNodeID),
               automaticPath(lane: .right, start: rightStartNodeID, end: rightEndNodeID)]
        let processingNodes = nodes.sorted { $0.id.uuidString < $1.id.uuidString }.map { node in
            var result = node
            result.position = .zero
            result.accentIndex = 0
            if var plugin = result.plugin, plugin.format == .au, let state = plugin.stateData {
                plugin.stateData = AudioUnitStateComparison.data(for: state)
                result.plugin = plugin
            }
            if graphMode == .single { result.lane = .left }
            return result
        }
        let content = Content(graphMode: graphMode, wiringMode: wiringMode,
            autoConnectEnd: autoConnectEnd, nodes: processingNodes,
            connections: wiringMode == .manual ? edges(connections) : [], gains: edges(autoGainOverrides), automaticOrder: order)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(content)
    }
}

/// AU fullState is a property list. Its binary object/key ordering can change
/// on every read even when every setting is identical. Normalize only the
/// comparison copy; the original plugin state remains intact for saving/loading.
private enum AudioUnitStateComparison {
    static func data(for state: Data) -> Data {
        guard let plist = try? PropertyListSerialization.propertyList(from: state, options: [], format: nil),
              let value = try? canonicalValue(plist),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            // Preserve byte comparison for opaque or unsupported states.
            return state
        }
        return data
    }

    private static func canonicalValue(_ value: Any) throws -> Any {
        // Tag each type so data/date values cannot collide with ordinary strings
        // or dictionaries. Dictionary keys are sorted by the final JSON encoder;
        // array order and all actual parameter values remain significant.
        switch value {
        case let dictionary as [String: Any]:
            return ["dictionary", try dictionary.mapValues { try canonicalValue($0) }] as [Any]
        case let array as [Any]:
            return ["array", try array.map { try canonicalValue($0) }] as [Any]
        case let data as Data:
            return ["data", data.base64EncodedString()]
        case let date as Date:
            return ["date", date.timeIntervalSinceReferenceDate] as [Any]
        case let string as String:
            return ["string", string]
        case let number as NSNumber:
            return ["number", number] as [Any]
        default:
            throw CocoaError(.propertyListReadCorrupt)
        }
    }
}
