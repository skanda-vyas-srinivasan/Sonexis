import SwiftUI
import AppKit

extension CanvasView {
    func changeGraphMode(to mode: GraphMode) {
        guard graphMode != mode else { return }
        if mode == .split {
            // Enter Dual Mono with an empty workspace instead of assigning
            // the stereo chain to channels based on canvas positions.
            clearGraphContents()
        }
        graphMode = mode
    }

    func changeWiringMode(to mode: WiringMode) {
        guard wiringMode != mode else { return }
        if mode == .manual {
            // Materialize the currently generated edges, including gain overrides
            // and both split lanes, before leaving Automatic.
            manualConnections = chainPath(for: .left).isEmpty ? [] : autoConnections(for: .left)
            if graphMode == .split {
                if !chainPath(for: .right).isEmpty {
                    manualConnections += autoConnections(for: .right)
                }
            }
        }
        selectedWireID = nil
        selectedAutoWire = nil
        activeConnectionFromID = nil
        activeConnectionPoint = .zero
        wiringMode = mode
    }

    func autoConnections(for lane: GraphLane) -> [BeginnerConnection] {
        let ordered = chainPath(for: lane)
        let startID = startNodeID(for: lane)
        let endID = endNodeID(for: lane)
        guard !ordered.isEmpty else {
            return [
                BeginnerConnection(
                    fromNodeId: startID,
                    toNodeId: endID,
                    gain: autoGain(for: startID, toID: endID)
                )
            ]
        }

        var connections: [BeginnerConnection] = []
        connections.append(
            BeginnerConnection(
                fromNodeId: startID,
                toNodeId: ordered[0].id,
                gain: autoGain(for: startID, toID: ordered[0].id)
            )
        )
        for index in 0..<(ordered.count - 1) {
            connections.append(
                BeginnerConnection(
                    fromNodeId: ordered[index].id,
                    toNodeId: ordered[index + 1].id,
                    gain: autoGain(for: ordered[index].id, toID: ordered[index + 1].id)
                )
            )
        }
        connections.append(
            BeginnerConnection(
                fromNodeId: ordered[ordered.count - 1].id,
                toNodeId: endID,
                gain: autoGain(for: ordered[ordered.count - 1].id, toID: endID)
            )
        )
        return connections
    }

    func levelForNode(_ id: UUID) -> Float {
        audioEngine.effectLevels[id] ?? 0
    }

    func updateNodePosition(_ id: UUID, position: CGPoint) {
        guard let index = effectChain.firstIndex(where: { $0.id == id }) else { return }
        effectChain[index].position = position
    }

    func moveSelectedNodes(by delta: CGSize, in size: CGSize) {
        for (id, startPos) in selectionDragStartPositions {
            let newPosition = CGPoint(
                x: startPos.x + delta.width,
                y: startPos.y + delta.height
            )
            let lane = effectChain.first(where: { $0.id == id })?.lane
            updateNodePosition(
                id,
                position: clampNodePosition(
                    newPosition,
                    id: id,
                    to: size,
                    lane: graphMode == .split ? lane : nil
                )
            )
        }
    }

    func displayNodePosition(_ node: BeginnerNode, in size: CGSize) -> CGPoint {
        var position = nodePosition(node, in: size)
        if let lift = expandedControlPanelLifts[node.id] {
            position.y -= lift
        }
        return position
    }

    func zoomIn() {
        nodeScale = min(nodeScale + 0.1, 1.8)
        nodeStartScale = nodeScale
    }

    func zoomOut() {
        nodeScale = max(nodeScale - 0.1, 0.4)
        nodeStartScale = nodeScale
    }

    func selectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    var visibleCanvasRect: CGRect {
        guard canvasFrameInRoot.width > 0, canvasDocumentFrameInRoot.width > 0 else {
            return CGRect(origin: .zero, size: canvasSize)
        }
        return CanvasViewportLayout.visibleRect(viewport: canvasFrameInRoot, document: canvasDocumentFrameInRoot)
    }

    func menuAdjusted(_ menu: CustomContextMenu) -> CustomContextMenu {
        menuAtPoint(menu, point: menu.position)
    }

