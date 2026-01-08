import SwiftUI

// MARK: - Beginner View

struct BeginnerView: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var effectChain: [BeginnerNode] = []
    @State private var draggedEffectType: EffectType?
    @State private var showSignalFlow = false
    @State private var canvasSize: CGSize = .zero
    @State private var draggingNodeID: UUID?
    @State private var dragStartPosition: CGPoint = .zero
    @State private var manualConnections: [BeginnerConnection] = []
    @State private var activeConnectionFromID: UUID?
    @State private var activeConnectionPoint: CGPoint = .zero
    @State private var wiringMode: WiringMode = .automatic
    @State private var debugChainText: String? = nil
    @State private var selectedNodeIDs: Set<UUID> = []
    @State private var lassoStart: CGPoint?
    @State private var lassoCurrent: CGPoint?
    @State private var selectionDragStartPositions: [UUID: CGPoint] = [:]

    @State private var startNodeID = UUID()
    @State private var endNodeID = UUID()
    private let connectionSnapRadius: CGFloat = 120

    enum WiringMode {
        case automatic  // Position-based with manual override
        case manual     // Pure manual wiring only
    }

    var body: some View {
        let path = wiringMode == .automatic ? chainPath() : manualPathFromStart()
        let pathIDs = Set(path.map { $0.id })

        VStack(spacing: 0) {
            // Effect palette at top
            HStack {
                EffectPalette(
                    onEffectSelected: { type in
                        addEffectToChain(type)
                    },
                    onEffectDragged: { type in
                        draggedEffectType = type
                    }
                )

                Spacer()

                HStack(spacing: 12) {
                    // Mode toggle
                    Picker("Wiring Mode", selection: $wiringMode) {
                        Text("Automatic").tag(WiringMode.automatic)
                        Text("Manual").tag(WiringMode.manual)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .help(wiringMode == .automatic ?
                          "Automatic: Effects flow left-to-right by position. Option+drag to override." :
                          "Manual: Pure manual wiring. Option+drag to connect everything.")
                    .onChange(of: wiringMode) { _ in
                        applyChainToEngine()
                    }

                    Button("Reset Wiring") {
                        manualConnections.removeAll()
                        applyChainToEngine()
                    }
                    .disabled(manualConnections.isEmpty)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Free-placement canvas
            GeometryReader { geometry in
                ZStack {
                    Color(NSColor.textBackgroundColor)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if wiringMode == .manual {
                                selectedNodeIDs.removeAll()
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard wiringMode == .manual else { return }
                                    guard !NSEvent.modifierFlags.contains(.option) else { return }
                                    guard draggingNodeID == nil else { return }

                                    if lassoStart == nil {
                                        lassoStart = value.startLocation
                                    }
                                    lassoCurrent = value.location
                                }
                                .onEnded { _ in
                                    guard wiringMode == .manual else { return }
                                    guard let start = lassoStart, let current = lassoCurrent else {
                                        lassoStart = nil
                                        lassoCurrent = nil
                                        return
                                    }

                                    let rect = selectionRect(from: start, to: current)
                                    let isShift = NSEvent.modifierFlags.contains(.shift)
                                    updateSelection(in: rect, additive: isShift)
                                    lassoStart = nil
                                    lassoCurrent = nil
                                }
                        )

                    // TEMP DEBUG: show DSP chain overlay (remove when wiring UX is finalized).
                    if let chainText = debugChainText {
                        Text(chainText)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }

                    // Subtle grid pattern
                    Canvas { context, size in
                        let spacing: CGFloat = 30
                        context.stroke(
                            Path { path in
                                for x in stride(from: 0, through: size.width, by: spacing) {
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: size.height))
                                }
                                for y in stride(from: 0, through: size.height, by: spacing) {
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: size.width, y: y))
                                }
                            },
                            with: .color(.secondary.opacity(0.05)),
                            lineWidth: 1
                        )
                    }

                    // Draw connections based on mode
                    if wiringMode == .automatic {
                        // In automatic mode, show position-based flow
                        ForEach(connectionsForCanvas(path: path), id: \.id) { connection in
                            FlowLine(
                                from: connection.from,
                                to: connection.to,
                                isActive: audioEngine.isRunning && showSignalFlow,
                                level: levelForNode(connection.toNodeId)
                            )
                        }
                    } else {
                        // In manual mode, show explicit wires (always visible)
                        ForEach(visualManualConnections(in: geometry.size), id: \.id) { connection in
                            FlowLine(
                                from: connection.from,
                                to: connection.to,
                                isActive: audioEngine.isRunning && showSignalFlow,
                                level: levelForNode(connection.toNodeId)
                            )
                            .contextMenu {
                                if connection.isManual {
                                    Button("Delete Wire") {
                                        deleteManualConnection(connection.id)
                                    }
                                }
                            }
                        }
                    }

                    // Draw preview line while dragging
                    if let startPoint = connectionPreviewStartPoint(in: geometry.size) {
                        Path { path in
                            path.move(to: startPoint)
                            path.addLine(to: activeConnectionPoint)
                        }
                        .stroke(Color.blue.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }

                    if let start = lassoStart, let current = lassoCurrent {
                        let rect = selectionRect(from: start, to: current)
                        Rectangle()
                            .path(in: rect)
                            .stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .background(Color.blue.opacity(0.08))
                    }

                    StartNodeView()
                        .position(startNodePosition(in: geometry.size))
                        .contextMenu {
                            if wiringMode == .manual {
                                Button("Delete Node Wires") {
                                    removeWires(for: startNodeID)
                                }
                            }
                        }
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if NSEvent.modifierFlags.contains(.option) {
                                        print("🖱️ START drag with Option held")
                                        let start = startNodePosition(in: geometry.size)
                                        activeConnectionFromID = startNodeID
                                        activeConnectionPoint = CGPoint(
                                            x: start.x + value.translation.width,
                                            y: start.y + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { value in
                                    if NSEvent.modifierFlags.contains(.option) {
                                        print("🖱️ START drag ended with Option")
                                        let start = startNodePosition(in: geometry.size)
                                        let dropPoint = CGPoint(
                                            x: start.x + value.translation.width,
                                            y: start.y + value.translation.height
                                        )
                                        finalizeConnection(from: startNodeID, dropPoint: dropPoint)
                                    } else {
                                        activeConnectionFromID = nil
                                        activeConnectionPoint = .zero
                                    }
                                }
                        )
                    EndNodeView()
                        .position(endNodePosition(in: geometry.size))
                        .contextMenu {
                            if wiringMode == .manual {
                                Button("Delete Node Wires") {
                                    removeWires(for: endNodeID)
                                }
                            }
                        }

                    ForEach(effectChain, id: \.id) { effect in
                        let nodePos = nodePosition(effect, in: geometry.size)
                        let isWired = pathIDs.contains(effect.id)
                        let isSelected = selectedNodeIDs.contains(effect.id)

                        EffectBlockHorizontal(
                            effect: effect,
                            audioEngine: audioEngine,
                            isWired: isWired,
                            isSelected: isSelected,
                            onRemove: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    removeEffect(id: effect.id)
                                }
                            }
                        )
                        .position(nodePos)
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {
                                    guard wiringMode == .manual else { return }
                                    let isShift = NSEvent.modifierFlags.contains(.shift)
                                    if isShift {
                                        toggleSelection(effect.id)
                                    } else {
                                        selectedNodeIDs = [effect.id]
                                    }
                                }
                        )
                        .contextMenu {
                            if wiringMode == .manual {
                                Button("Delete Node") {
                                    removeEffect(id: effect.id)
                                }
                                Button("Delete Node Wires") {
                                    removeWires(for: effect.id)
                                }
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let hasOption = NSEvent.modifierFlags.contains(.option)
                                    if hasOption {
                                        // Wiring mode
                                        print("🖱️ EFFECT drag with Option held")
                                        activeConnectionFromID = effect.id
                                        activeConnectionPoint = CGPoint(
                                            x: nodePos.x + value.translation.width,
                                            y: nodePos.y + value.translation.height
                                        )
                                    } else {
                                        // Move mode
                                        if draggingNodeID != effect.id {
                                            draggingNodeID = effect.id
                                            dragStartPosition = nodePos
                                            if wiringMode == .manual {
                                                if !selectedNodeIDs.contains(effect.id) && !NSEvent.modifierFlags.contains(.shift) {
                                                    selectedNodeIDs = [effect.id]
                                                }
                                                selectionDragStartPositions = selectedNodeIDs.reduce(into: [:]) { result, id in
                                                    if let node = effectChain.first(where: { $0.id == id }) {
                                                        result[id] = nodePosition(node, in: geometry.size)
                                                    }
                                                }
                                            }
                                        }
                                        let delta = CGSize(width: value.translation.width, height: value.translation.height)
                                        if wiringMode == .manual, !selectedNodeIDs.isEmpty {
                                            moveSelectedNodes(by: delta, in: geometry.size)
                                        } else {
                                            let newPosition = CGPoint(
                                                x: dragStartPosition.x + value.translation.width,
                                                y: dragStartPosition.y + value.translation.height
                                            )
                                            updateNodePosition(effect.id, position: clamp(newPosition, to: geometry.size))
                                        }
                                    }
                                }
                                .onEnded { value in
                                    let hasOption = NSEvent.modifierFlags.contains(.option)
                                    if hasOption {
                                        // Finalize wiring
                                        print("🖱️ EFFECT drag ended with Option")
                                        let dropPoint = CGPoint(
                                            x: nodePos.x + value.translation.width,
                                            y: nodePos.y + value.translation.height
                                        )
                                        finalizeConnection(from: effect.id, dropPoint: dropPoint)
                                    } else {
                                        activeConnectionFromID = nil
                                        activeConnectionPoint = .zero
                                        // Finalize move
                                        draggingNodeID = nil
                                        selectionDragStartPositions.removeAll()
                                        applyChainToEngine()
                                    }
                                }
                        )
                    }

                    if effectChain.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.path")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.3))
                            Text("Drop effects anywhere")
                                .font(.title3)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                }
                .onAppear {
                    canvasSize = geometry.size
                }
                .onChange(of: geometry.size) { newSize in
                    canvasSize = newSize
                }
                .contentShape(Rectangle())
                .onDrop(of: [.text], delegate: CanvasDropDelegate(
                    effectChain: $effectChain,
                    draggedEffectType: $draggedEffectType,
                    canvasSize: geometry.size,
                    onAdd: { newNode in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            effectChain.append(newNode)
                            applyChainToEngine()
                        }
                    }
                ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: audioEngine.isRunning) { isRunning in
            showSignalFlow = isRunning
        }
        .contextMenu {
            if wiringMode == .manual && !selectedNodeIDs.isEmpty {
                Button("Delete Selected Nodes") {
                    removeEffects(ids: selectedNodeIDs)
                }
                Button("Delete Wires for Selected") {
                    deleteWiresForSelected()
                }
            }
        }
    }

    private func addEffectToChain(_ type: EffectType) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            let newEffect = BeginnerNode(type: type, position: defaultNodePosition(in: canvasSize))
            effectChain.append(newEffect)
            applyChainToEngine()
        }
    }

    private func removeEffect(id: UUID) {
        effectChain.removeAll { $0.id == id }
        manualConnections.removeAll { $0.fromNodeId == id || $0.toNodeId == id }
        selectedNodeIDs.remove(id)
        applyChainToEngine()
    }

    private func removeEffects(ids: Set<UUID>) {
        effectChain.removeAll { ids.contains($0.id) }
        manualConnections.removeAll { ids.contains($0.fromNodeId) || ids.contains($0.toNodeId) }
        selectedNodeIDs.subtract(ids)
        applyChainToEngine()
    }

    private func deleteWiresForSelected() {
        manualConnections.removeAll { selectedNodeIDs.contains($0.fromNodeId) || selectedNodeIDs.contains($0.toNodeId) }
        applyChainToEngine()
    }

    private func applyChainToEngine() {
        let path = chainPath()
        print("📊 Chain path (\(path.count) effects) - Mode: \(wiringMode == .automatic ? "AUTOMATIC" : "MANUAL")")
        for (index, node) in path.enumerated() {
            print("   \(index + 1). \(node.type.rawValue)")
        }
        print("   Manual connections: \(manualConnections.count)")
        for conn in manualConnections {
            let fromName = conn.fromNodeId == startNodeID ? "START" :
                          (effectChain.first(where: { $0.id == conn.fromNodeId })?.type.rawValue ?? "?")
            let toName = conn.toNodeId == endNodeID ? "END" :
                        (effectChain.first(where: { $0.id == conn.toNodeId })?.type.rawValue ?? "?")
        print("   🔗 \(fromName) → \(toName)")
        }
        audioEngine.updateEffectChain(path)

        // TEMP DEBUG: surface the DSP chain in the UI for visual verification.
        updateDebugChainText(path)
    }

    private func updateDebugChainText(_ path: [BeginnerNode]) {
        if path.isEmpty {
            debugChainText = "DSP chain: (empty)"
            return
        }
        let names = path.map { $0.type.rawValue }.joined(separator: " → ")
        debugChainText = "DSP chain: \(names)"
    }

    private func levelForNode(_ id: UUID) -> Float {
        audioEngine.effectLevels[id] ?? 0
    }

    private func updateNodePosition(_ id: UUID, position: CGPoint) {
        guard let index = effectChain.firstIndex(where: { $0.id == id }) else { return }
        effectChain[index].position = position
    }

    private func moveSelectedNodes(by delta: CGSize, in size: CGSize) {
        for (id, startPos) in selectionDragStartPositions {
            let newPosition = CGPoint(
                x: startPos.x + delta.width,
                y: startPos.y + delta.height
            )
            updateNodePosition(id, position: clamp(newPosition, to: size))
        }
    }

    private func selectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func updateSelection(in rect: CGRect, additive: Bool) {
        let matched = effectChain.filter { node in
            rect.contains(nodePosition(node, in: canvasSize))
        }
        if additive {
            selectedNodeIDs.formUnion(matched.map { $0.id })
        } else {
            selectedNodeIDs = Set(matched.map { $0.id })
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedNodeIDs.contains(id) {
            selectedNodeIDs.remove(id)
        } else {
            selectedNodeIDs.insert(id)
        }
    }

    private func removeWires(for nodeID: UUID) {
        manualConnections.removeAll { $0.fromNodeId == nodeID || $0.toNodeId == nodeID }
        applyChainToEngine()
    }

    private func deleteManualConnection(_ id: UUID) {
        manualConnections.removeAll { $0.id == id }
        applyChainToEngine()
    }

    private func visualManualConnections(in size: CGSize) -> [CanvasConnection] {
        var connections: [CanvasConnection] = []

        for connection in manualConnections {
            let fromPoint: CGPoint
            if connection.fromNodeId == startNodeID {
                fromPoint = startNodePosition(in: size)
            } else if let node = effectChain.first(where: { $0.id == connection.fromNodeId }) {
                fromPoint = nodePosition(node, in: size)
            } else {
                continue
            }

            let toPoint: CGPoint
            if connection.toNodeId == endNodeID {
                toPoint = endNodePosition(in: size)
            } else if let node = effectChain.first(where: { $0.id == connection.toNodeId }) {
                toPoint = nodePosition(node, in: size)
            } else {
                continue
            }

            connections.append(
                CanvasConnection(
                    id: connection.id,
                    from: fromPoint,
                    to: toPoint,
                    toNodeId: connection.toNodeId,
                    isManual: true
                )
            )
        }

        if wiringMode == .manual {
            let manualPath = manualPathFromStart()
            if let lastNode = manualPath.last,
               !manualConnections.contains(where: { $0.fromNodeId == lastNode.id && $0.toNodeId == endNodeID }) {
                let fromPoint = nodePosition(lastNode, in: size)
                let toPoint = endNodePosition(in: size)
                connections.append(
                    CanvasConnection(id: UUID(), from: fromPoint, to: toPoint, toNodeId: endNodeID, isManual: false)
                )
            }
        }

        return connections
    }

    private func connectionsForCanvas(path ordered: [BeginnerNode]) -> [CanvasConnection] {
        guard !ordered.isEmpty else { return [] }

        let startPoint = startNodePosition(in: canvasSize)
        let endPoint = endNodePosition(in: canvasSize)

        var connections: [CanvasConnection] = []
        var previousPoint = startPoint

        for node in ordered {
            let currentPoint = nodePosition(node, in: canvasSize)
            connections.append(
                CanvasConnection(id: UUID(), from: previousPoint, to: currentPoint, toNodeId: node.id, isManual: false)
            )
            previousPoint = currentPoint
        }

        if let last = ordered.last {
            connections.append(
                CanvasConnection(id: UUID(), from: previousPoint, to: endPoint, toNodeId: last.id, isManual: false)
            )
        }

        return connections
    }

    private func defaultNodePosition(in size: CGSize) -> CGPoint {
        CGPoint(x: max(size.width * 0.5, 100), y: max(size.height * 0.5, 100))
    }

    private func startNodePosition(in size: CGSize) -> CGPoint {
        CGPoint(x: 80, y: size.height * 0.5)
    }

    private func endNodePosition(in size: CGSize) -> CGPoint {
        CGPoint(x: max(size.width - 80, 100), y: size.height * 0.5)
    }

    private func clamp(_ point: CGPoint, to size: CGSize) -> CGPoint {
        let padding: CGFloat = 80
        let x = min(max(point.x, padding), max(size.width - padding, padding))
        let y = min(max(point.y, padding), max(size.height - padding, padding))
        return CGPoint(x: x, y: y)
    }

    private func connectionPreviewStartPoint(in size: CGSize) -> CGPoint? {
        guard let fromID = activeConnectionFromID else { return nil }
        if fromID == startNodeID {
            return startNodePosition(in: size)
        }
        if let fromNode = effectChain.first(where: { $0.id == fromID }) {
            return nodePosition(fromNode, in: size)
        }
        return nil
    }

    private func finalizeConnection(from fromID: UUID, dropPoint: CGPoint) {
        print("🔗 Attempting to finalize connection from \(fromID == startNodeID ? "START" : "node")")
        print("   Drop point: \(dropPoint)")

        defer {
            activeConnectionFromID = nil
            activeConnectionPoint = .zero
        }

        guard let targetID = nearestConnectionTarget(from: fromID, at: dropPoint),
              targetID != fromID
        else {
            print("   ❌ No valid target found or same node")
            return
        }

        print("   ✅ Found target: \(targetID == endNodeID ? "END" : "effect node")")

        guard !createsCycle(from: fromID, to: targetID) else {
            print("   ❌ Would create cycle")
            return
        }

        print("   ✅ No cycle detected")
        manualConnections.removeAll { $0.fromNodeId == fromID || $0.toNodeId == targetID }
        manualConnections.append(BeginnerConnection(fromNodeId: fromID, toNodeId: targetID))
        print("   ✅ Connection created! Total connections: \(manualConnections.count)")
        applyChainToEngine()
    }

    private func nearestConnectionTarget(from fromID: UUID, at point: CGPoint) -> UUID? {
        var closest: (id: UUID, distance: CGFloat)?

        for node in effectChain {
            let nodePoint = nodePosition(node, in: canvasSize)
            let dx = nodePoint.x - point.x
            let dy = nodePoint.y - point.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance <= connectionSnapRadius {
                if closest == nil || distance < closest!.distance {
                    closest = (node.id, distance)
                }
            }
        }

        if fromID != endNodeID && fromID != startNodeID {
            let endPoint = endNodePosition(in: canvasSize)
            let dx = endPoint.x - point.x
            let dy = endPoint.y - point.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance <= connectionSnapRadius {
                if closest == nil || distance < closest!.distance {
                    closest = (endNodeID, distance)
                }
            }
        }
        return closest?.id
    }

    private func createsCycle(from: UUID, to: UUID) -> Bool {
        var nextMap = buildNextMap()
        nextMap[from] = to

        var visited = Set<UUID>()
        var current = to
        while let next = nextMap[current] {
            if next == from { return true }
            if visited.contains(next) { break }
            visited.insert(next)
            current = next
        }
        return false
    }

    private func buildNextMap() -> [UUID: UUID] {
        var nextMap: [UUID: UUID] = [:]

        switch wiringMode {
        case .automatic:
            // Build automatic position-based connections
            let ordered = orderedNodesByPosition()
            guard !ordered.isEmpty else { return nextMap }

            nextMap[startNodeID] = ordered[0].id
            for index in 0..<(ordered.count - 1) {
                nextMap[ordered[index].id] = ordered[index + 1].id
            }
            nextMap[ordered[ordered.count - 1].id] = endNodeID

            // Manual connections override automatic ones
            for connection in manualConnections {
                let fromIsValid = connection.fromNodeId == startNodeID ||
                    effectChain.contains(where: { $0.id == connection.fromNodeId })
                let toIsValid = connection.toNodeId == endNodeID ||
                    effectChain.contains(where: { $0.id == connection.toNodeId })
                guard fromIsValid, toIsValid else { continue }
                nextMap[connection.fromNodeId] = connection.toNodeId
            }

        case .manual:
            // Only use manual connections, no automatic fallback
            for connection in manualConnections {
                let fromIsValid = connection.fromNodeId == startNodeID ||
                    effectChain.contains(where: { $0.id == connection.fromNodeId })
                let toIsValid = connection.toNodeId == endNodeID ||
                    effectChain.contains(where: { $0.id == connection.toNodeId })
                guard fromIsValid, toIsValid else { continue }
                nextMap[connection.fromNodeId] = connection.toNodeId
            }
        }

        return nextMap
    }

    private func chainPath() -> [BeginnerNode] {
        let nextMap = buildNextMap()
        guard let first = nextMap[startNodeID] else { return [] }

        var ordered: [BeginnerNode] = []
        var visited = Set<UUID>([startNodeID])
        var current = first

        while current != endNodeID {
            if visited.contains(current) { break }
            visited.insert(current)
            guard let node = effectChain.first(where: { $0.id == current }) else { break }
            ordered.append(node)
            guard let next = nextMap[current] else { break }
            current = next
        }
        return ordered
    }

    private func manualPathFromStart() -> [BeginnerNode] {
        guard wiringMode == .manual else { return chainPath() }

        var nextMap: [UUID: UUID] = [:]
        for connection in manualConnections {
            let fromIsValid = connection.fromNodeId == startNodeID ||
                effectChain.contains(where: { $0.id == connection.fromNodeId })
            let toIsValid = connection.toNodeId == endNodeID ||
                effectChain.contains(where: { $0.id == connection.toNodeId })
            guard fromIsValid, toIsValid else { continue }
            nextMap[connection.fromNodeId] = connection.toNodeId
        }

        guard let first = nextMap[startNodeID] else { return [] }

        var ordered: [BeginnerNode] = []
        var visited = Set<UUID>([startNodeID])
        var current = first

        while current != endNodeID {
            if visited.contains(current) { break }
            visited.insert(current)
            guard let node = effectChain.first(where: { $0.id == current }) else { break }
            ordered.append(node)
            guard let next = nextMap[current] else { break }
            current = next
        }
        return ordered
    }

    private func orderedNodesByPosition() -> [BeginnerNode] {
        effectChain.sorted { lhs, rhs in
            let lhsPoint = nodePosition(lhs, in: canvasSize)
            let rhsPoint = nodePosition(rhs, in: canvasSize)
            if lhsPoint.x == rhsPoint.x {
                return lhsPoint.y < rhsPoint.y
            }
            return lhsPoint.x < rhsPoint.x
        }
    }

    private func nodePosition(_ node: BeginnerNode, in size: CGSize) -> CGPoint {
        node.position == .zero ? defaultNodePosition(in: size) : node.position
    }
}

