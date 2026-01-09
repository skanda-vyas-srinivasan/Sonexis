import SwiftUI

// MARK: - Beginner View

struct BeginnerView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var selectedWireID: UUID?

    @State private var startNodeID = UUID()
    @State private var endNodeID = UUID()
    @State private var leftStartNodeID = UUID()
    @State private var leftEndNodeID = UUID()
    @State private var rightStartNodeID = UUID()
    @State private var rightEndNodeID = UUID()
    @State private var graphMode: GraphMode = .single
    @State private var nextAccentIndex = 0
    @State private var isAppActive = true
    @State private var isTrayCollapsed = false
    private let connectionSnapRadius: CGFloat = 120
    private let accentPalette: [AccentStyle] = [
        AccentStyle(
            fill: Color(red: 0.93, green: 0.88, blue: 0.78),
            fillDark: Color(red: 0.86, green: 0.80, blue: 0.67),
            text: Color(red: 0.24, green: 0.20, blue: 0.15)
        ),
        AccentStyle(
            fill: Color(red: 0.82, green: 0.64, blue: 0.42),
            fillDark: Color(red: 0.73, green: 0.55, blue: 0.35),
            text: Color(red: 0.22, green: 0.18, blue: 0.13)
        )
    ]

    enum WiringMode {
        case automatic  // Position-based with manual override
        case manual     // Pure manual wiring only
    }

    var body: some View {
        let leftAutoPath = graphMode == .split ? chainPath(for: .left) : chainPath(for: nil)
        let rightAutoPath = graphMode == .split ? chainPath(for: .right) : []
        let pathIDs = wiringMode == .automatic
            ? Set((leftAutoPath + rightAutoPath).map { $0.id })
            : reachableNodeIDsFromStart()
        let isAnimating = audioEngine.isRunning && showSignalFlow && isAppActive

        HStack(spacing: 0) {
            EffectTray(
                isCollapsed: $isTrayCollapsed,
                onSelect: { type in
                    addEffectToChain(type)
                },
                onDrag: { type in
                    draggedEffectType = type
                }
            )

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("Graph Mode", selection: $graphMode) {
                        Text("Stereo").tag(GraphMode.single)
                        Text("Split L/R").tag(GraphMode.split)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .tint(AppColors.neonCyan)
                    .onChange(of: graphMode) { _ in
                        if graphMode == .split {
                            syncLanesForSplit()
                        }
                        applyChainToEngine()
                    }

                    Picker("Wiring Mode", selection: $wiringMode) {
                        Text("Automatic").tag(WiringMode.automatic)
                        Text("Manual").tag(WiringMode.manual)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .tint(AppColors.neonCyan)
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
                    .foregroundColor(AppColors.textSecondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppColors.midPurple.opacity(0.9))

                Divider()
                    .background(AppColors.gridLines)

                // Free-placement canvas
                GeometryReader { geometry in
                    ZStack {
                    AppGradients.background
                        .ignoresSafeArea()

                    AnimatedGrid(intensity: showSignalFlow ? 0.6 : 0.3)

                    ScanlinesOverlay()

                    Rectangle()
                        .fill(Color.clear)
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

                    // Draw connections based on mode
                    if wiringMode == .automatic {
                        let autoConnections = graphMode == .split
                            ? (connectionsForCanvas(path: leftAutoPath, lane: .left) +
                               connectionsForCanvas(path: rightAutoPath, lane: .right))
                            : connectionsForCanvas(path: leftAutoPath, lane: nil)
                        ForEach(autoConnections, id: \.id) { connection in
                            FlowLine(
                                from: connection.from,
                                to: connection.to,
                                isActive: isAnimating,
                                level: levelForNode(connection.toNodeId)
                            )
                        }
                    } else {
                        let manualConnections = graphMode == .split
                            ? (visualManualConnections(in: geometry.size, lane: .left) +
                               visualManualConnections(in: geometry.size, lane: .right))
                            : visualManualConnections(in: geometry.size, lane: nil)
                        ForEach(manualConnections, id: \.id) { connection in
                            FlowLine(
                                from: connection.from,
                                to: connection.to,
                                isActive: isAnimating,
                                level: levelForNode(connection.toNodeId)
                            )
                            .contextMenu {
                                if connection.isManual {
                                    Button("Delete Wire") {
                                        deleteManualConnection(connection.id)
                                    }
                                    Button("Set Gain…") {
                                        selectedWireID = connection.id
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

                    if let wireID = selectedWireID,
                       let binding = gainBinding(for: wireID),
                       let wire = manualConnection(for: wireID) {
                        let midpoint = CGPoint(
                            x: (wire.from.x + wire.to.x) * 0.5,
                            y: (wire.from.y + wire.to.y) * 0.5 - 28
                        )

                        VStack(spacing: 6) {
                            Text("Gain")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.9))
                            Slider(value: binding, in: 0...1)
                                .controlSize(.mini)
                                .frame(width: 140)
                            Text(String(format: "%.0f%%", binding.wrappedValue * 100))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.7))
                            Button("Done") {
                                selectedWireID = nil
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.75))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: Color.black.opacity(0.5), radius: 6, y: 2)
                        .position(midpoint)
                        .zIndex(5)
                    }

                    if let start = lassoStart, let current = lassoCurrent {
                        let rect = selectionRect(from: start, to: current)
                        Rectangle()
                            .path(in: rect)
                            .stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .background(Color.blue.opacity(0.08))
                    }

                    if graphMode == .split {
                        Rectangle()
                            .fill(Color.gray.opacity(0.18))
                            .frame(width: 1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                        StartNodeView()
                            .position(startNodePosition(in: geometry.size, lane: .left))
                            .contextMenu {
                                if wiringMode == .manual {
                                    Button("Delete Node Wires") {
                                        removeWires(for: leftStartNodeID)
                                    }
                                }
                            }
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if NSEvent.modifierFlags.contains(.option) {
                                            let start = startNodePosition(in: geometry.size, lane: .left)
                                            activeConnectionFromID = leftStartNodeID
                                            activeConnectionPoint = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { value in
                                        if NSEvent.modifierFlags.contains(.option) {
                                            let start = startNodePosition(in: geometry.size, lane: .left)
                                            let dropPoint = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                            finalizeConnection(from: leftStartNodeID, dropPoint: dropPoint)
                                        } else {
                                            activeConnectionFromID = nil
                                            activeConnectionPoint = .zero
                                        }
                                    }
                            )

                        EndNodeView()
                            .position(endNodePosition(in: geometry.size, lane: .left))
                            .contextMenu {
                                if wiringMode == .manual {
                                    Button("Delete Node Wires") {
                                        removeWires(for: leftEndNodeID)
                                    }
                                }
                            }

                        StartNodeView()
                            .position(startNodePosition(in: geometry.size, lane: .right))
                            .contextMenu {
                                if wiringMode == .manual {
                                    Button("Delete Node Wires") {
                                        removeWires(for: rightStartNodeID)
                                    }
                                }
                            }
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if NSEvent.modifierFlags.contains(.option) {
                                            let start = startNodePosition(in: geometry.size, lane: .right)
                                            activeConnectionFromID = rightStartNodeID
                                            activeConnectionPoint = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { value in
                                        if NSEvent.modifierFlags.contains(.option) {
                                            let start = startNodePosition(in: geometry.size, lane: .right)
                                            let dropPoint = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                            finalizeConnection(from: rightStartNodeID, dropPoint: dropPoint)
                                        } else {
                                            activeConnectionFromID = nil
                                            activeConnectionPoint = .zero
                                        }
                                    }
                            )

                        EndNodeView()
                            .position(endNodePosition(in: geometry.size, lane: .right))
                            .contextMenu {
                                if wiringMode == .manual {
                                    Button("Delete Node Wires") {
                                        removeWires(for: rightEndNodeID)
                                    }
                                }
                            }
                    } else {
                        StartNodeView()
                            .position(startNodePosition(in: geometry.size, lane: nil))
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
                                            let start = startNodePosition(in: geometry.size, lane: nil)
                                            activeConnectionFromID = startNodeID
                                            activeConnectionPoint = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { value in
                                        if NSEvent.modifierFlags.contains(.option) {
                                            let start = startNodePosition(in: geometry.size, lane: nil)
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
                            .position(endNodePosition(in: geometry.size, lane: nil))
                            .contextMenu {
                                if wiringMode == .manual {
                                    Button("Delete Node Wires") {
                                        removeWires(for: endNodeID)
                                    }
                                }
                            }
                    }

                    ForEach(effectChain, id: \.id) { effect in
                        let effectValue = effect
                        let nodePos = nodePosition(effectValue, in: geometry.size)
                        let isWired = pathIDs.contains(effectValue.id)
                        let isSelected = selectedNodeIDs.contains(effectValue.id)

                        EffectBlockHorizontal(
                            effect: bindingForEffect(effectValue.id),
                            isWired: isWired,
                            isSelected: isSelected,
                            tileStyle: accentPalette[effectValue.accentIndex % accentPalette.count],
                            onRemove: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    removeEffect(id: effectValue.id)
                                }
                            },
                            onUpdate: {
                                applyChainToEngine()
                            }
                        )
                        .position(nodePos)
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {
                                    guard wiringMode == .manual else { return }
                                    let isShift = NSEvent.modifierFlags.contains(.shift)
                                    if isShift {
                                        toggleSelection(effectValue.id)
                                    } else {
                                        selectedNodeIDs = [effectValue.id]
                                    }
                                }
                        )
                        .contextMenu {
                            Button("Delete Node") {
                                removeEffect(id: effectValue.id)
                            }
                            if wiringMode == .manual {
                                Button("Delete Node Wires") {
                                    removeWires(for: effectValue.id)
                                }
                            }
                            Button("Duplicate Node") {
                                duplicateEffect(id: effectValue.id)
                            }
                            Button("Reset Node Params") {
                                resetEffectParameters(id: effectValue.id)
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let hasOption = NSEvent.modifierFlags.contains(.option)
                                    if hasOption {
                                        // Wiring mode
                                        print("🖱️ EFFECT drag with Option held")
                                        activeConnectionFromID = effectValue.id
                                        activeConnectionPoint = CGPoint(
                                            x: nodePos.x + value.translation.width,
                                            y: nodePos.y + value.translation.height
                                        )
                                    } else {
                                        // Move mode
                                        if draggingNodeID != effectValue.id {
                                            draggingNodeID = effectValue.id
                                            dragStartPosition = nodePos
                                            if wiringMode == .manual {
                                                if !selectedNodeIDs.contains(effectValue.id) && !NSEvent.modifierFlags.contains(.shift) {
                                                    selectedNodeIDs = [effectValue.id]
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
                                            updateNodePosition(
                                                effectValue.id,
                                                position: clamp(
                                                    newPosition,
                                                    to: geometry.size,
                                                    lane: graphMode == .split ? effectValue.lane : nil
                                                )
                                            )
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
                                        finalizeConnection(from: effectValue.id, dropPoint: dropPoint)
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

                    if effectChain.isEmpty && graphMode != .split {
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
                    graphMode: graphMode,
                    laneProvider: { point in
                        laneForPoint(point, in: geometry.size)
                    },
                    onAdd: { newNode in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            var node = newNode
                            node.accentIndex = nextAccentIndex
                            nextAccentIndex = (nextAccentIndex + 1) % accentPalette.count
                            effectChain.append(node)
                            applyChainToEngine()
                        }
                    }
                ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            showSignalFlow = audioEngine.isRunning
        }
        .onChange(of: audioEngine.isRunning) { isRunning in
            showSignalFlow = isRunning
        }
        .onReceive(audioEngine.$pendingGraphSnapshot) { snapshot in
            guard let snapshot else { return }
            applyGraphSnapshot(snapshot)
            audioEngine.pendingGraphSnapshot = nil
        }
        .onChange(of: scenePhase) { phase in
            isAppActive = phase == .active
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
            let lane: GraphLane? = graphMode == .split ? .left : nil
            let position = defaultNodePosition(in: canvasSize, lane: lane)
            let newEffect = BeginnerNode(
                type: type,
                position: position,
                lane: lane ?? .left,
                accentIndex: nextAccentIndex
            )
            nextAccentIndex = (nextAccentIndex + 1) % accentPalette.count
            effectChain.append(newEffect)
            applyChainToEngine()
        }
    }

    private func removeEffect(id: UUID) {
        effectChain.removeAll { $0.id == id }
        manualConnections.removeAll { $0.fromNodeId == id || $0.toNodeId == id }
        selectedNodeIDs.remove(id)
        normalizeAllOutgoingGains()
        applyChainToEngine()
    }

    private func duplicateEffect(id: UUID) {
        guard let index = effectChain.firstIndex(where: { $0.id == id }) else { return }
        let source = effectChain[index]
        var clone = BeginnerNode(
            type: source.type,
            position: CGPoint(x: source.position.x + 40, y: source.position.y + 40),
            lane: source.lane,
            isEnabled: source.isEnabled,
            parameters: source.parameters,
            accentIndex: source.accentIndex
        )
        clone.position = clamp(clone.position, to: canvasSize, lane: graphMode == .split ? clone.lane : nil)
        effectChain.append(clone)
        applyChainToEngine()
    }

    private func resetEffectParameters(id: UUID) {
        guard let index = effectChain.firstIndex(where: { $0.id == id }) else { return }
        effectChain[index].parameters = NodeEffectParameters.defaults()
        applyChainToEngine()
    }

    private func removeEffects(ids: Set<UUID>) {
        effectChain.removeAll { ids.contains($0.id) }
        manualConnections.removeAll { ids.contains($0.fromNodeId) || ids.contains($0.toNodeId) }
        selectedNodeIDs.subtract(ids)
        normalizeAllOutgoingGains()
        applyChainToEngine()
    }

    private func deleteWiresForSelected() {
        manualConnections.removeAll { selectedNodeIDs.contains($0.fromNodeId) || selectedNodeIDs.contains($0.toNodeId) }
        normalizeAllOutgoingGains()
        applyChainToEngine()
    }

    private func applyChainToEngine() {
        if graphMode == .split {
            let leftNodes = effectChain.filter { $0.lane == .left }
            let rightNodes = effectChain.filter { $0.lane == .right }
            let leftConnections = wiringMode == .automatic
                ? autoConnections(for: .left)
                : manualConnections.filter { laneForConnection($0) == .left }
            let rightConnections = wiringMode == .automatic
                ? autoConnections(for: .right)
                : manualConnections.filter { laneForConnection($0) == .right }

            audioEngine.updateEffectGraphSplit(
                leftNodes: leftNodes,
                leftConnections: leftConnections,
                leftStartID: leftStartNodeID,
                leftEndID: leftEndNodeID,
                rightNodes: rightNodes,
                rightConnections: rightConnections,
                rightStartID: rightStartNodeID,
                rightEndID: rightEndNodeID
            )
            updateDebugGraphText()
        } else {
            let path = chainPath(for: nil)
            print("📊 Chain path (\(path.count) effects) - Mode: \(wiringMode == .automatic ? "AUTOMATIC" : "MANUAL")")
            if wiringMode == .automatic {
                for (index, node) in path.enumerated() {
                    print("   \(index + 1). \(node.type.rawValue)")
                }
            } else {
                let edges = manualGraphEdges(lane: nil)
                print("   Manual edges (\(edges.count))")
                for edge in edges {
                    print("   🔗 \(edge)")
                }
            }
            if wiringMode == .manual {
                audioEngine.updateEffectGraph(
                    nodes: effectChain,
                    connections: manualConnections,
                    startID: startNodeID,
                    endID: endNodeID
                )
                updateDebugGraphText()
            } else {
                audioEngine.updateEffectChain(path)
                updateDebugChainText(path)
            }
        }
        audioEngine.updateGraphSnapshot(currentGraphSnapshot())
    }

    private func bindingForEffect(_ id: UUID) -> Binding<BeginnerNode> {
        Binding(
            get: {
                effectChain.first(where: { $0.id == id }) ?? BeginnerNode(type: .bassBoost)
            },
            set: { updated in
                guard let index = effectChain.firstIndex(where: { $0.id == id }) else { return }
                effectChain[index] = updated
            }
        )
    }

    private func applyGraphSnapshot(_ snapshot: GraphSnapshot) {
        let nodes = snapshot.hasNodeParameters ? snapshot.nodes : migrateNodeParameters(snapshot.nodes)
        let removedIds = Set(nodes.filter { $0.type == .pitchShift }.map { $0.id })
        let filteredNodes = nodes.filter { $0.type != .pitchShift }
        effectChain = filteredNodes
        manualConnections = snapshot.connections.filter { !removedIds.contains($0.fromNodeId) && !removedIds.contains($0.toNodeId) }
        startNodeID = snapshot.startNodeID
        endNodeID = snapshot.endNodeID
        leftStartNodeID = snapshot.leftStartNodeID ?? leftStartNodeID
        leftEndNodeID = snapshot.leftEndNodeID ?? leftEndNodeID
        rightStartNodeID = snapshot.rightStartNodeID ?? rightStartNodeID
        rightEndNodeID = snapshot.rightEndNodeID ?? rightEndNodeID
        graphMode = snapshot.graphMode
        wiringMode = snapshot.wiringMode == .manual ? .manual : .automatic
        if graphMode == .split {
            manualConnections.removeAll { laneForConnection($0) == nil }
        }
        let maxAccent = effectChain.map(\.accentIndex).max() ?? -1
        nextAccentIndex = (maxAccent + 1) % accentPalette.count
        selectedNodeIDs.removeAll()
        selectedWireID = nil
        applyChainToEngine()
    }

    private func migrateNodeParameters(_ nodes: [BeginnerNode]) -> [BeginnerNode] {
        nodes.map { node in
            var updated = node
            var params = NodeEffectParameters.defaults()
            switch node.type {
            case .bassBoost:
                params.bassBoostAmount = audioEngine.bassBoostAmount
            case .pitchShift:
                params.nightcoreIntensity = audioEngine.nightcoreIntensity
            case .rubberBandPitch:
                params.rubberBandPitchSemitones = audioEngine.rubberBandPitchSemitones
            case .clarity:
                params.clarityAmount = audioEngine.clarityAmount
            case .deMud:
                params.deMudStrength = audioEngine.deMudStrength
            case .simpleEQ:
                params.eqBass = audioEngine.eqBass
                params.eqMids = audioEngine.eqMids
                params.eqTreble = audioEngine.eqTreble
            case .tenBandEQ:
                params.tenBandGains = [
                    audioEngine.tenBand31,
                    audioEngine.tenBand62,
                    audioEngine.tenBand125,
                    audioEngine.tenBand250,
                    audioEngine.tenBand500,
                    audioEngine.tenBand1k,
                    audioEngine.tenBand2k,
                    audioEngine.tenBand4k,
                    audioEngine.tenBand8k,
                    audioEngine.tenBand16k
                ]
            case .compressor:
                params.compressorStrength = audioEngine.compressorStrength
            case .reverb:
                params.reverbMix = audioEngine.reverbMix
                params.reverbSize = audioEngine.reverbSize
            case .stereoWidth:
                params.stereoWidthAmount = audioEngine.stereoWidthAmount
            case .delay:
                params.delayTime = audioEngine.delayTime
                params.delayFeedback = audioEngine.delayFeedback
                params.delayMix = audioEngine.delayMix
            case .distortion:
                params.distortionDrive = audioEngine.distortionDrive
                params.distortionMix = audioEngine.distortionMix
            case .tremolo:
                params.tremoloRate = audioEngine.tremoloRate
                params.tremoloDepth = audioEngine.tremoloDepth
            case .chorus:
                params.chorusRate = audioEngine.chorusRate
                params.chorusDepth = audioEngine.chorusDepth
                params.chorusMix = audioEngine.chorusMix
            case .phaser:
                params.phaserRate = audioEngine.phaserRate
                params.phaserDepth = audioEngine.phaserDepth
            case .flanger:
                params.flangerRate = audioEngine.flangerRate
                params.flangerDepth = audioEngine.flangerDepth
                params.flangerFeedback = audioEngine.flangerFeedback
                params.flangerMix = audioEngine.flangerMix
            case .bitcrusher:
                params.bitcrusherBitDepth = audioEngine.bitcrusherBitDepth
                params.bitcrusherDownsample = audioEngine.bitcrusherDownsample
                params.bitcrusherMix = audioEngine.bitcrusherMix
            case .tapeSaturation:
                params.tapeSaturationDrive = audioEngine.tapeSaturationDrive
                params.tapeSaturationMix = audioEngine.tapeSaturationMix
            case .resampling:
                params.resampleRate = audioEngine.resampleRate
                params.resampleCrossfade = audioEngine.resampleCrossfade
            }
            updated.parameters = params
            return updated
        }
    }

    private func currentGraphSnapshot() -> GraphSnapshot {
        GraphSnapshot(
            graphMode: graphMode,
            wiringMode: wiringMode == .manual ? .manual : .automatic,
            nodes: effectChain,
            connections: manualConnections,
            startNodeID: startNodeID,
            endNodeID: endNodeID,
            leftStartNodeID: leftStartNodeID,
            leftEndNodeID: leftEndNodeID,
            rightStartNodeID: rightStartNodeID,
            rightEndNodeID: rightEndNodeID,
            hasNodeParameters: true
        )
    }

    private func updateDebugChainText(_ path: [BeginnerNode]) {
        if path.isEmpty {
            debugChainText = "DSP chain: (empty)"
            return
        }
        let names = path.map { $0.type.rawValue }.joined(separator: " → ")
        debugChainText = "DSP chain: \(names)"
    }

    private func updateDebugGraphText() {
        if graphMode == .split {
            let leftEdges = wiringMode == .automatic
                ? edgeStrings(from: autoConnections(for: .left), lane: .left)
                : manualGraphEdges(lane: .left)
            let rightEdges = wiringMode == .automatic
                ? edgeStrings(from: autoConnections(for: .right), lane: .right)
                : manualGraphEdges(lane: .right)
            if leftEdges.isEmpty && rightEdges.isEmpty {
                debugChainText = "DSP graph: (empty)"
                return
            }
            let leftText = leftEdges.isEmpty ? "Left: (empty)" : "Left: \(leftEdges.joined(separator: " | "))"
            let rightText = rightEdges.isEmpty ? "Right: (empty)" : "Right: \(rightEdges.joined(separator: " | "))"
            debugChainText = "DSP graph: \(leftText)  •  \(rightText)"
        } else {
            let edges = wiringMode == .automatic
                ? edgeStrings(from: autoConnections(for: .left), lane: nil)
                : manualGraphEdges(lane: nil)
            if edges.isEmpty {
                debugChainText = "DSP graph: (empty)"
                return
            }
            debugChainText = "DSP graph: \(edges.joined(separator: " | "))"
        }
    }

    private func manualGraphEdges(lane: GraphLane?) -> [String] {
        var edges: [String] = []

        func name(for id: UUID) -> String {
            if graphMode == .split {
                if id == leftStartNodeID { return "Start L" }
                if id == leftEndNodeID { return "End L" }
                if id == rightStartNodeID { return "Start R" }
                if id == rightEndNodeID { return "End R" }
            } else {
                if id == startNodeID { return "Start" }
                if id == endNodeID { return "End" }
            }
            return effectChain.first(where: { $0.id == id })?.type.rawValue ?? "?"
        }

        for connection in manualConnections {
            if graphMode == .split, laneForConnection(connection) != lane { continue }
            edges.append("\(name(for: connection.fromNodeId))→\(name(for: connection.toNodeId))")
        }

        for nodeID in implicitEndNodes(lane: lane) {
            let endLabel = graphMode == .split ? (lane == .right ? "End R" : "End L") : "End"
            edges.append("\(name(for: nodeID))→\(endLabel)")
        }

        return edges
    }

    private func edgeStrings(from connections: [BeginnerConnection], lane: GraphLane?) -> [String] {
        func name(for id: UUID) -> String {
            if graphMode == .split {
                if id == leftStartNodeID { return "Start L" }
                if id == leftEndNodeID { return "End L" }
                if id == rightStartNodeID { return "Start R" }
                if id == rightEndNodeID { return "End R" }
            } else {
                if id == startNodeID { return "Start" }
                if id == endNodeID { return "End" }
            }
            return effectChain.first(where: { $0.id == id })?.type.rawValue ?? "?"
        }

        return connections.map { connection in
            "\(name(for: connection.fromNodeId))→\(name(for: connection.toNodeId))"
        }
    }

    private func autoConnections(for lane: GraphLane) -> [BeginnerConnection] {
        let ordered = chainPath(for: lane)
        let startID = startNodeID(for: lane)
        let endID = endNodeID(for: lane)
        guard !ordered.isEmpty else {
            return [BeginnerConnection(fromNodeId: startID, toNodeId: endID)]
        }

        var connections: [BeginnerConnection] = []
        connections.append(BeginnerConnection(fromNodeId: startID, toNodeId: ordered[0].id))
        for index in 0..<(ordered.count - 1) {
            connections.append(BeginnerConnection(fromNodeId: ordered[index].id, toNodeId: ordered[index + 1].id))
        }
        connections.append(BeginnerConnection(fromNodeId: ordered[ordered.count - 1].id, toNodeId: endID))
        return connections
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
            let lane = effectChain.first(where: { $0.id == id })?.lane
            updateNodePosition(id, position: clamp(newPosition, to: size, lane: graphMode == .split ? lane : nil))
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
        normalizeOutgoingGains(from: nodeID)
        applyChainToEngine()
    }

    private func deleteManualConnection(_ id: UUID) {
        if let connection = manualConnections.first(where: { $0.id == id }) {
            manualConnections.removeAll { $0.id == id }
            normalizeOutgoingGains(from: connection.fromNodeId)
        }
        applyChainToEngine()
    }

    private func normalizeAllOutgoingGains() {
        guard wiringMode == .manual else { return }
        let sources = Set(manualConnections.map { $0.fromNodeId })
        for source in sources {
            normalizeOutgoingGains(from: source)
        }
    }

    private func normalizeOutgoingGains(from fromID: UUID) {
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

    private func gainBinding(for wireID: UUID) -> Binding<Double>? {
        guard let index = manualConnections.firstIndex(where: { $0.id == wireID }) else {
            return nil
        }
        return Binding(
            get: { manualConnections[index].gain },
            set: { newValue in
                manualConnections[index].gain = min(max(newValue, 0), 1)
                applyChainToEngine()
            }
        )
    }

    private func manualConnection(for wireID: UUID) -> CanvasConnection? {
        guard let connection = manualConnections.first(where: { $0.id == wireID }) else { return nil }
        let size = canvasSize
        let lane = laneForConnection(connection)

        let fromPoint: CGPoint
        if connection.fromNodeId == startNodeID || connection.fromNodeId == leftStartNodeID || connection.fromNodeId == rightStartNodeID {
            fromPoint = startNodePosition(in: size, lane: lane)
        } else if let node = effectChain.first(where: { $0.id == connection.fromNodeId }) {
            fromPoint = nodePosition(node, in: size)
        } else {
            return nil
        }

        let toPoint: CGPoint
        if connection.toNodeId == endNodeID || connection.toNodeId == leftEndNodeID || connection.toNodeId == rightEndNodeID {
            toPoint = endNodePosition(in: size, lane: lane)
        } else if let node = effectChain.first(where: { $0.id == connection.toNodeId }) {
            toPoint = nodePosition(node, in: size)
        } else {
            return nil
        }

        return CanvasConnection(id: connection.id, from: fromPoint, to: toPoint, toNodeId: connection.toNodeId, isManual: true)
    }

    private func visualManualConnections(in size: CGSize, lane: GraphLane?) -> [CanvasConnection] {
        var connections: [CanvasConnection] = []

        for connection in manualConnections {
            if graphMode == .split {
                guard laneForConnection(connection) == lane else { continue }
            }
            let fromPoint: CGPoint
            if connection.fromNodeId == startNodeID || connection.fromNodeId == leftStartNodeID || connection.fromNodeId == rightStartNodeID {
                fromPoint = startNodePosition(in: size, lane: lane)
            } else if let node = effectChain.first(where: { $0.id == connection.fromNodeId }) {
                fromPoint = nodePosition(node, in: size)
            } else {
                continue
            }

            let toPoint: CGPoint
            if connection.toNodeId == endNodeID || connection.toNodeId == leftEndNodeID || connection.toNodeId == rightEndNodeID {
                toPoint = endNodePosition(in: size, lane: lane)
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
            for nodeID in implicitEndNodes(lane: lane) {
                guard let node = effectChain.first(where: { $0.id == nodeID }) else { continue }
                let fromPoint = nodePosition(node, in: size)
                let toPoint = endNodePosition(in: size, lane: lane)
                connections.append(
                    CanvasConnection(id: UUID(), from: fromPoint, to: toPoint, toNodeId: endNodeID(for: lane), isManual: false)
                )
            }
        }

        return connections
    }

    private func connectionsForCanvas(path ordered: [BeginnerNode], lane: GraphLane?) -> [CanvasConnection] {
        guard !ordered.isEmpty else { return [] }

        let startPoint = startNodePosition(in: canvasSize, lane: lane)
        let endPoint = endNodePosition(in: canvasSize, lane: lane)

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
                CanvasConnection(id: UUID(), from: previousPoint, to: endPoint, toNodeId: endNodeID(for: lane), isManual: false)
            )
        }

        return connections
    }

    private func laneBounds(in size: CGSize, lane: GraphLane) -> CGRect {
        let midX = size.width * 0.5
        switch lane {
        case .left:
            return CGRect(x: 0, y: 0, width: midX, height: size.height)
        case .right:
            return CGRect(x: midX, y: 0, width: size.width - midX, height: size.height)
        }
    }

    private func defaultNodePosition(in size: CGSize, lane: GraphLane?) -> CGPoint {
        if graphMode == .split, let lane {
            let bounds = laneBounds(in: size, lane: lane)
            return CGPoint(x: max(bounds.midX, 100), y: max(bounds.midY, 100))
        }
        return CGPoint(x: max(size.width * 0.5, 100), y: max(size.height * 0.5, 100))
    }

    private func startNodePosition(in size: CGSize, lane: GraphLane?) -> CGPoint {
        if graphMode == .split, let lane {
            let bounds = laneBounds(in: size, lane: lane)
            return CGPoint(x: bounds.minX + 80, y: bounds.midY)
        }
        return CGPoint(x: 80, y: size.height * 0.5)
    }

    private func endNodePosition(in size: CGSize, lane: GraphLane?) -> CGPoint {
        if graphMode == .split, let lane {
            let bounds = laneBounds(in: size, lane: lane)
            return CGPoint(x: max(bounds.maxX - 80, bounds.minX + 80), y: bounds.midY)
        }
        return CGPoint(x: max(size.width - 80, 100), y: size.height * 0.5)
    }

    private func clamp(_ point: CGPoint, to size: CGSize, lane: GraphLane?) -> CGPoint {
        let padding: CGFloat = 80
        if graphMode == .split, let lane {
            let bounds = laneBounds(in: size, lane: lane)
            let x = min(max(point.x, bounds.minX + padding), max(bounds.maxX - padding, bounds.minX + padding))
            let y = min(max(point.y, padding), max(size.height - padding, padding))
            return CGPoint(x: x, y: y)
        }
        let x = min(max(point.x, padding), max(size.width - padding, padding))
        let y = min(max(point.y, padding), max(size.height - padding, padding))
        return CGPoint(x: x, y: y)
    }

    private func connectionPreviewStartPoint(in size: CGSize) -> CGPoint? {
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

        if graphMode == .split {
            let fromLane = laneForNodeID(fromID)
            let toLane = laneForNodeID(targetID)
            guard fromLane == toLane, fromLane != nil else {
                print("   ❌ Cross-lane connection blocked")
                return
            }
        }

        print("   ✅ Found target: \(targetID == endNodeID ? "END" : "effect node")")

        guard !createsCycle(from: fromID, to: targetID) else {
            print("   ❌ Would create cycle")
            return
        }

        print("   ✅ No cycle detected")
        if wiringMode == .automatic {
            manualConnections.removeAll { $0.fromNodeId == fromID || $0.toNodeId == targetID }
        } else {
            manualConnections.removeAll { $0.fromNodeId == fromID && $0.toNodeId == targetID }
        }
        manualConnections.append(BeginnerConnection(fromNodeId: fromID, toNodeId: targetID))
        if wiringMode == .manual {
            normalizeOutgoingGains(from: fromID)
        }
        print("   ✅ Connection created! Total connections: \(manualConnections.count)")
        applyChainToEngine()
    }

    private func nearestConnectionTarget(from fromID: UUID, at point: CGPoint) -> UUID? {
        var closest: (id: UUID, distance: CGFloat)?
        let fromLane = laneForNodeID(fromID)

        for node in effectChain {
            if graphMode == .split, let fromLane, node.lane != fromLane {
                continue
            }
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

        let endID = graphMode == .split ? endNodeID(for: fromLane) : endNodeID
        if fromID != endID {
            let endPoint = endNodePosition(in: canvasSize, lane: fromLane)
            let dx = endPoint.x - point.x
            let dy = endPoint.y - point.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance <= connectionSnapRadius {
                if closest == nil || distance < closest!.distance {
                    closest = (endID, distance)
                }
            }
        }
        return closest?.id
    }

    private func createsCycle(from: UUID, to: UUID) -> Bool {
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

    private func buildNextMap(for lane: GraphLane?) -> [UUID: UUID] {
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

        if wiringMode == .automatic {
            for connection in manualConnections {
                if graphMode == .split, laneForConnection(connection) != lane { continue }
                let fromIsValid = connection.fromNodeId == startID ||
                    effectChain.contains(where: { $0.id == connection.fromNodeId })
                let toIsValid = connection.toNodeId == endID ||
                    effectChain.contains(where: { $0.id == connection.toNodeId })
                guard fromIsValid, toIsValid else { continue }
                nextMap[connection.fromNodeId] = connection.toNodeId
            }
        }

        return nextMap
    }

    private func chainPath(for lane: GraphLane?) -> [BeginnerNode] {
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

    private func reachableNodeIDsFromStart() -> Set<UUID> {
        guard wiringMode == .manual else { return [] }
        if graphMode == .split {
            let left = reachableNodeIDs(from: .left)
            let right = reachableNodeIDs(from: .right)
            return left.union(right)
        }
        return reachableNodeIDs(from: nil)
    }

    private func reachableNodeIDs(from lane: GraphLane?) -> Set<UUID> {
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

    private func implicitEndNodes(lane: GraphLane?) -> [UUID] {
        guard wiringMode == .manual else { return [] }
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

    private func orderedNodesByPosition(lane: GraphLane?) -> [BeginnerNode] {
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

    private func laneForPoint(_ point: CGPoint, in size: CGSize) -> GraphLane {
        point.x < size.width * 0.5 ? .left : .right
    }

    private func startNodeID(for lane: GraphLane?) -> UUID {
        if graphMode == .split {
            return lane == .right ? rightStartNodeID : leftStartNodeID
        }
        return startNodeID
    }

    private func endNodeID(for lane: GraphLane?) -> UUID {
        if graphMode == .split {
            return lane == .right ? rightEndNodeID : leftEndNodeID
        }
        return endNodeID
    }

    private func laneForNodeID(_ id: UUID) -> GraphLane? {
        if graphMode == .split {
            if id == leftStartNodeID || id == leftEndNodeID { return .left }
            if id == rightStartNodeID || id == rightEndNodeID { return .right }
            return effectChain.first(where: { $0.id == id })?.lane
        }
        return nil
    }

    private func laneForConnection(_ connection: BeginnerConnection) -> GraphLane? {
        guard graphMode == .split else { return nil }
        let fromLane = laneForNodeID(connection.fromNodeId)
        let toLane = laneForNodeID(connection.toNodeId)
        guard fromLane == toLane else { return nil }
        return fromLane
    }

    private func syncLanesForSplit() {
        let midX = canvasSize.width * 0.5
        for index in effectChain.indices {
            let position = nodePosition(effectChain[index], in: canvasSize)
            effectChain[index].lane = position.x < midX ? .left : .right
        }
        manualConnections.removeAll { laneForConnection($0) == nil }
    }

    private func nodePosition(_ node: BeginnerNode, in size: CGSize) -> CGPoint {
        node.position == .zero ? defaultNodePosition(in: size, lane: graphMode == .split ? node.lane : nil) : node.position
    }
}


// MARK: - Canvas Drop Delegate

struct CanvasDropDelegate: DropDelegate {
    @Binding var effectChain: [BeginnerNode]
    @Binding var draggedEffectType: EffectType?
    let canvasSize: CGSize
    let graphMode: GraphMode
    let laneProvider: (CGPoint) -> GraphLane
    let onAdd: (BeginnerNode) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let effectType = draggedEffectType else { return false }
        let lane = graphMode == .split ? laneProvider(info.location) : .left
        let location = clamp(info.location, to: canvasSize, lane: graphMode == .split ? lane : nil)
        onAdd(BeginnerNode(type: effectType, position: location, lane: lane))
        draggedEffectType = nil
        return true
    }

    private func clamp(_ point: CGPoint, to size: CGSize, lane: GraphLane?) -> CGPoint {
        let padding: CGFloat = 80
        let x: CGFloat
        if let lane {
            let midX = size.width * 0.5
            let minX = lane == .left ? 0 : midX
            let maxX = lane == .left ? midX : size.width
            x = min(max(point.x, minX + padding), max(maxX - padding, minX + padding))
        } else {
            x = min(max(point.x, padding), max(size.width - padding, padding))
        }
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

// MARK: - Effect Tray

struct EffectTray: View {
    @Binding var isCollapsed: Bool
    let onSelect: (EffectType) -> Void
    let onDrag: (EffectType) -> Void
    @State private var searchText = ""

    private let effects: [EffectType] = [
        .bassBoost, .clarity, .deMud,
        .simpleEQ, .tenBandEQ, .compressor, .reverb, .stereoWidth,
        .delay, .distortion, .tremolo, .chorus, .phaser, .flanger, .bitcrusher, .tapeSaturation,
        .resampling, .rubberBandPitch
    ]

    var body: some View {
        let filteredEffects = effects.filter { effect in
            searchText.isEmpty || effect.rawValue.lowercased().contains(searchText.lowercased())
        }

        ZStack {
            VStack(spacing: 0) {
                if !isCollapsed {
                    HStack(spacing: 8) {
                        Text("Effects")
                            .font(AppTypography.technical)
                            .foregroundColor(AppColors.textMuted)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                    Divider()
                        .background(AppColors.gridLines)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppColors.neonCyan)
                        TextField("Search effects...", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .padding(8)
                    .background(AppColors.darkPurple)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.neonCyan.opacity(0.5), lineWidth: 1)
                    )
                    .cornerRadius(8)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(filteredEffects, id: \.self) { effectType in
                                EffectPaletteButton(
                                    effectType: effectType,
                                    onTap: {
                                        onSelect(effectType)
                                    },
                                    onDragStart: {
                                        onDrag(effectType)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .overlay(alignment: .trailing) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            }) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(6)
                    .background(AppColors.midPurple.opacity(0.95))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .frame(maxHeight: .infinity)
            .zIndex(2)
        }
        .frame(width: isCollapsed ? 44 : 200)
        .background(AppColors.darkPurple.opacity(0.96))
        .overlay(
            Divider(),
            alignment: .trailing
        )
    }
}

struct EffectPaletteButton: View {
    let effectType: EffectType
    let onTap: () -> Void
    let onDragStart: () -> Void
    @State private var isHovered = false
    @State private var isDragging = false
    private let tileBase = AppColors.midPurple
    private let textColor = AppColors.textPrimary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: effectType.icon)
                .font(.system(size: 22, weight: .light))
                .symbolRenderingMode(.monochrome)
                .foregroundColor(textColor)
                .frame(width: 56, height: 56)
                .background(tileBase)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isHovered ? AppColors.neonPink : Color.clear, lineWidth: 1)
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .opacity(isDragging ? 0.5 : 1.0)

            Text(effectType.rawValue)
                .font(AppTypography.caption)
                .foregroundColor(textColor)
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
                        colors: [AppColors.success.opacity(0.8), AppColors.success],
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
                .shadow(color: AppColors.success.opacity(0.6), radius: pulse ? 20 : 10)
                .scaleEffect(pulse ? 1.05 : 1.0)

            Text("Start")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
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
                        colors: [AppColors.neonPink.opacity(0.8), AppColors.neonPink],
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
                .shadow(color: AppColors.neonPink.opacity(0.6), radius: pulse ? 20 : 10)
                .scaleEffect(pulse ? 1.05 : 1.0)

            Text("End")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
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
        let glow = AppColors.neonCyan.opacity(0.2 + 0.8 * intensity)
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
    @State private var bounce: CGFloat = 0

    var body: some View {
        let intensity = min(max(CGFloat(level) * 3.0, 0.0), 1.0)
        let baseOpacity = 0.25 + 0.6 * intensity
        let glowColor = AppColors.neonCyan.opacity(0.35 + 0.55 * intensity)
        let thickness: CGFloat = 2 + 5 * intensity + 2 * bounce
        let packetCount = 4
        let dotsPerPacket = 8
        let packetSpan: CGFloat = 0.22
        let baseDotSize: CGFloat = 2.5 + 3.5 * intensity
        let jitterScale: CGFloat = 6 + 8 * intensity
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let nx = -dy / length
        let ny = dx / length
        Group {
            if isActive {
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let speed = 0.35
                    let phase = CGFloat((time * speed).truncatingRemainder(dividingBy: 1.0))

                    ZStack {
                        Path { path in
                            path.move(to: from)
                            path.addLine(to: to)
                        }
                        .stroke(AppColors.wireActive.opacity(baseOpacity), lineWidth: thickness)
                        .contentShape(Path { path in
                            path.move(to: from)
                            path.addLine(to: to)
                        }.strokedPath(.init(lineWidth: thickness + 10)))

                        Path { path in
                            path.move(to: from)
                            path.addLine(to: to)
                        }
                        .stroke(glowColor, lineWidth: thickness + 4)
                        .blur(radius: 6 + 6 * intensity)

                        ForEach(0..<packetCount, id: \.self) { packetIndex in
                            ForEach(0..<dotsPerPacket, id: \.self) { dotIndex in
                                let packetOffset = CGFloat(packetIndex) / CGFloat(packetCount)
                                let localOffset = (CGFloat(dotIndex) / CGFloat(max(dotsPerPacket - 1, 1))) * packetSpan
                                let t = (phase + packetOffset + localOffset).truncatingRemainder(dividingBy: 1.0)
                                let sizeScale = 0.5 + 0.6 * (1 - CGFloat(dotIndex) / CGFloat(max(dotsPerPacket - 1, 1)))
                                let dotSize = baseDotSize * sizeScale
                                let drift = sin((phase * 6.28318) + CGFloat(packetIndex * 7 + dotIndex)) * jitterScale
                                let basePoint = pointAlongLine(from: from, to: to, t: t)
                                let particlePoint = CGPoint(
                                    x: basePoint.x + nx * drift,
                                    y: basePoint.y + ny * drift
                                )

                                Circle()
                                    .fill(glowColor)
                                    .frame(width: dotSize, height: dotSize)
                                    .position(particlePoint)
                                    .shadow(color: glowColor.opacity(0.7), radius: 6)
                            }
                        }
                    }
                }
            } else {
                Path { path in
                    path.move(to: from)
                    path.addLine(to: to)
                }
                .stroke(AppColors.wireInactive.opacity(0.8), lineWidth: 2)
            }
        }
        .onAppear {
            guard isActive else { return }
            withAnimation(.interpolatingSpring(stiffness: 120, damping: 8).repeatForever(autoreverses: true)) {
                bounce = 1
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

fileprivate struct AccentStyle {
    let fill: Color
    let fillDark: Color
    let text: Color
}


// MARK: - Effect Block

struct EffectBlockHorizontal: View {
    @Binding var effect: BeginnerNode
    let isWired: Bool
    let isSelected: Bool
    fileprivate let tileStyle: AccentStyle
    let onRemove: () -> Void
    let onUpdate: () -> Void
    @State private var isHovered = false
    @State private var isExpanded = false
    private let cardBackground = Color(red: 0.18, green: 0.16, blue: 0.13)
    private let cardBorder = Color(red: 0.68, green: 0.52, blue: 0.32)
    private let tileDisabled = Color(red: 0.32, green: 0.30, blue: 0.26)
    private let disabledText = Color(red: 0.78, green: 0.74, blue: 0.68)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                // Icon and name
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                getEffectEnabled()
                                    ? LinearGradient(
                                        colors: [tileStyle.fill, tileStyle.fillDark],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [tileDisabled, tileDisabled.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    .blur(radius: 0.6)
                                    .offset(y: -0.5)
                                    .mask(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(
                                                LinearGradient(
                                                    colors: [.white, .clear],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )
                                    )
                            )

                        VStack(spacing: 6) {
                            Image(systemName: effect.type.icon)
                                .font(.system(size: 26, weight: .light))
                                .symbolRenderingMode(.monochrome)
                                .foregroundColor(getEffectEnabled() ? tileStyle.text : disabledText)

                            Text(effect.type.rawValue.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.8)
                                .foregroundColor((getEffectEnabled() ? tileStyle.text : disabledText).opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(width: 92, height: 92)
                }

            }
            .padding(10)
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .opacity(isWired ? 1.0 : 0.45)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? cardBorder : Color.clear, lineWidth: 2)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            }

            // Expanded parameters
            if isExpanded {
                VStack(spacing: 12) {
                    EffectParametersViewCompact(
                        effectType: effect.type,
                        parameters: $effect.parameters,
                        onChange: onUpdate
                    )

                    Divider()
                        .background(cardBorder.opacity(0.4))

                    HStack(spacing: 12) {
                        Button(action: {
                            setEffectEnabled(!getEffectEnabled())
                        }) {
                            Label(getEffectEnabled() ? "On" : "Off", systemImage: "power")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive, action: onRemove) {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .frame(width: 220)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.22, green: 0.19, blue: 0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(cardBorder.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                )
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func getEffectEnabled() -> Bool {
        effect.isEnabled
    }

    private func setEffectEnabled(_ enabled: Bool) {
        effect.isEnabled = enabled
        onUpdate()
    }
}

// MARK: - Compact Parameters View

struct EffectParametersViewCompact: View {
    let effectType: EffectType
    @Binding var parameters: NodeEffectParameters
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            switch effectType {
            case .bassBoost:
                CompactSlider(label: "Amount", value: $parameters.bassBoostAmount, range: 0...1, format: .percent, onChange: onChange)

            case .pitchShift:
                EmptyView()

            case .rubberBandPitch:
                CompactSlider(label: "Semitones", value: $parameters.rubberBandPitchSemitones, range: -12...12, format: .semitones, onChange: onChange)

            case .clarity:
                CompactSlider(label: "Amount", value: $parameters.clarityAmount, range: 0...1, format: .percent, onChange: onChange)

            case .deMud:
                CompactSlider(label: "Strength", value: $parameters.deMudStrength, range: 0...1, format: .percent, onChange: onChange)

            case .simpleEQ:
                CompactSlider(label: "Bass", value: $parameters.eqBass, range: -1...1, format: .db, onChange: onChange)
                CompactSlider(label: "Mids", value: $parameters.eqMids, range: -1...1, format: .db, onChange: onChange)
                CompactSlider(label: "Treble", value: $parameters.eqTreble, range: -1...1, format: .db, onChange: onChange)

            case .tenBandEQ:
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 8) {
                    CompactSlider(label: "31", value: bandBinding(0), range: -12...12, format: .dbValue, onChange: onChange)
                    CompactSlider(label: "62", value: bandBinding(1), range: -12...12, format: .dbValue, onChange: onChange)
                    CompactSlider(label: "125", value: bandBinding(2), range: -12...12, format: .dbValue, onChange: onChange)
                    CompactSlider(label: "250", value: bandBinding(3), range: -12...12, format: .dbValue, onChange: onChange)
                    CompactSlider(label: "500", value: bandBinding(4), range: -12...12, format: .dbValue, onChange: onChange)
                    CompactSlider(label: "1k", value: bandBinding(5), range: -12...12, format: .dbValue, onChange: onChange)
                    CompactSlider(label: "2k", value: bandBinding(6), range: -12...12, format: .dbValue, onChange: onChange)
                    CompactSlider(label: "4k", value: bandBinding(7), range: -12...12, format: .dbValue, onChange: onChange)
                    CompactSlider(label: "8k", value: bandBinding(8), range: -12...12, format: .dbValue, onChange: onChange)
                    CompactSlider(label: "16k", value: bandBinding(9), range: -12...12, format: .dbValue, onChange: onChange)
                }

            case .compressor:
                CompactSlider(label: "Strength", value: $parameters.compressorStrength, range: 0...1, format: .percent, onChange: onChange)

            case .reverb:
                CompactSlider(label: "Mix", value: $parameters.reverbMix, range: 0...1, format: .percent, onChange: onChange)
                CompactSlider(label: "Size", value: $parameters.reverbSize, range: 0...1, format: .percent, onChange: onChange)

            case .stereoWidth:
                CompactSlider(label: "Width", value: $parameters.stereoWidthAmount, range: 0...1, format: .percent, onChange: onChange)

            case .delay:
                CompactSlider(label: "Time", value: $parameters.delayTime, range: 0.01...2.0, format: .ms, onChange: onChange)
                CompactSlider(label: "Feedback", value: $parameters.delayFeedback, range: 0...1, format: .percent, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.delayMix, range: 0...1, format: .percent, onChange: onChange)

            case .distortion:
                CompactSlider(label: "Drive", value: $parameters.distortionDrive, range: 0...1, format: .percent, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.distortionMix, range: 0...1, format: .percent, onChange: onChange)

            case .tremolo:
                CompactSlider(label: "Rate", value: $parameters.tremoloRate, range: 0.1...20, format: .hz, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.tremoloDepth, range: 0...1, format: .percent, onChange: onChange)

            case .chorus:
                CompactSlider(label: "Rate", value: $parameters.chorusRate, range: 0.1...5, format: .hz, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.chorusDepth, range: 0...1, format: .percent, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.chorusMix, range: 0...1, format: .percent, onChange: onChange)

            case .phaser:
                CompactSlider(label: "Rate", value: $parameters.phaserRate, range: 0.1...5, format: .hz, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.phaserDepth, range: 0...1, format: .percent, onChange: onChange)

            case .flanger:
                CompactSlider(label: "Rate", value: $parameters.flangerRate, range: 0.1...5, format: .hz, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.flangerDepth, range: 0...1, format: .percent, onChange: onChange)
                CompactSlider(label: "Feedback", value: $parameters.flangerFeedback, range: 0...0.95, format: .percent, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.flangerMix, range: 0...1, format: .percent, onChange: onChange)

            case .bitcrusher:
                CompactSlider(label: "Bit Depth", value: $parameters.bitcrusherBitDepth, range: 4...16, format: .integer, onChange: onChange)
                CompactSlider(label: "Downsample", value: $parameters.bitcrusherDownsample, range: 1...20, format: .integer, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.bitcrusherMix, range: 0...1, format: .percent, onChange: onChange)

            case .tapeSaturation:
                CompactSlider(label: "Drive", value: $parameters.tapeSaturationDrive, range: 0...1, format: .percent, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.tapeSaturationMix, range: 0...1, format: .percent, onChange: onChange)

            case .resampling:
                CompactSlider(label: "Rate", value: $parameters.resampleRate, range: 0.5...2.0, format: .ratio, onChange: onChange)
                CompactSlider(label: "Smooth", value: $parameters.resampleCrossfade, range: 0.05...0.6, format: .percent, onChange: onChange)
            }
        }
    }

    private func bandBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard parameters.tenBandGains.indices.contains(index) else { return 0 }
                return parameters.tenBandGains[index]
            },
            set: { newValue in
                if parameters.tenBandGains.count < 10 {
                    parameters.tenBandGains += Array(repeating: 0, count: 10 - parameters.tenBandGains.count)
                }
                if parameters.tenBandGains.indices.contains(index) {
                    parameters.tenBandGains[index] = newValue
                }
            }
        )
    }
}

struct CompactSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: ValueFormat
    let onChange: (() -> Void)?

    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: ValueFormat,
        onChange: (() -> Void)? = nil
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.format = format
        self.onChange = onChange
    }

    enum ValueFormat {
        case percent
        case db
        case dbValue
        case ms
        case hz
        case integer
        case ratio
        case semitones
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
                .onChange(of: value) { _ in
                    onChange?()
                }
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
        case .integer:
            return String(format: "%.0f", value)
        case .ratio:
            return String(format: "%.2fx", value)
        case .semitones:
            return String(format: "%+.1f st", value)
        }
    }
}

// MARK: - Supporting Types

// Preview disabled to avoid build-time macro errors.