    func menuAtPoint(
        _ menu: CustomContextMenu,
        point: CGPoint,
        gap: CGFloat = 8
    ) -> CustomContextMenu {
        let position = CanvasViewportLayout.contextMenuPosition(
            click: point,
            size: menu.size,
            visibleRect: visibleCanvasRect,
            gap: gap
        )
        return CustomContextMenu(anchor: menu.anchor, position: position, tint: menu.tint, items: menu.items)
    }

    func updateSelection(in rect: CGRect, additive: Bool) {
        let matched = effectChain.filter { node in
            rect.intersects(selectionHitRect(for: node, in: canvasSize))
        }
        if additive {
            selectedNodeIDs.formUnion(matched.map { $0.id })
        } else {
            selectedNodeIDs = Set(matched.map { $0.id })
        }
    }

    func selectionHitRect(for node: BeginnerNode, in size: CGSize) -> CGRect {
        let center = displayNodePosition(node, in: size)
        let tileSize = CGSize(
            width: effectEndpointVisualSize.width * nodeScale,
            height: effectEndpointVisualSize.height * nodeScale
        )
        return CGRect(
            x: center.x - tileSize.width * 0.5,
            y: center.y - tileSize.height * 0.5,
            width: tileSize.width,
            height: tileSize.height
        )
    }