// MARK: - Canvas Drop Delegate

struct CanvasDropDelegate: DropDelegate {
    @Binding var effectChain: [BeginnerNode]
    @Binding var draggedEffectType: EffectType?
    let canvasSize: CGSize
    let onAdd: (BeginnerNode) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let effectType = draggedEffectType else { return false }
        let location = clamp(info.location, to: canvasSize)
        onAdd(BeginnerNode(type: effectType, position: location))
        draggedEffectType = nil
        return true
    }

    private func clamp(_ point: CGPoint, to size: CGSize) -> CGPoint {
        let padding: CGFloat = 80
        let x = min(max(point.x, padding), max(size.width - padding, padding))
        let y = min(max(point.y, padding), max(size.height - padding, padding))
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Insertion Indicator

struct InsertionIndicator: View {
    @State private var pulse = false

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.3), .blue, .blue.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 4, height: 120)
            .cornerRadius(2)
            .shadow(color: .blue.opacity(0.5), radius: pulse ? 12 : 6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Effect Palette (Horizontal)

struct EffectPalette: View {
    let onEffectSelected: (EffectType) -> Void
    let onEffectDragged: (EffectType) -> Void

    private let effects: [EffectType] = [
        .bassBoost, .pitchShift, .clarity, .deMud,
        .simpleEQ, .tenBandEQ, .compressor, .reverb, .stereoWidth,
        .delay, .distortion, .tremolo
    ]

    var body: some View {
        VStack(spacing: 8) {
            Text("Available Effects (Drag or Click to Add)")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(effects, id: \.self) { effectType in
                        EffectPaletteButton(
                            effectType: effectType,
                            onTap: {
                                onEffectSelected(effectType)
                            },
                            onDragStart: {
                                onEffectDragged(effectType)
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

struct EffectPaletteButton: View {
    let effectType: EffectType
    let onTap: () -> Void
    let onDragStart: () -> Void
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: effectType.icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(
                        colors: isHovered ? [.blue.opacity(0.8), .blue] : [.blue.opacity(0.6), .blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: isHovered ? 8 : 4, y: isHovered ? 4 : 2)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .opacity(isDragging ? 0.5 : 1.0)

            Text(effectType.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onTap()
        }
        .onDrag {
            isDragging = true
            onDragStart()
            return NSItemProvider(object: effectType.rawValue as NSString)
        }
    }
}

// MARK: - Start/End Nodes

struct StartNodeView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.green.opacity(0.8), .green],
                        center: .center,
                        startRadius: 10,
                        endRadius: 40
                    )
                )
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                )
                .shadow(color: .green.opacity(0.6), radius: pulse ? 20 : 10)
                .scaleEffect(pulse ? 1.05 : 1.0)

            Text("Start")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .frame(width: 80)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct EndNodeView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.purple.opacity(0.8), .purple],
                        center: .center,
                        startRadius: 10,
                        endRadius: 40
                    )
                )
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                )
                .shadow(color: .purple.opacity(0.6), radius: pulse ? 20 : 10)
                .scaleEffect(pulse ? 1.05 : 1.0)

            Text("End")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .frame(width: 80)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Flow Connection

