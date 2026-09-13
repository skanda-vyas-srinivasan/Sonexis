import SwiftUI
import AppKit

extension CanvasView {
    func connectionsForCanvas(path ordered: [BeginnerNode], lane: GraphLane?) -> [CanvasConnection] {
        guard !ordered.isEmpty else { return [] }

        let startPoint = startNodePosition(in: canvasSize, lane: lane)
        let endPoint = endNodePosition(in: canvasSize, lane: lane)

        var connections: [CanvasConnection] = []
        var previousPoint = startPoint
        var previousNodeId: UUID? = nil

        for node in ordered {
            let currentPoint = displayNodePosition(node, in: canvasSize)
            connections.append(
                CanvasConnection(
                    id: UUID(),
                    fromNodeId: previousNodeId ?? startNodeID(for: lane),
                    from: previousPoint,
                    toNodeId: node.id,
                    to: currentPoint,
                    isManual: false
                )
            )
            previousPoint = currentPoint
            previousNodeId = node.id
        }

        if let last = ordered.last {
            connections.append(
                CanvasConnection(
                    id: UUID(),
                    fromNodeId: last.id,
                    from: previousPoint,
                    toNodeId: endNodeID(for: lane),
                    to: endPoint,
                    isManual: false
                )
            )
        }

        return connections
    }

    func laneBounds(in size: CGSize, lane: GraphLane) -> CGRect {
        let midX = size.width * 0.5
        switch lane {
        case .left:
            return CGRect(x: 0, y: 0, width: midX, height: size.height)
        case .right:
            return CGRect(x: midX, y: 0, width: size.width - midX, height: size.height)
        }
    }

    func defaultNodePosition(in size: CGSize, lane: GraphLane?) -> CGPoint {
        if graphMode == .split, let lane {
            let bounds = laneBounds(in: size, lane: lane)
            return CGPoint(x: max(bounds.midX, 100), y: max(bounds.midY, 100))
        }
        return CGPoint(x: max(size.width * 0.5, 100), y: max(size.height * 0.5, 100))
    }

    func startNodePosition(in size: CGSize, lane: GraphLane?) -> CGPoint {
        if graphMode == .split, let lane {
            let bounds = laneBounds(in: size, lane: lane)
            return CGPoint(x: bounds.minX + 80, y: bounds.midY)
        }
        return CGPoint(x: 80, y: size.height * 0.5)
    }

    func endNodePosition(in size: CGSize, lane: GraphLane?) -> CGPoint {
        if graphMode == .split, let lane {
            let viewportSize = CGSize(
                width: canvasFrameInRoot.width > 0 ? min(canvasFrameInRoot.width, size.width) : size.width,
                height: size.height
            )
            let bounds = laneBounds(in: viewportSize, lane: lane)
            let x = max(bounds.maxX - 80, bounds.minX + 80)
            return CGPoint(x: x, y: bounds.midY)
        }
        return CGPoint(
            x: CanvasViewportLayout.terminalX(
                viewportWidth: canvasFrameInRoot.width,
                documentWidth: size.width
            ),
            y: size.height * 0.5
        )
    }

    func endpointVisualSize(for nodeID: UUID) -> CGSize {
        if isTerminalNode(nodeID) {
            return terminalEndpointVisualSize
        }
        return CGSize(
            width: effectEndpointVisualSize.width * nodeScale,
            height: effectEndpointVisualSize.height * nodeScale
        )
    }

    func isTerminalNode(_ nodeID: UUID) -> Bool {
        nodeID == startNodeID ||
            nodeID == endNodeID ||
            nodeID == leftStartNodeID ||
            nodeID == leftEndNodeID ||
            nodeID == rightStartNodeID ||
            nodeID == rightEndNodeID
    }

    func clampNodePosition(_ point: CGPoint, id: UUID, to size: CGSize, lane: GraphLane?) -> CGPoint {
        let visualLift = expandedControlPanelLifts[id] ?? 0
        return clamp(
            point,
            to: size,
            lane: lane,
            topPadding: 80 + visualLift
        )
    }

    func clamp(_ point: CGPoint, to size: CGSize, lane: GraphLane?, topPadding: CGFloat? = nil) -> CGPoint {
        let padding: CGFloat = 80
        let resolvedTopPadding = topPadding ?? padding
        if graphMode == .split, let lane {
            let bounds = laneBounds(in: size, lane: lane)
            let x = min(max(point.x, bounds.minX + padding), max(bounds.maxX - padding, bounds.minX + padding))
            let y = min(max(point.y, resolvedTopPadding), max(size.height - padding, resolvedTopPadding))
            return CGPoint(x: x, y: y)
        }
        let x = min(max(point.x, padding), max(size.width - padding, padding))
        let y = min(max(point.y, resolvedTopPadding), max(size.height - padding, resolvedTopPadding))
        return CGPoint(x: x, y: y)
    }