    func handleRightClick(at point: CGPoint, in size: CGSize) {
        if tutorial.isBuildStep && ![.buildRightClick, .buildCloseContextMenu, .buildSelection, .buildWireLevels].contains(tutorial.step) {
            return
        }
        // Check nodes
        let nodeRadius: CGFloat = 60 * nodeScale
        if let hitNode = effectChain.first(where: { node in
            let pos = displayNodePosition(node, in: size)
            return hypot(point.x - pos.x, point.y - pos.y) <= nodeRadius
        }) {
            if tutorial.step == .buildWireLevels { return }
            if tutorial.step == .buildRightClick && hitNode.type != .bassBoost {
                return
            }
            let canUseBatchSelection = selectedNodeIDs.count > 1 && selectedNodeIDs.contains(hitNode.id)
            let batchIDs = selectedNodeIDs
            var items: [CustomContextMenu.Item] = [
                CustomContextMenu.Item(
                    title: "Delete",
                    role: .destructive,
                    action: { removeEffect(id: hitNode.id) }
                )
            ]
            if canUseBatchSelection {
                items.append(
                    CustomContextMenu.Item(
                        title: "Delete all selected blocks",
                        role: .destructive,
                        action: { removeEffects(ids: batchIDs) }
                    )
                )
            }
            items.append(
                CustomContextMenu.Item(
                    title: "Duplicate",
                    role: nil,
                    action: { duplicateEffect(id: hitNode.id) }
                )
            )
            if canUseBatchSelection {
                items.append(
                    CustomContextMenu.Item(
                        title: "Duplicate all selected blocks",
                        role: nil,
                        action: { duplicateEffects(ids: batchIDs) }
                    )
                )
            }
            items.append(
                CustomContextMenu.Item(
                    title: "Reset Params",
                    role: nil,
                    action: { resetEffectParameters(id: hitNode.id) }
                )
            )
            if wiringMode == .manual {
                items.insert(
                    CustomContextMenu.Item(
                        title: "Clear Wires",
                        role: nil,
                        action: { removeWires(for: hitNode.id) }
                    ),
                    at: canUseBatchSelection ? 2 : 1
                )
            }
            let tint = accentPalette[hitNode.accentIndex % accentPalette.count].fill
            let menu = CustomContextMenu(anchor: displayNodePosition(hitNode, in: size), position: point, tint: tint, items: items)
            wireContextMenu = nil
            customContextMenu = menuAdjusted(menu)
            tutorial.advanceIf(.buildRightClick)
            return
        }

        // Wires (manual/auto) - after node hits
        if wiringMode == .manual {
            let connections = graphMode == .split
                ? (visualManualConnections(in: size, lane: .left) + visualManualConnections(in: size, lane: .right))
                : visualManualConnections(in: size, lane: nil)
            if let hit = connections.first(where: { $0.isManual && distanceToSegment(point, $0.from, $0.to) <= 16 }) {
                let midpoint = CGPoint(x: (hit.from.x + hit.to.x) * 0.5, y: (hit.from.y + hit.to.y) * 0.5)
                let menu = CustomContextMenu(
                    anchor: midpoint,
                    position: point,
                    tint: AppColors.neonCyan,
                    items: [
                        CustomContextMenu.Item(
                            title: "Delete Wire",
                            role: .destructive,
                            action: { deleteManualConnection(hit.id) }
                        ),
                        CustomContextMenu.Item(
                            title: "Wire Gain",
                            role: nil,
                            action: {
                                selectedAutoWire = nil
                                selectedWireID = hit.id
                                wireGainPopoverAnchor = point
                            }
                        )
                    ]
                )
                customContextMenu = nil
                wireContextMenu = menuAtPoint(menu, point: point, gap: -wireContextMenuOverlap)
                return
            }
        } else {
            let autoConnections = graphMode == .split
                ? (connectionsForCanvas(path: chainPath(for: .left), lane: .left) +
                   connectionsForCanvas(path: chainPath(for: .right), lane: .right))
                : connectionsForCanvas(path: chainPath(for: nil), lane: nil)
            if let hit = autoConnections.first(where: { distanceToSegment(point, $0.from, $0.to) <= 16 }) {
                let midpoint = CGPoint(
                    x: (hit.from.x + hit.to.x) * 0.5,
                    y: (hit.from.y + hit.to.y) * 0.5 - 28
                )
                let wireKey = WireKey(from: hit.fromNodeId, to: hit.toNodeId)
                let menu = CustomContextMenu(
                    anchor: midpoint,
                    position: point,
                    tint: AppColors.neonCyan,
                    items: [
                        CustomContextMenu.Item(
                            title: "Wire Gain",
                            role: nil,
                            action: {
                                selectedWireID = nil
                                selectedAutoWire = AutoWireSelection(
                                    key: wireKey,
                                    popoverAnchor: point,
                                    tint: AppColors.neonCyan
                                )
                                wireGainPopoverAnchor = point
                            }
                        )
                    ]
                )
                customContextMenu = nil
                wireContextMenu = menuAtPoint(menu, point: point, gap: -wireContextMenuOverlap)
                return
            }
        }

        // Start/End nodes (manual wiring only)
        if wiringMode == .manual {
            let startPos = startNodePosition(in: size, lane: nil)
            if hypot(point.x - startPos.x, point.y - startPos.y) <= 40 {
                let menu = CustomContextMenu(
                    anchor: startPos,
                    position: point,
                    tint: AppColors.neonCyan,
                    items: [
                        CustomContextMenu.Item(
                            title: "Clear Wires",
                            role: nil,
                            action: { removeWires(for: startNodeID) }
                        )
                    ]
                )
                wireContextMenu = nil
                customContextMenu = menuAdjusted(menu)
                return
            }

            let endPos = endNodePosition(in: size, lane: nil)
            if hypot(point.x - endPos.x, point.y - endPos.y) <= 40 {
                let menu = CustomContextMenu(
                    anchor: endPos,
                    position: point,
                    tint: AppColors.neonPink,
                    items: [
                        CustomContextMenu.Item(
                            title: "Clear Wires",
                            role: nil,
                            action: { removeWires(for: endNodeID) }
                        )
                    ]
                )
                wireContextMenu = nil
                customContextMenu = menuAdjusted(menu)
                return
            }
        }

        if selectedNodeIDs.count > 1 {
            let batchIDs = selectedNodeIDs
            let menu = CustomContextMenu(
                anchor: point,
                position: point,
                tint: AppColors.neonPink,
                items: [
                    CustomContextMenu.Item(
                        title: "Delete all selected blocks",
                        role: .destructive,
                        action: { removeEffects(ids: batchIDs) }
                    ),
                    CustomContextMenu.Item(
                        title: "Duplicate all selected blocks",
                        role: nil,
                        action: { duplicateEffects(ids: batchIDs) }
                    )
                ]
            )
            wireContextMenu = nil
            customContextMenu = menuAtPoint(menu, point: point)
            return
        }

        customContextMenu = nil
        wireContextMenu = nil
    }