struct FlowConnection: View {
    let isActive: Bool
    let level: Float
    @State private var animationProgress: CGFloat = 0

    var body: some View {
        let intensity = min(max(Double(level) * 3.0, 0.0), 1.0)
        let glow = Color.blue.opacity(0.2 + 0.8 * intensity)
        let baseOpacity = 0.2 + 0.6 * intensity
        let thickness: CGFloat = 2 + CGFloat(intensity) * 3

        ZStack {
            // Base line
            Rectangle()
                .fill(Color.secondary.opacity(baseOpacity))
                .frame(width: 100, height: thickness)

            // Animated flow
            if isActive {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, glow, glow, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 30, height: thickness + 1)
                    .offset(x: animationProgress * 70 - 35)
                    .shadow(color: glow.opacity(0.6), radius: 6, y: 0)
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            animationProgress = 1.0
                        }
                    }
            }
        }
    }
}

// MARK: - Flow Line

struct FlowLine: View {
    let from: CGPoint
    let to: CGPoint
    let isActive: Bool
    let level: Float
    @State private var phase: CGFloat = 0

    var body: some View {
        let intensity = min(max(CGFloat(level) * 3.0, 0.0), 1.0)
        let baseOpacity = 0.15 + 0.6 * intensity
        let glowColor = Color.blue.opacity(0.2 + 0.7 * intensity)
        let thickness: CGFloat = 2 + 3 * intensity

        ZStack {
            Path { path in
                path.move(to: from)
                path.addLine(to: to)
            }
            .stroke(Color.secondary.opacity(baseOpacity), lineWidth: thickness)
            .contentShape(Path { path in
                path.move(to: from)
                path.addLine(to: to)
            }.strokedPath(.init(lineWidth: thickness + 10)))

            if isActive {
                Circle()
                    .fill(glowColor)
                    .frame(width: 6 + 6 * intensity, height: 6 + 6 * intensity)
                    .position(pointAlongLine(from: from, to: to, t: phase))
                    .shadow(color: glowColor.opacity(0.6), radius: 6)
            }
        }
        .onAppear {
            if isActive {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
        .onChange(of: isActive) { active in
            if active {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            } else {
                phase = 0
            }
        }
    }

    private func pointAlongLine(from: CGPoint, to: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(
            x: from.x + (to.x - from.x) * t,
            y: from.y + (to.y - from.y) * t
        )
    }
}

private struct CanvasConnection: Identifiable {
    let id: UUID
    let from: CGPoint
    let to: CGPoint
    let toNodeId: UUID
    let isManual: Bool
}


// MARK: - Effect Block

struct EffectBlockHorizontal: View {
    let effect: BeginnerNode
    @ObservedObject var audioEngine: AudioEngine
    let isWired: Bool
    let isSelected: Bool
    let onRemove: () -> Void
    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                // Icon and name
                VStack(spacing: 6) {
                    Image(systemName: effect.type.icon)
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(
                            LinearGradient(
                                colors: getEffectEnabled() ? [.blue, .blue.opacity(0.7)] : [.gray, .gray.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(getEffectEnabled() ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                    Text(effect.type.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 80)
                }

                // Control buttons
                HStack(spacing: 8) {
                    // Toggle
                    Button(action: {
                        setEffectEnabled(!getEffectEnabled())
                    }) {
                        Image(systemName: getEffectEnabled() ? "power.circle.fill" : "power.circle")
                            .font(.system(size: 18))
                            .foregroundColor(getEffectEnabled() ? .green : .secondary)
                    }
                    .buttonStyle(.plain)

                    // Expand/collapse
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "slider.horizontal.3")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)

                    // Remove
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(width: 120)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .opacity(isWired ? 1.0 : 0.45)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue.opacity(0.8) : Color.clear, lineWidth: 2)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }

            // Expanded parameters
            if isExpanded && getEffectEnabled() {
                VStack(spacing: 12) {
                    EffectParametersViewCompact(effectType: effect.type, audioEngine: audioEngine)
                }
                .padding()
                .frame(width: 200)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.9))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                )
                .padding(.top, 8)
                .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
            }
        }
    }

    private func getEffectEnabled() -> Bool {
        switch effect.type {
        case .bassBoost: return audioEngine.bassBoostEnabled
        case .pitchShift: return audioEngine.nightcoreEnabled
        case .clarity: return audioEngine.clarityEnabled
        case .reverb: return audioEngine.reverbEnabled
        case .compressor: return audioEngine.compressorEnabled
        case .stereoWidth: return audioEngine.stereoWidthEnabled
        case .simpleEQ: return audioEngine.simpleEQEnabled
        case .tenBandEQ: return audioEngine.tenBandEQEnabled
        case .deMud: return audioEngine.deMudEnabled
        case .delay: return audioEngine.delayEnabled
        case .distortion: return audioEngine.distortionEnabled
        case .tremolo: return audioEngine.tremoloEnabled
        }
    }

    private func setEffectEnabled(_ enabled: Bool) {
        switch effect.type {
        case .bassBoost: audioEngine.bassBoostEnabled = enabled
        case .pitchShift: audioEngine.nightcoreEnabled = enabled
        case .clarity: audioEngine.clarityEnabled = enabled
        case .reverb: audioEngine.reverbEnabled = enabled
        case .compressor: audioEngine.compressorEnabled = enabled
        case .stereoWidth: audioEngine.stereoWidthEnabled = enabled
        case .simpleEQ: audioEngine.simpleEQEnabled = enabled
        case .tenBandEQ: audioEngine.tenBandEQEnabled = enabled
        case .deMud: audioEngine.deMudEnabled = enabled
        case .delay: audioEngine.delayEnabled = enabled
        case .distortion: audioEngine.distortionEnabled = enabled
        case .tremolo: audioEngine.tremoloEnabled = enabled
        }
    }
}