    func connectionPreviewStartPoint(in size: CGSize) -> CGPoint? {
        guard let fromID = activeConnectionFromID else { return nil }
        if fromID == startNodeID {
            return startNodePosition(in: size, lane: nil)
        }
        if fromID == leftStartNodeID {
            return startNodePosition(in: size, lane: .left)
        }
        if fromID == rightStartNodeID {
            return startNodePosition(in: size, lane: .right)
        }
        if let fromNode = effectChain.first(where: { $0.id == fromID }) {
            return displayNodePosition(fromNode, in: size)
        }
        return nil
    }

    func finalizeConnection(from fromID: UUID, dropPoint: CGPoint) {

        defer {
            activeConnectionFromID = nil
            activeConnectionPoint = .zero
        }

        guard let targetID = nearestConnectionTarget(from: fromID, at: dropPoint),
              targetID != fromID
        else {
            return
        }

        if graphMode == .split {
            let fromLane = laneForNodeID(fromID)
            let toLane = laneForNodeID(targetID)
            guard fromLane == toLane, fromLane != nil else {
                return
            }
        }

        guard tutorialAllowsConnection(from: fromID, to: targetID) else {
            return
        }

        guard !createsCycle(from: fromID, to: targetID) else {
            return
        }

        if wiringMode == .automatic {
            manualConnections.removeAll { $0.fromNodeId == fromID || $0.toNodeId == targetID }
        } else {
            manualConnections.removeAll { $0.fromNodeId == fromID && $0.toNodeId == targetID }
        }
        manualConnections.append(BeginnerConnection(fromNodeId: fromID, toNodeId: targetID))
        if wiringMode == .manual {
            normalizeOutgoingGains(from: fromID)
        }
        applyChainToEngine()
        if tutorial.step == .buildConnect, shouldAdvanceConnectTutorial() {
            tutorial.advance()
        } else if tutorial.step == .buildParallelConnect, shouldAdvanceParallelTutorial() {
            tutorial.advance()
        } else if tutorial.step == .buildDualMonoConnect, shouldAdvanceDualMonoConnectTutorial() {
            tutorial.advance()
        }
    }

    func shouldAdvanceConnectTutorial() -> Bool {
        // Tutorial expectation: Start → Bass Boost → End (stereo graph, manual wiring).
        guard let bassNode = effectChain.first(where: { $0.type == .bassBoost }) else { return false }
        let hasStartToBass = manualConnections.contains { $0.fromNodeId == startNodeID && $0.toNodeId == bassNode.id }
        let hasBassToEnd = manualConnections.contains { $0.fromNodeId == bassNode.id && $0.toNodeId == endNodeID }
        return hasStartToBass && hasBassToEnd
    }

    struct TutorialEdge: Hashable {
        let from: UUID
        let to: UUID
    }

    func tutorialAllowsConnection(from: UUID, to: UUID) -> Bool {
        switch tutorial.step {
        case .buildConnect:
            guard let bassNode = effectChain.first(where: { $0.type == .bassBoost }) else { return false }
            let allowed: Set<TutorialEdge> = [
                TutorialEdge(from: startNodeID, to: bassNode.id),
                TutorialEdge(from: bassNode.id, to: endNodeID)
            ]
            return allowed.contains(TutorialEdge(from: from, to: to))

        case .buildParallelConnect:
            guard
                let bassNode = effectChain.first(where: { $0.type == .bassBoost }),
                let clarityNode = effectChain.first(where: { $0.type == .clarity }),
                let reverbNode = effectChain.first(where: { $0.type == .reverb })
            else { return false }

            let allowed: Set<TutorialEdge> = [
                TutorialEdge(from: startNodeID, to: bassNode.id),
                TutorialEdge(from: startNodeID, to: clarityNode.id),
                TutorialEdge(from: bassNode.id, to: reverbNode.id),
                TutorialEdge(from: clarityNode.id, to: reverbNode.id),
                TutorialEdge(from: reverbNode.id, to: endNodeID)
            ]
            return allowed.contains(TutorialEdge(from: from, to: to))

        case .buildDualMonoConnect:
            guard
                graphMode == .split,
                let bassNode = effectChain.first(where: { $0.type == .bassBoost && $0.lane == .left }),
                let clarityNode = effectChain.first(where: { $0.type == .clarity && $0.lane == .right })
            else { return false }

            let allowed: Set<TutorialEdge> = [
                TutorialEdge(from: leftStartNodeID, to: bassNode.id),
                TutorialEdge(from: bassNode.id, to: leftEndNodeID),
                TutorialEdge(from: rightStartNodeID, to: clarityNode.id),
                TutorialEdge(from: clarityNode.id, to: rightEndNodeID)
            ]
            return allowed.contains(TutorialEdge(from: from, to: to))

        default:
            return true
        }
    }