    func distanceToSegment(_ p: CGPoint, _ v: CGPoint, _ w: CGPoint) -> CGFloat {
        let l2 = pow(v.x - w.x, 2) + pow(v.y - w.y, 2)
        guard l2 > 0 else { return hypot(p.x - v.x, p.y - v.y) }
        let t = max(0, min(1, ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2))
        let proj = CGPoint(x: v.x + t * (w.x - v.x), y: v.y + t * (w.y - v.y))
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    func toggleSelection(_ id: UUID) {
        if selectedNodeIDs.contains(id) {
            selectedNodeIDs.remove(id)
        } else {
            selectedNodeIDs.insert(id)
        }
    }

    func clearGraphSelection() {
        selectedNodeIDs.removeAll()
        selectedWireID = nil
        selectedAutoWire = nil
    }

    func removeWires(for nodeID: UUID) {
        manualConnections.removeAll { $0.fromNodeId == nodeID || $0.toNodeId == nodeID }
        normalizeOutgoingGains(from: nodeID)
        applyChainToEngine()
    }

    func deleteManualConnection(_ id: UUID) {
        if let connection = manualConnections.first(where: { $0.id == id }) {
            manualConnections.removeAll { $0.id == id }
            normalizeOutgoingGains(from: connection.fromNodeId)
        }
        applyChainToEngine()
    }

    func handleKeyDown(_ event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectedNodeIDs = Set(effectChain.map { $0.id })
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            guard !selectedNodeIDs.isEmpty else { return }
            removeEffects(ids: selectedNodeIDs)
        }

        handleBetaUnlock(event)
    }

    func handleBetaUnlock(_ event: NSEvent) {
        guard !audioEngine.betaRecordingUnlocked else { return }
        let blocked: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(blocked).isEmpty else { return }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else { return }

        for scalar in chars.unicodeScalars where CharacterSet.letters.contains(scalar) {
            betaUnlockBuffer.append(Character(scalar))
        }

        if betaUnlockBuffer.count > betaUnlockPhrase.count {
            betaUnlockBuffer = String(betaUnlockBuffer.suffix(betaUnlockPhrase.count))
        }

        if betaUnlockBuffer == betaUnlockPhrase {
            audioEngine.betaRecordingUnlocked = true
        }
    }

    func clearCanvas() {
        guard canUseClearCanvasAction else { return }

        clearGraphContents()
        applyChainToEngine()
        tutorial.advanceIf(.buildClearCanvasForDualMono)
    }

    func clearGraphContents() {
        effectChain.removeAll()
        manualConnections.removeAll()
        autoGainOverrides.removeAll()
        selectedNodeIDs.removeAll()
        expandedControlPanelLifts.removeAll()
        selectedWireID = nil
        selectedAutoWire = nil
        activeConnectionFromID = nil
        activeConnectionPoint = .zero
        customContextMenu = nil
        wireContextMenu = nil
        nextAccentIndex = 0
    }

    func resetWiring() {
        guard canUseResetWiringAction else { return }

        manualConnections.removeAll()
        autoGainOverrides.removeAll()
        selectedWireID = nil
        selectedAutoWire = nil
        applyChainToEngine()
        tutorial.advanceIf(.buildResetWiringForParallel)
    }

    func normalizeAllOutgoingGains() {
        guard wiringMode == .manual else { return }
        let sources = Set(manualConnections.map { $0.fromNodeId })
        for source in sources {
            normalizeOutgoingGains(from: source)
        }
    }

    func normalizeOutgoingGains(from fromID: UUID) {
        guard wiringMode == .manual else { return }
        let outgoing = manualConnections.filter { $0.fromNodeId == fromID }
        guard !outgoing.isEmpty else { return }
        let gain = 1.0 / Double(outgoing.count)
        for index in manualConnections.indices {
            if manualConnections[index].fromNodeId == fromID {
                manualConnections[index].gain = gain
            }
        }
    }

