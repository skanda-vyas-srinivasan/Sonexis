import Foundation

/// Immutable routing only: DSP parameters and effect state remain in the engine.
/// Prepared before snapshot publication, never traversed/rebuilt by the worker.
final class GraphRoutingPlan {
    enum OutputMode { case passthrough, empty, routed }
    struct Step {
        let id: UUID
        let type: EffectType
        let inputs: [(UUID, Double)]
    }

    let mode: OutputMode
    let startID: UUID?
    let steps: [Step]
    let endInputs: [(UUID, Double)]

    static let unconfigured = GraphRoutingPlan(nodes: [], connections: [],
        startID: nil, endID: nil, autoConnectEnd: false)

    init(nodes: [BeginnerNode], connections: [BeginnerConnection],
         startID: UUID?, endID: UUID?, autoConnectEnd: Bool) {
        self.startID = startID
        guard let startID, let endID else {
            mode = .passthrough; steps = []; endInputs = []
            return
        }
        guard !nodes.isEmpty || !connections.isEmpty else {
            mode = .empty; steps = []; endInputs = []
            return
        }
        mode = .routed
        var outgoing: [UUID: [UUID]] = [:]
        var incoming: [UUID: [(UUID, Double)]] = [:]
        for connection in connections {
            outgoing[connection.fromNodeId, default: []].append(connection.toNodeId)
            incoming[connection.toNodeId, default: []].append((connection.fromNodeId, connection.gain))
        }

        var reachable: Set<UUID> = [startID]
        var queue = [startID]
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for next in outgoing[current] ?? [] where reachable.insert(next).inserted {
                queue.append(next)
            }
        }

        if autoConnectEnd {
            // Preserve the existing reachable-sink rule, including explicit
            // output gains. Preparation does not infer routes for orphan nodes.
            for id in reachable where id != startID && id != endID {
                let outputs = outgoing[id] ?? []
                let hasFurtherNode = outputs.contains { reachable.contains($0) && $0 != endID }
                if !hasFurtherNode && !outputs.contains(endID) {
                    outgoing[id, default: []].append(endID)
                    incoming[endID, default: []].append((id, 1))
                }
            }
        }

        var nodeByID: [UUID: BeginnerNode] = [:]
        for node in nodes where nodeByID[node.id] == nil { nodeByID[node.id] = node }
        var indegree: [UUID: Int] = [:]
        queue.removeAll(keepingCapacity: true)
        cursor = 0
        for node in nodes where reachable.contains(node.id) {
            let count = (incoming[node.id] ?? []).filter { $0.0 != startID }.count
            indegree[node.id] = count
            if count == 0 { queue.append(node.id) }
        }

        var preparedSteps: [Step] = []
        while cursor < queue.count {
            let id = queue[cursor]
            cursor += 1
            guard let node = nodeByID[id] else { continue }
            preparedSteps.append(Step(id: id, type: node.type, inputs: incoming[id] ?? []))
            for next in outgoing[id] ?? [] where reachable.contains(next) && next != endID {
                indegree[next, default: 0] -= 1
                if indegree[next] == 0 { queue.append(next) }
            }
        }
        steps = preparedSteps
        endInputs = incoming[endID] ?? []
    }
}

/// One cache per graph/lane, owned by the snapshot-publishing thread. Equality
/// excludes positions, parameter values, enabled state and transient wire IDs.
final class GraphRoutingPlanCache {
    private struct Node: Equatable { let id: UUID; let type: EffectType }
    private struct Edge: Equatable { let from: UUID; let to: UUID; let gain: Double }
    private struct Key: Equatable {
        let nodes: [Node]
        let edges: [Edge]
        let start: UUID?
        let end: UUID?
        let autoConnect: Bool
    }
    private var key: Key?
    private var cached = GraphRoutingPlan.unconfigured

    func plan(nodes: [BeginnerNode], connections: [BeginnerConnection],
              startID: UUID?, endID: UUID?, autoConnectEnd: Bool) -> GraphRoutingPlan {
        let next = Key(nodes: nodes.map { Node(id: $0.id, type: $0.type) },
            edges: connections.map { Edge(from: $0.fromNodeId, to: $0.toNodeId, gain: $0.gain) },
            start: startID, end: endID, autoConnect: autoConnectEnd)
        if key != next {
            cached = GraphRoutingPlan(nodes: nodes, connections: connections,
                startID: startID, endID: endID, autoConnectEnd: autoConnectEnd)
            key = next
        }
        return cached
    }
}