    func shouldAdvanceParallelTutorial() -> Bool {
        guard
            let bassNode = effectChain.first(where: { $0.type == .bassBoost }),
            let clarityNode = effectChain.first(where: { $0.type == .clarity }),
            let reverbNode = effectChain.first(where: { $0.type == .reverb })
        else { return false }

        let required: Set<TutorialEdge> = [
            TutorialEdge(from: startNodeID, to: bassNode.id),
            TutorialEdge(from: startNodeID, to: clarityNode.id),
            TutorialEdge(from: bassNode.id, to: reverbNode.id),
            TutorialEdge(from: clarityNode.id, to: reverbNode.id),
            TutorialEdge(from: reverbNode.id, to: endNodeID)
        ]

        let existing = Set(manualConnections.map { TutorialEdge(from: $0.fromNodeId, to: $0.toNodeId) })
        return required.isSubset(of: existing)
    }

    func shouldAdvanceDualMonoConnectTutorial() -> Bool {
        guard
            graphMode == .split,
            let bassNode = effectChain.first(where: { $0.type == .bassBoost && $0.lane == .left }),
            let clarityNode = effectChain.first(where: { $0.type == .clarity && $0.lane == .right })
        else { return false }

        let required: Set<TutorialEdge> = [
            TutorialEdge(from: leftStartNodeID, to: bassNode.id),
            TutorialEdge(from: bassNode.id, to: leftEndNodeID),
            TutorialEdge(from: rightStartNodeID, to: clarityNode.id),
            TutorialEdge(from: clarityNode.id, to: rightEndNodeID)
        ]

        let existing = Set(manualConnections.map { TutorialEdge(from: $0.fromNodeId, to: $0.toNodeId) })
        return required.isSubset(of: existing)
    }

    func maybeAdvanceAutoReorderTutorial() {
        guard tutorial.step == .buildAutoReorder else { return }
        guard let bass = effectChain.first(where: { $0.type == .bassBoost }),
              let clarity = effectChain.first(where: { $0.type == .clarity })
        else { return }
        let bassPos = displayNodePosition(bass, in: canvasSize)
        let clarityPos = displayNodePosition(clarity, in: canvasSize)
        if clarityPos.x > bassPos.x {
            tutorial.advance()
        }
    }

    func maybeAdvanceDualMonoTutorial() {
        guard tutorial.step == .buildDualMonoAdd else { return }
        guard graphMode == .split else { return }

        let hasLeftBass = effectChain.contains { node in
            node.type == .bassBoost && node.lane == .left
        }
        let hasRightClarity = effectChain.contains { node in
            node.type == .clarity && node.lane == .right
        }

        if hasLeftBass && hasRightClarity {
            tutorial.advance()
        }
    }

    func nearestConnectionTarget(from fromID: UUID, at point: CGPoint) -> UUID? {
        var closest: (id: UUID, distance: CGFloat)?
        let fromLane = laneForNodeID(fromID)
        let nodeSize: CGFloat = 110 * nodeScale

        for node in effectChain {
            if graphMode == .split, let fromLane, node.lane != fromLane {
                continue
            }
            let nodePoint = displayNodePosition(node, in: canvasSize)
            let rect = CGRect(
                x: nodePoint.x - nodeSize * 0.5,
                y: nodePoint.y - nodeSize * 0.5,
                width: nodeSize,
                height: nodeSize
            )
            guard rect.contains(point) else { continue }
            let dx = nodePoint.x - point.x
            let dy = nodePoint.y - point.y
            let distance = sqrt(dx * dx + dy * dy)
            if closest == nil || distance < closest!.distance {
                closest = (node.id, distance)
            }
        }

        let endID = graphMode == .split ? endNodeID(for: fromLane) : endNodeID
        if fromID != endID {
            let endPoint = endNodePosition(in: canvasSize, lane: fromLane)
            let endSize: CGFloat = 80
            let rect = CGRect(
                x: endPoint.x - endSize * 0.5,
                y: endPoint.y - endSize * 0.5,
                width: endSize,
                height: endSize
            )
            if rect.contains(point) {
                let dx = endPoint.x - point.x
                let dy = endPoint.y - point.y
                let distance = sqrt(dx * dx + dy * dy)
                if closest == nil || distance < closest!.distance {
                    closest = (endID, distance)
                }
            }
        }
        return closest?.id
    }