    func gainBinding(for wireID: UUID) -> Binding<Double>? {
        guard let index = manualConnections.firstIndex(where: { $0.id == wireID }) else {
            return nil
        }
        return Binding(
            get: { manualConnections[index].gain },
            set: { newValue in
                let previous = manualConnections[index].gain
                manualConnections[index].gain = min(max(newValue, 0), 1)
                applyChainToEngine()
                if manualConnections[index].gain != previous { tutorial.didAdjustWireGain() }
            }
        )
    }

    func autoGainBinding(for key: WireKey) -> Binding<Double>? {
        Binding(
            get: { autoGainOverrides[key] ?? 1.0 },
            set: { newValue in
                autoGainOverrides[key] = min(max(newValue, 0), 1)
                applyChainToEngine()
            }
        )
    }

    func autoGain(for fromID: UUID, toID: UUID) -> Double {
        autoGainOverrides[WireKey(from: fromID, to: toID)] ?? 1.0
    }

    func manualConnection(for wireID: UUID) -> CanvasConnection? {
        guard let connection = manualConnections.first(where: { $0.id == wireID }) else { return nil }
        let size = canvasSize
        let lane = laneForConnection(connection)

        let fromPoint: CGPoint
        if connection.fromNodeId == startNodeID || connection.fromNodeId == leftStartNodeID || connection.fromNodeId == rightStartNodeID {
            fromPoint = startNodePosition(in: size, lane: lane)
        } else if let node = effectChain.first(where: { $0.id == connection.fromNodeId }) {
            fromPoint = displayNodePosition(node, in: size)
        } else {
            return nil
        }

        let toPoint: CGPoint
        if connection.toNodeId == endNodeID || connection.toNodeId == leftEndNodeID || connection.toNodeId == rightEndNodeID {
            toPoint = endNodePosition(in: size, lane: lane)
        } else if let node = effectChain.first(where: { $0.id == connection.toNodeId }) {
            toPoint = displayNodePosition(node, in: size)
        } else {
            return nil
        }

        return CanvasConnection(
            id: connection.id,
            fromNodeId: connection.fromNodeId,
            from: fromPoint,
            toNodeId: connection.toNodeId,
            to: toPoint,
            isManual: true
        )
    }

    func visualManualConnections(in size: CGSize, lane: GraphLane?) -> [CanvasConnection] {
        var connections: [CanvasConnection] = []

        for connection in manualConnections {
            if graphMode == .split {
                guard laneForConnection(connection) == lane else { continue }
            }
            let fromPoint: CGPoint
            if connection.fromNodeId == startNodeID || connection.fromNodeId == leftStartNodeID || connection.fromNodeId == rightStartNodeID {
                fromPoint = startNodePosition(in: size, lane: lane)
            } else if let node = effectChain.first(where: { $0.id == connection.fromNodeId }) {
                fromPoint = displayNodePosition(node, in: size)
            } else {
                continue
            }

            let toPoint: CGPoint
            if connection.toNodeId == endNodeID || connection.toNodeId == leftEndNodeID || connection.toNodeId == rightEndNodeID {
                toPoint = endNodePosition(in: size, lane: lane)
            } else if let node = effectChain.first(where: { $0.id == connection.toNodeId }) {
                toPoint = displayNodePosition(node, in: size)
            } else {
                continue
            }

            connections.append(
                CanvasConnection(
                    id: connection.id,
                    fromNodeId: connection.fromNodeId,
                    from: fromPoint,
                    toNodeId: connection.toNodeId,
                    to: toPoint,
                    isManual: true
                )
            )
        }

        if wiringMode == .manual {
            for nodeID in implicitEndNodes(lane: lane) {
                guard let node = effectChain.first(where: { $0.id == nodeID }) else { continue }
                let fromPoint = displayNodePosition(node, in: size)
                let toPoint = endNodePosition(in: size, lane: lane)
                connections.append(
                    CanvasConnection(
                        id: UUID(),
                        fromNodeId: nodeID,
                        from: fromPoint,
                        toNodeId: endNodeID(for: lane),
                        to: toPoint,
                        isManual: false
                    )
                )
            }
        }

        return connections
    }

}