// MARK: - Compact Parameters View

struct EffectParametersViewCompact: View {
    let effectType: EffectType
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        VStack(spacing: 10) {
            switch effectType {
            case .bassBoost:
                CompactSlider(label: "Amount", value: $audioEngine.bassBoostAmount, range: 0...1, format: .percent)

            case .pitchShift:
                CompactSlider(label: "Intensity", value: $audioEngine.nightcoreIntensity, range: 0...1, format: .percent)

            case .clarity:
                CompactSlider(label: "Amount", value: $audioEngine.clarityAmount, range: 0...1, format: .percent)

            case .deMud:
                CompactSlider(label: "Strength", value: $audioEngine.deMudStrength, range: 0...1, format: .percent)

            case .simpleEQ:
                CompactSlider(label: "Bass", value: $audioEngine.eqBass, range: -1...1, format: .db)
                CompactSlider(label: "Mids", value: $audioEngine.eqMids, range: -1...1, format: .db)
                CompactSlider(label: "Treble", value: $audioEngine.eqTreble, range: -1...1, format: .db)

            case .tenBandEQ:
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 8) {
                    CompactSlider(label: "31", value: $audioEngine.tenBand31, range: -12...12, format: .dbValue)
                    CompactSlider(label: "62", value: $audioEngine.tenBand62, range: -12...12, format: .dbValue)
                    CompactSlider(label: "125", value: $audioEngine.tenBand125, range: -12...12, format: .dbValue)
                    CompactSlider(label: "250", value: $audioEngine.tenBand250, range: -12...12, format: .dbValue)
                    CompactSlider(label: "500", value: $audioEngine.tenBand500, range: -12...12, format: .dbValue)
                    CompactSlider(label: "1k", value: $audioEngine.tenBand1k, range: -12...12, format: .dbValue)
                    CompactSlider(label: "2k", value: $audioEngine.tenBand2k, range: -12...12, format: .dbValue)
                    CompactSlider(label: "4k", value: $audioEngine.tenBand4k, range: -12...12, format: .dbValue)
                    CompactSlider(label: "8k", value: $audioEngine.tenBand8k, range: -12...12, format: .dbValue)
                    CompactSlider(label: "16k", value: $audioEngine.tenBand16k, range: -12...12, format: .dbValue)
                }

            case .compressor:
                CompactSlider(label: "Strength", value: $audioEngine.compressorStrength, range: 0...1, format: .percent)

            case .reverb:
                CompactSlider(label: "Mix", value: $audioEngine.reverbMix, range: 0...1, format: .percent)
                CompactSlider(label: "Size", value: $audioEngine.reverbSize, range: 0...1, format: .percent)

            case .stereoWidth:
                CompactSlider(label: "Width", value: $audioEngine.stereoWidthAmount, range: 0...1, format: .percent)

            case .delay:
                CompactSlider(label: "Time", value: $audioEngine.delayTime, range: 0.01...2.0, format: .ms)
                CompactSlider(label: "Feedback", value: $audioEngine.delayFeedback, range: 0...1, format: .percent)
                CompactSlider(label: "Mix", value: $audioEngine.delayMix, range: 0...1, format: .percent)

            case .distortion:
                CompactSlider(label: "Drive", value: $audioEngine.distortionDrive, range: 0...1, format: .percent)
                CompactSlider(label: "Mix", value: $audioEngine.distortionMix, range: 0...1, format: .percent)

            case .tremolo:
                CompactSlider(label: "Rate", value: $audioEngine.tremoloRate, range: 0.1...20, format: .hz)
                CompactSlider(label: "Depth", value: $audioEngine.tremoloDepth, range: 0...1, format: .percent)
            }
        }
    }
}

struct CompactSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: ValueFormat

    enum ValueFormat {
        case percent
        case db
        case dbValue
        case ms
        case hz
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formattedValue)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }

    private var formattedValue: String {
        switch format {
        case .percent:
            return "\(Int(value * 100))%"
        case .db:
            let db = value * 12.0
            return String(format: "%+.1f dB", db)
        case .dbValue:
            return String(format: "%+.1f dB", value)
        case .ms:
            return String(format: "%.0f ms", value * 1000)
        case .hz:
            return String(format: "%.1f Hz", value)
        }
    }
}

// MARK: - Supporting Types

#Preview {
    BeginnerView(audioEngine: AudioEngine())
}