    func createsCycle(from: UUID, to: UUID) -> Bool {
        var outEdges: [UUID: [UUID]] = [:]
        for connection in manualConnections {
            outEdges[connection.fromNodeId, default: []].append(connection.toNodeId)
        }
        outEdges[from, default: []].append(to)

        var visited: Set<UUID> = []
        var queue: [UUID] = [to]

        while let current = queue.first {
            queue.removeFirst()
            if current == from { return true }
            if visited.contains(current) { continue }
            visited.insert(current)
            for next in outEdges[current] ?? [] {
                queue.append(next)
            }
        }
        return false
    }

    func buildNextMap(for lane: GraphLane?) -> [UUID: UUID] {
        var nextMap: [UUID: UUID] = [:]

        let ordered = orderedNodesByPosition(lane: lane)
        guard !ordered.isEmpty else { return nextMap }

        let startID = startNodeID(for: lane)
        let endID = endNodeID(for: lane)
        nextMap[startID] = ordered[0].id
        for index in 0..<(ordered.count - 1) {
            nextMap[ordered[index].id] = ordered[index + 1].id
        }
        nextMap[ordered[ordered.count - 1].id] = endID

        // Automatic routing follows node positions; manual edges never override it.
        return nextMap
    }

    func chainPath(for lane: GraphLane?) -> [BeginnerNode] {
        let nextMap = buildNextMap(for: lane)
        let startID = startNodeID(for: lane)
        let endID = endNodeID(for: lane)
        guard let first = nextMap[startID] else { return [] }

        var ordered: [BeginnerNode] = []
        var visited = Set<UUID>([startID])
        var current = first

        while current != endID {
            if visited.contains(current) { break }
            visited.insert(current)
            guard let node = effectChain.first(where: { $0.id == current }) else { break }
            ordered.append(node)
            guard let next = nextMap[current] else { break }
            current = next
        }
        return ordered
    }

    func reachableNodeIDsFromStart() -> Set<UUID> {
        guard wiringMode == .manual else { return [] }
        if graphMode == .split {
            let left = reachableNodeIDs(from: .left)
            let right = reachableNodeIDs(from: .right)
            return left.union(right)
        }
        return reachableNodeIDs(from: nil)
    }

    func reachableNodeIDs(from lane: GraphLane?) -> Set<UUID> {
        var outEdges: [UUID: [UUID]] = [:]
        for connection in manualConnections {
            if graphMode == .split, laneForConnection(connection) != lane { continue }
            outEdges[connection.fromNodeId, default: []].append(connection.toNodeId)
        }

        let startID = startNodeID(for: lane)
        let endID = endNodeID(for: lane)
        var visited: Set<UUID> = [startID]
        var queue: [UUID] = [startID]

        while let current = queue.first {
            queue.removeFirst()
            for next in outEdges[current] ?? [] {
                if !visited.contains(next) {
                    visited.insert(next)
                    queue.append(next)
                }
            }
        }

        visited.remove(startID)
        visited.remove(endID)
        return visited
    }

    func implicitEndNodes(lane: GraphLane?) -> [UUID] {
        guard wiringMode == .manual && autoConnectEnd else { return [] }
        let reachable = reachableNodeIDs(from: lane)
        var outEdges: [UUID: [UUID]] = [:]
        for connection in manualConnections {
            if graphMode == .split, laneForConnection(connection) != lane { continue }
            outEdges[connection.fromNodeId, default: []].append(connection.toNodeId)
        }

        let endID = endNodeID(for: lane)
        var sinks: [UUID] = []
        for nodeID in reachable {
            let outs = outEdges[nodeID] ?? []
            if outs.isEmpty || !outs.contains(where: { $0 != endID }) {
                if !outs.contains(endID) {
                    sinks.append(nodeID)
                }
            }
        }
        return sinks
    }

    func orderedNodesByPosition(lane: GraphLane?) -> [BeginnerNode] {
        let nodes: [BeginnerNode]
        if graphMode == .split, let lane = lane {
            nodes = effectChain.filter { $0.lane == lane }
        } else {
            nodes = effectChain
        }
        return nodes.sorted { lhs, rhs in
            let lhsPoint = nodePosition(lhs, in: canvasSize)
            let rhsPoint = nodePosition(rhs, in: canvasSize)
            if lhsPoint.x == rhsPoint.x {
                return lhsPoint.y < rhsPoint.y
            }
            return lhsPoint.x < rhsPoint.x
        }
    }

    func laneForPoint(_ point: CGPoint, in size: CGSize) -> GraphLane {
        point.x < size.width * 0.5 ? .left : .right
    }

    func startNodeID(for lane: GraphLane?) -> UUID {
        if graphMode == .split {
            return lane == .right ? rightStartNodeID : leftStartNodeID
        }
        return startNodeID
    }

    func endNodeID(for lane: GraphLane?) -> UUID {
        if graphMode == .split {
            return lane == .right ? rightEndNodeID : leftEndNodeID
        }
        return endNodeID
    }

    func laneForNodeID(_ id: UUID) -> GraphLane? {
        if graphMode == .split {
            if id == leftStartNodeID || id == leftEndNodeID { return .left }
            if id == rightStartNodeID || id == rightEndNodeID { return .right }
            return effectChain.first(where: { $0.id == id })?.lane
        }
        return nil
    }

    func laneForConnection(_ connection: BeginnerConnection) -> GraphLane? {
        guard graphMode == .split else { return nil }
        let fromLane = laneForNodeID(connection.fromNodeId)
        let toLane = laneForNodeID(connection.toNodeId)
        guard fromLane == toLane else { return nil }
        return fromLane
    }

    func syncLanesForSplit() {
        let midX = canvasSize.width * 0.5
        for index in effectChain.indices {
            let position = nodePosition(effectChain[index], in: canvasSize)
            effectChain[index].lane = position.x < midX ? .left : .right
        }
        manualConnections.removeAll { laneForConnection($0) == nil }
    }

    func nodePosition(_ node: BeginnerNode, in size: CGSize) -> CGPoint {
        node.position == .zero ? defaultNodePosition(in: size, lane: graphMode == .split ? node.lane : nil) : node.position
    }

    func setControlPanelLift(for node: BeginnerNode, in size: CGSize) {
        let lift = controlPanelLiftNeeded(for: node, in: size)
        withAnimation(.easeOut(duration: 0.20)) {
            if lift > 0 {
                expandedControlPanelLifts[node.id] = lift
            } else {
                expandedControlPanelLifts.removeValue(forKey: node.id)
            }
        }
    }

    func clearControlPanelLift(for id: UUID) {
        withAnimation(.easeOut(duration: 0.18)) {
            _ = expandedControlPanelLifts.removeValue(forKey: id)
        }
    }

    func controlPanelLiftNeeded(for node: BeginnerNode, in size: CGSize) -> CGFloat {
        guard size.height > 0 else { return 0 }

        let rawPosition = nodePosition(node, in: size)
        let visible = visibleCanvasRect
        guard rawPosition.y > visible.minY + visible.height * 0.64 else { return 0 }

        let panelTop = rawPosition.y + 73 * nodeScale
        let panelBottom = panelTop + estimatedControlPanelHeight(for: node.type)
        let overflow = panelBottom + 16 - visible.maxY
        guard overflow > 0 else { return 0 }

        let topLimit: CGFloat = visible.minY + 82
        let maxLift = max(rawPosition.y - topLimit, 0)
        return min(overflow, maxLift)
    }

    func estimatedControlPanelHeight(for type: EffectType) -> CGFloat {
        let parameterRows = max(1, Int(ceil(Double(parameterCount(for: type)) / 2.0)))
        let gridHeight = min(CGFloat(parameterRows) * 104 + CGFloat(max(0, parameterRows - 1)) * 10, 234)
        return 110 + gridHeight
    }

    func parameterCount(for type: EffectType) -> Int {
        switch type {
        case .enhancer, .bassBoost, .rubberBandPitch, .clarity, .deMud, .stereoWidth:
            return 1
        case .nightDrive, .chromePunch, .midnightGlow, .afterglow, .reverb, .tremolo, .autoPan, .phaser, .tapeSaturation, .resampling:
            return 2
        case .simpleEQ, .appleThreeBandEQ, .delay, .chorus, .bitcrusher:
            return 3
        case .amp, .distortion, .flanger:
            return 4
        case .compressor:
            return 6
        case .tenBandEQ:
            return 10
        case .pitchShift, .plugin:
            return 0
        }
    }
}
