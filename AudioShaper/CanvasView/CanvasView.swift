import SwiftUI

// MARK: - Canvas View

struct CanvasView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var tutorial: TutorialController
    @Environment(\.scenePhase) private var scenePhase
    @State private var effectChain: [BeginnerNode] = []
    @State private var draggedEffectType: EffectType?
    @State private var showSignalFlow = false
    @State private var arrowFpsIndex = 1
    @State private var canvasSize: CGSize = .zero
    @State private var draggingNodeID: UUID?
    @State private var dragStartPosition: CGPoint = .zero
    @State private var manualConnections: [BeginnerConnection] = []
    @State private var activeConnectionFromID: UUID?
    @State private var activeConnectionPoint: CGPoint = .zero
    @State private var wiringMode: WiringMode = .automatic
    @State private var autoConnectEnd: Bool = false
    @State private var selectedNodeIDs: Set<UUID> = []
    @State private var lassoStart: CGPoint?
    @State private var lassoCurrent: CGPoint?
    @State private var selectionDragStartPositions: [UUID: CGPoint] = [:]
    @State private var selectedWireID: UUID?
    @State private var selectedAutoWire: AutoWireSelection?
    @State private var autoGainOverrides: [WireKey: Double] = [:]

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
    @State private var dropAnimatedNodeIDs: Set<UUID> = []
    @State private var beatPulse: CGFloat = 0
    @State private var nodeScale: CGFloat = 1.0
    @State private var nodeStartScale: CGFloat = 1.0
    @State private var customContextMenu: CustomContextMenu?
    @State private var undoStack: [GraphSnapshot] = []
    @State private var redoStack: [GraphSnapshot] = []
    @State private var dragUndoSnapshot: GraphSnapshot?
    @State private var isRestoringSnapshot = false
    @State private var isCanvasHovering = false
    @State private var isOptionHeld = false
    @State private var flagsMonitor: Any?
    @State private var isWindowKey = true
    private let connectionSnapRadius: CGFloat = 120
    private let arrowFpsOptions: [Double] = [0, 12, 20, 24, 30, 40]
    private let accentPalette: [AccentStyle] = [
        AccentStyle(
            fill: Color(hex: "#00F5FF"),
            fillDark: Color(hex: "#007C88"),
            highlight: Color(hex: "#FF5FBF"),
            text: .white
        ),
        AccentStyle(
            fill: Color(hex: "#FF5FBF"),
            fillDark: Color(hex: "#7A1F4A"),
            highlight: Color(hex: "#00F5FF"),
            text: .white
        ),
        AccentStyle(
            fill: Color(hex: "#8B3DFF"),
            fillDark: Color(hex: "#3A0B73"),
            highlight: Color(hex: "#FFB800"),
            text: .white
        ),
        AccentStyle(
            fill: Color(hex: "#00FF88"),
            fillDark: Color(hex: "#00733D"),
            highlight: Color(hex: "#00D9FF"),
            text: .white
        ),
        AccentStyle(
            fill: Color(hex: "#FFB800"),
            fillDark: Color(hex: "#7A4C00"),
            highlight: Color(hex: "#FF5FBF"),
            text: .white
        ),
        AccentStyle(
            fill: Color(hex: "#FF6B00"),
            fillDark: Color(hex: "#7A2E00"),
            highlight: Color(hex: "#8B3DFF"),
            text: .white
        ),
        AccentStyle(
            fill: Color(hex: "#00D9FF"),
            fillDark: Color(hex: "#004866"),
            highlight: Color(hex: "#00FF88"),
            text: .white
        )
    ]

    enum WiringMode {
        case automatic  // Position-based with manual override
        case manual     // Pure manual wiring only
    }

    @ViewBuilder
    private var toolbarView: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                Text("Graph Mode")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
                Picker("", selection: $graphMode) {
                    Text("Stereo").tag(GraphMode.single)
                    Text("Dual Mono (L/R)").tag(GraphMode.split)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(tutorial.isBuildStep && ![.buildGraphMode, .buildReturnStereoAuto].contains(tutorial.step))
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [.buildGraphMode: proxy.frame(in: .global)]
                        )
                    }
                )
                .onChange(of: graphMode) { _ in
                    if graphMode == .split {
                        syncLanesForSplit()
                    }
                    applyChainToEngine()
                    tutorial.advanceIf(.buildGraphMode)
                    if tutorial.step == .buildReturnStereoAuto,
                       graphMode == .single,
                       wiringMode == .automatic {
                        tutorial.advance()
                    }
                    // Ensure animations continue after picker interaction
                    DispatchQueue.main.async {
                        let keyWindow = NSApp.keyWindow?.isKeyWindow ?? isWindowKey
                        if keyWindow && scenePhase == .active {
                            isAppActive = true
                            showSignalFlow = audioEngine.isRunning
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Wiring")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
                Picker("", selection: $wiringMode) {
                    Text("Automatic").tag(WiringMode.automatic)
                    Text("Manual").tag(WiringMode.manual)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(tutorial.isBuildStep && ![.buildWiringManual, .buildReturnStereoAuto, .buildDualMonoConnect].contains(tutorial.step))
                .help(wiringMode == .automatic ?
                      "Automatic: Effects flow left-to-right by position." :
                      "Manual: Pure manual wiring. Option+drag to connect.")
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [.buildWiringMode: proxy.frame(in: .global)]
                        )
                    }
                )
                .onChange(of: wiringMode) { newMode in
                    guard !isRestoringSnapshot else { return }
                    if newMode == .automatic {
                        activeConnectionFromID = nil
                        activeConnectionPoint = .zero
                        isOptionHeld = false
                    } else if newMode == .manual {
                        // Clear all wiring when switching to manual
                        manualConnections.removeAll()
                    }
                    applyChainToEngine()
                    updateCursor()
                    tutorial.advanceIf(.buildWiringManual)
                    if tutorial.step == .buildReturnStereoAuto,
                       graphMode == .single,
                       wiringMode == .automatic {
                        tutorial.advance()
                    }
                    // Ensure animations continue after picker interaction
                    DispatchQueue.main.async {
                        let keyWindow = NSApp.keyWindow?.isKeyWindow ?? isWindowKey
                        if keyWindow && scenePhase == .active {
                            isAppActive = true
                            showSignalFlow = audioEngine.isRunning
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Auto-connect End")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
                Toggle("", isOn: $autoConnectEnd)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(wiringMode == .automatic || (tutorial.isBuildStep && tutorial.step != .buildAutoConnectEnd))
                    .opacity(wiringMode == .automatic ? 0.4 : 1.0)
                    .help(wiringMode == .automatic ?
                          "Automatic mode handles all connections." :
                          (autoConnectEnd ?
                           "Auto-connect End: On - Last nodes auto-connect to End." :
                           "Auto-connect End: Off - Manually connect to End."))
                    .onChange(of: autoConnectEnd) { _ in
                        applyChainToEngine()
                        // Ensure animations continue after toggle interaction
                        DispatchQueue.main.async {
                            let keyWindow = NSApp.keyWindow?.isKeyWindow ?? isWindowKey
                            if keyWindow && scenePhase == .active {
                                isAppActive = true
                                showSignalFlow = audioEngine.isRunning
                            }
                        }
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TutorialTargetPreferenceKey.self,
                                value: [.buildAutoConnectEnd: proxy.frame(in: .global)]
                            )
                        }
                    )
            }

            HStack(spacing: 6) {
                Text("Flow")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
                Button(arrowFps == 0 ? "Flow Off" : "\(Int(arrowFps)) FPS") {
                    arrowFpsIndex = (arrowFpsIndex + 1) % arrowFpsOptions.count
                }
                .buttonStyle(.plain)
                .foregroundColor(AppColors.textSecondary)
                .disabled(tutorial.isBuildStep)
            }

            HStack(spacing: 6) {
                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(undoStack.isEmpty ? AppColors.textMuted : AppColors.textSecondary)
                .disabled(undoStack.isEmpty || tutorial.isBuildStep)

                Button {
                    redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(redoStack.isEmpty ? AppColors.textMuted : AppColors.textSecondary)
                .disabled(redoStack.isEmpty || tutorial.isBuildStep)
            }

            Spacer()

            Menu {
                Button("Clear Canvas") {
                    clearCanvas()
                }
                Button("Reset Wiring") {
                    resetWiring()
                }
                .disabled(manualConnections.isEmpty && autoGainOverrides.isEmpty)
            } label: {
                Text("Canvas")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TutorialTargetPreferenceKey.self,
                        value: [.buildCanvasMenu: proxy.frame(in: .global)]
                    )
                }
            )
            .disabled(tutorial.isBuildStep && ![.buildResetWiringForParallel, .buildClearCanvasForDualMono].contains(tutorial.step))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColors.midPurple.opacity(0.9))
    }

    private var leftAutoPath: [BeginnerNode] {
        graphMode == .split ? chainPath(for: .left) : chainPath(for: nil)
    }

    private var rightAutoPath: [BeginnerNode] {
        graphMode == .split ? chainPath(for: .right) : []
    }

    private var pathIDs: Set<UUID> {
        if wiringMode == .automatic {
            return Set((leftAutoPath + rightAutoPath).map { $0.id })
        }
        return reachableNodeIDsFromStart()
    }

    private var isAnimating: Bool {
        audioEngine.isRunning && showSignalFlow && isAppActive
    }

    private var arrowFps: Double {
        arrowFpsOptions[arrowFpsIndex]
    }

    @ViewBuilder
    private func canvasContent(in geometry: GeometryProxy) -> some View {
                    ZStack {
                    AppGradients.background
                        .ignoresSafeArea()

                    StaticGrid()

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
                                    // Allow lasso selection during connection steps for better UX
                                    let allowLassoDuringTutorial = tutorial.step == .buildConnect ||
                                                                   tutorial.step == .buildParallelConnect ||
                                                                   tutorial.step == .buildDualMonoConnect
                                    guard !tutorial.isBuildStep || allowLassoDuringTutorial else { return }
                                    guard !NSEvent.modifierFlags.contains(.option) else { return }
                                    guard draggingNodeID == nil else { return }

                                    if lassoStart == nil {
                                        lassoStart = value.startLocation
                                    }
                                    lassoCurrent = value.location
                                }
                                .onEnded { _ in
                                    let allowLassoDuringTutorial = tutorial.step == .buildConnect ||
                                                                   tutorial.step == .buildParallelConnect ||
                                                                   tutorial.step == .buildDualMonoConnect
                                    guard !tutorial.isBuildStep || allowLassoDuringTutorial else {
                                        lassoStart = nil
                                        lassoCurrent = nil
                                        return
                                    }
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
                                level: levelForNode(connection.toNodeId),
                                beatPulse: beatPulse,
                                fps: arrowFps,
                                allowAnimation: isAppActive
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
                                level: levelForNode(connection.toNodeId),
                                beatPulse: beatPulse,
                                fps: arrowFps,
                                allowAnimation: isAppActive
                            )
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
                        GainPopoverView(
                            tint: AppColors.neonCyan,
                            value: binding
                        ) {
                            selectedWireID = nil
                        }
                        .position(midpoint)
                        .zIndex(5)
                    } else if let autoWire = selectedAutoWire,
                              let binding = autoGainBinding(for: autoWire.key) {
                        GainPopoverView(
                            tint: autoWire.tint,
                            value: binding
                        ) {
                            selectedAutoWire = nil
                        }
                        .position(autoWire.midpoint)
                        .zIndex(5)
                    }

                    if let menu = customContextMenu {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture {
                                customContextMenu = nil
                                tutorial.advanceIf(.buildCloseContextMenu)
                            }

                        CustomContextMenuView(menu: menu) {
                            customContextMenu = nil
                            tutorial.advanceIf(.buildCloseContextMenu)
                        }
                        .zIndex(10)
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
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if wiringMode == .manual && NSEvent.modifierFlags.contains(.option) && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect) {
                                            let start = startNodePosition(in: geometry.size, lane: .left)
                                            activeConnectionFromID = leftStartNodeID
                                            activeConnectionPoint = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { value in
                                        if wiringMode == .manual && NSEvent.modifierFlags.contains(.option) && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect) {
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

                        StartNodeView()
                            .position(startNodePosition(in: geometry.size, lane: .right))
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if wiringMode == .manual && NSEvent.modifierFlags.contains(.option) && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect) {
                                            let start = startNodePosition(in: geometry.size, lane: .right)
                                            activeConnectionFromID = rightStartNodeID
                                            activeConnectionPoint = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { value in
                                        if wiringMode == .manual && NSEvent.modifierFlags.contains(.option) && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect) {
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
                    } else {
                        StartNodeView()
                            .position(startNodePosition(in: geometry.size, lane: nil))
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if wiringMode == .manual && NSEvent.modifierFlags.contains(.option) && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect) {
                                            let start = startNodePosition(in: geometry.size, lane: nil)
                                            activeConnectionFromID = startNodeID
                                            activeConnectionPoint = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { value in
                                        if wiringMode == .manual && NSEvent.modifierFlags.contains(.option) && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect) {
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
                    }

                    ForEach($effectChain) { effect in
                        let effectValue = effect.wrappedValue
                        let nodePos = displayNodePosition(effectValue, in: geometry.size)
                        let isWired = pathIDs.contains(effectValue.id)
                        let isSelected = selectedNodeIDs.contains(effectValue.id)
                        let isDropAnimating = dropAnimatedNodeIDs.contains(effectValue.id)

                        EffectBlockHorizontal(
                            effect: effect,
                            isWired: isWired,
                            isSelected: isSelected,
                            isDropAnimating: isDropAnimating,
                            tileStyle: accentPalette[effectValue.accentIndex % accentPalette.count],
                            nodeScale: nodeScale,
                            onRemove: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    removeEffect(id: effectValue.id)
                                }
                            },
                            onUpdate: {
                                applyChainToEngine()
                            },
                            onExpanded: {
                                tutorial.advanceIf(.buildDoubleClick)
                            },
                            onCollapsed: {
                                tutorial.advanceIf(.buildCloseOverlay)
                            },
                            allowExpand: !tutorial.isBuildStep || tutorial.step == .buildDoubleClick || tutorial.step == .buildCloseOverlay,
                            tutorialStep: tutorial.step
                        )
                        .scaleEffect(nodeScale)
                        .position(nodePos)
                        .background(
                            GeometryReader { proxy in
                                if effectValue.type == .bassBoost {
                                    Color.clear.preference(
                                        key: TutorialTargetPreferenceKey.self,
                                        value: [.buildBassNode: proxy.frame(in: .global)]
                                    )
                                } else if effectValue.type == .clarity {
                                    Color.clear.preference(
                                        key: TutorialTargetPreferenceKey.self,
                                        value: [.buildClarityNode: proxy.frame(in: .global)]
                                    )
                                } else if effectValue.type == .reverb {
                                    Color.clear.preference(
                                        key: TutorialTargetPreferenceKey.self,
                                        value: [.buildReverbNode: proxy.frame(in: .global)]
                                    )
                                }
                            }
                        )
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {
                                    if tutorial.isBuildStep {
                                        return
                                    }
                                    guard wiringMode == .manual else { return }
                                    let isShift = NSEvent.modifierFlags.contains(.shift)
                                    if isShift {
                                        toggleSelection(effectValue.id)
                                    } else {
                                        selectedNodeIDs = [effectValue.id]
                                    }
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                        let hasOption = wiringMode == .manual && NSEvent.modifierFlags.contains(.option) && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect)
                                    if hasOption {
                                        // Wiring mode
                                        activeConnectionFromID = effectValue.id
                                        activeConnectionPoint = CGPoint(
                                            x: nodePos.x + value.translation.width,
                                            y: nodePos.y + value.translation.height
                                        )
                                    } else {
                                        // Allow node movement during reorder and connection steps
                                        let allowMoveDuringTutorial = tutorial.step == .buildAutoReorder ||
                                                                      tutorial.step == .buildConnect ||
                                                                      tutorial.step == .buildParallelConnect ||
                                                                      tutorial.step == .buildDualMonoConnect
                                        if tutorial.isBuildStep && !allowMoveDuringTutorial {
                                            return
                                        }
                                        // Move mode
                                        if draggingNodeID != effectValue.id {
                                            draggingNodeID = effectValue.id
                                            if dragUndoSnapshot == nil {
                                                dragUndoSnapshot = currentGraphSnapshot()
                                            }
                                            dragStartPosition = nodePosition(effectValue, in: geometry.size)
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
                                                x: dragStartPosition.x + delta.width,
                                                y: dragStartPosition.y + delta.height
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
                                    let hasOption = wiringMode == .manual && NSEvent.modifierFlags.contains(.option) && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect)
                                    if hasOption {
                                        // Finalize wiring
                                        let dropPoint = CGPoint(
                                            x: nodePos.x + value.translation.width,
                                            y: nodePos.y + value.translation.height
                                        )
                                        finalizeConnection(from: effectValue.id, dropPoint: dropPoint)
                                    } else {
                                        // Allow node movement during reorder and connection steps
                                        let allowMoveDuringTutorial = tutorial.step == .buildAutoReorder ||
                                                                      tutorial.step == .buildConnect ||
                                                                      tutorial.step == .buildParallelConnect ||
                                                                      tutorial.step == .buildDualMonoConnect
                                        if tutorial.isBuildStep && !allowMoveDuringTutorial {
                                            activeConnectionFromID = nil
                                            activeConnectionPoint = .zero
                                            return
                                        }
                                        activeConnectionFromID = nil
                                        activeConnectionPoint = .zero
                                        // Finalize move
                                        draggingNodeID = nil
                                        selectionDragStartPositions.removeAll()
                                        if let snapshot = dragUndoSnapshot {
                                            recordUndoSnapshot(snapshot)
                                        }
                                        dragUndoSnapshot = nil
                                        applyChainToEngine()
                                        if tutorial.step == .buildAutoReorder {
                                            maybeAdvanceAutoReorderTutorial()
                                        }
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
    }

    @ViewBuilder
    private var canvasView: some View {
        GeometryReader { geometry in
            canvasContent(in: geometry)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [.buildCanvas: proxy.frame(in: .global)]
                        )
                    }
                )
                .onHover { hovering in
                    isCanvasHovering = hovering
                    updateCursor()
                }
                .onAppear {
                    canvasSize = geometry.size
                }
                .onChange(of: geometry.size) { newSize in
                    canvasSize = newSize
                }
                .background(WindowFocusReader { isKey in
                    isWindowKey = isKey
                    let active = scenePhase == .active && isWindowKey
                    isAppActive = active
                    showSignalFlow = active && audioEngine.isRunning
                })
                .contentShape(Rectangle())
                .overlay(
                    ZStack {
                        RightClickCapture { location in
                            handleRightClick(at: location, in: geometry.size)
                        }
                        KeyEventCapture { event in
                            handleKeyDown(event)
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
                .onDrop(of: [.text], delegate: CanvasDropDelegate(
                    effectChain: $effectChain,
                    draggedEffectType: $draggedEffectType,
                    canvasSize: geometry.size,
                    graphMode: graphMode,
                    laneProvider: { point in
                        laneForPoint(point, in: geometry.size)
                    },
                    onAdd: { newNode in
                        if tutorial.isBuildStep && ![
                            TutorialStep.buildAddBass,
                            .buildAutoAddClarity,
                            .buildParallelAddReverb,
                            .buildDualMonoAdd
                        ].contains(tutorial.step) {
                            return
                        }
                        if tutorial.step == .buildAddBass && newNode.type != .bassBoost {
                            return
                        }
                        if tutorial.step == .buildAutoAddClarity && newNode.type != .clarity {
                            return
                        }
                        if tutorial.step == .buildParallelAddReverb && newNode.type != .reverb {
                            return
                        }
                        if tutorial.step == .buildDualMonoAdd && ![EffectType.bassBoost, .clarity].contains(newNode.type) {
                            return
                        }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            recordUndoSnapshot()
                            var node = newNode
                            node.accentIndex = nextAccentIndex
                            nextAccentIndex = (nextAccentIndex + 1) % accentPalette.count
                            effectChain.append(node)
                            triggerDropAnimation(for: node.id)
                            applyChainToEngine()
                            tutorial.advanceIf(.buildAddBass)
                            tutorial.advanceIf(.buildAutoAddClarity)
                            tutorial.advanceIf(.buildParallelAddReverb)
                            maybeAdvanceDualMonoTutorial()
                        }
                    }
                ))
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            guard !tutorial.isBuildStep else { return }
                            let next = nodeStartScale * value
                            nodeScale = min(max(next, 0.4), 1.8)
                        }
                        .onEnded { _ in
                            guard !tutorial.isBuildStep else { return }
                            nodeStartScale = nodeScale
                        }
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var body: some View {
        HStack(spacing: 0) {
            EffectTray(
                isCollapsed: $isTrayCollapsed,
                previewStyle: accentPalette[nextAccentIndex % accentPalette.count],
                onSelect: { type in
                    addEffectToChain(type)
                },
                onDrag: { type in
                    draggedEffectType = type
                },
                allowTapToAdd: !tutorial.isBuildStep || ![
                    .buildAddBass,
                    .buildAutoAddClarity,
                    .buildParallelAddReverb,
                    .buildDualMonoAdd
                ].contains(tutorial.step)
            )

            VStack(spacing: 0) {
                toolbarView

                Divider()
                    .background(AppColors.gridLines)

                canvasView
            }
        }
        .overlay(
            HStack {
                Button("Zoom In") { zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
            }
            .hidden()
        )
        .onAppear {
            showSignalFlow = audioEngine.isRunning
        }
        .onChange(of: tutorial.step) { step in
            if step == .buildWiringManual && wiringMode == .manual {
                tutorial.advance()
            }
            if step == .buildGraphMode && graphMode == .split {
                tutorial.advance()
            }
        }
        .onChange(of: audioEngine.isRunning) { isRunning in
            showSignalFlow = isRunning
        }
        .onChange(of: scenePhase) { phase in
            let active = phase == .active && isWindowKey
            isAppActive = active
            showSignalFlow = active && audioEngine.isRunning
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isWindowKey = true
            let active = scenePhase == .active
            isAppActive = active && isWindowKey
            showSignalFlow = isAppActive && audioEngine.isRunning
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            isWindowKey = false
            isAppActive = false
            showSignalFlow = false
        }
        .onReceive(audioEngine.$pendingGraphSnapshot) { snapshot in
            guard let snapshot else { return }
            isRestoringSnapshot = true
            applyGraphSnapshot(snapshot)
            DispatchQueue.main.async {
                isRestoringSnapshot = false
            }
            audioEngine.pendingGraphSnapshot = nil
        }
        .onReceive(audioEngine.$signalFlowToken) { _ in
            let keyWindow = NSApp.keyWindow?.isKeyWindow ?? isWindowKey
            isWindowKey = keyWindow
            let active = scenePhase == .active && isWindowKey
            isAppActive = active
            showSignalFlow = active && audioEngine.isRunning
        }
        .onAppear {
            if flagsMonitor == nil {
                flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    isOptionHeld = wiringMode == .manual && event.modifierFlags.contains(.option)
                    updateCursor()
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
        }
    }

    private func updateCursor() {
        guard isCanvasHovering else {
            NSCursor.arrow.set()
            return
        }
        if isOptionHeld && wiringMode == .manual {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func addEffectToChain(_ type: EffectType) {
        if tutorial.isBuildStep && ![TutorialStep.buildAddBass, .buildDualMonoAdd].contains(tutorial.step) {
            return
        }
        if tutorial.step == .buildAddBass && type != .bassBoost {
            return
        }
        if tutorial.step == .buildDualMonoAdd && ![EffectType.bassBoost, .clarity].contains(type) {
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            recordUndoSnapshot()
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
            triggerDropAnimation(for: newEffect.id)
            applyChainToEngine()
            tutorial.advanceIf(.buildAddBass)
            maybeAdvanceDualMonoTutorial()
        }
    }

    private func triggerDropAnimation(for id: UUID) {
        dropAnimatedNodeIDs.insert(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            dropAnimatedNodeIDs.remove(id)
        }
    }


    private func removeEffect(id: UUID) {
        recordUndoSnapshot()
        effectChain.removeAll { $0.id == id }
        manualConnections.removeAll { $0.fromNodeId == id || $0.toNodeId == id }
        autoGainOverrides = autoGainOverrides.filter { $0.key.from != id && $0.key.to != id }
        selectedNodeIDs.remove(id)
        normalizeAllOutgoingGains()
        applyChainToEngine()
    }

    private func duplicateEffect(id: UUID) {
        recordUndoSnapshot()
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
        recordUndoSnapshot()
        guard let index = effectChain.firstIndex(where: { $0.id == id }) else { return }
        effectChain[index].parameters = NodeEffectParameters.defaults()
        applyChainToEngine()
    }

    private func removeEffects(ids: Set<UUID>) {
        recordUndoSnapshot()
        effectChain.removeAll { ids.contains($0.id) }
        manualConnections.removeAll { ids.contains($0.fromNodeId) || ids.contains($0.toNodeId) }
        autoGainOverrides = autoGainOverrides.filter { !ids.contains($0.key.from) && !ids.contains($0.key.to) }
        selectedNodeIDs.subtract(ids)
        normalizeAllOutgoingGains()
        applyChainToEngine()
    }

    private func deleteWiresForSelected() {
        recordUndoSnapshot()
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
                rightEndID: rightEndNodeID,
                autoConnectEnd: autoConnectEnd
            )
            // Debug overlay removed.
        } else {
            let path = chainPath(for: nil)
            if wiringMode == .automatic {
                // Debug output removed.
            } else {
                let edges = manualGraphEdges(lane: nil)
                // Debug output removed.
            }
            if wiringMode == .manual {
                audioEngine.updateEffectGraph(
                    nodes: effectChain,
                    connections: manualConnections,
                    startID: startNodeID,
                    endID: endNodeID,
                    autoConnectEnd: autoConnectEnd
                )
                // Debug overlay removed.
            } else {
                if autoGainOverrides.isEmpty {
                    audioEngine.updateEffectChain(path)
                } else {
                    let connections = autoConnections(for: .left)
                    audioEngine.updateEffectGraph(
                        nodes: effectChain,
                        connections: connections,
                        startID: startNodeID,
                        endID: endNodeID
                    )
                }
                // Debug overlay removed.
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
        let filteredAutoGains = snapshot.autoGainOverrides.filter {
            !removedIds.contains($0.fromNodeId) && !removedIds.contains($0.toNodeId)
        }
        autoGainOverrides = Dictionary(
            uniqueKeysWithValues: filteredAutoGains.map {
                (WireKey(from: $0.fromNodeId, to: $0.toNodeId), $0.gain)
            }
        )
        startNodeID = snapshot.startNodeID
        endNodeID = snapshot.endNodeID
        leftStartNodeID = snapshot.leftStartNodeID ?? leftStartNodeID
        leftEndNodeID = snapshot.leftEndNodeID ?? leftEndNodeID
        rightStartNodeID = snapshot.rightStartNodeID ?? rightStartNodeID
        rightEndNodeID = snapshot.rightEndNodeID ?? rightEndNodeID
        graphMode = snapshot.graphMode
        wiringMode = snapshot.wiringMode == .manual ? .manual : .automatic
        autoConnectEnd = snapshot.autoConnectEnd
        if graphMode == .split {
            manualConnections.removeAll { laneForConnection($0) == nil }
        }
        let maxAccent = effectChain.map(\.accentIndex).max() ?? -1
        nextAccentIndex = (maxAccent + 1) % accentPalette.count
        selectedNodeIDs.removeAll()
        selectedWireID = nil
        selectedAutoWire = nil
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
            autoConnectEnd: autoConnectEnd,
            nodes: effectChain,
            connections: manualConnections,
            autoGainOverrides: autoGainOverrides.map {
                BeginnerConnection(fromNodeId: $0.key.from, toNodeId: $0.key.to, gain: $0.value)
            },
            startNodeID: startNodeID,
            endNodeID: endNodeID,
            leftStartNodeID: leftStartNodeID,
            leftEndNodeID: leftEndNodeID,
            rightStartNodeID: rightStartNodeID,
            rightEndNodeID: rightEndNodeID,
            hasNodeParameters: true
        )
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

    private func displayNodePosition(_ node: BeginnerNode, in size: CGSize) -> CGPoint {
        nodePosition(node, in: size)
    }

    private func zoomIn() {
        nodeScale = min(nodeScale + 0.1, 1.8)
        nodeStartScale = nodeScale
    }

    private func zoomOut() {
        nodeScale = max(nodeScale - 0.1, 0.4)
        nodeStartScale = nodeScale
    }

    private func selectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func menuAdjusted(_ menu: CustomContextMenu) -> CustomContextMenu {
        let padding: CGFloat = 12
        let size = menu.size
        var x = menu.anchor.x + size.width * 0.5 + 12
        if x + size.width * 0.5 > canvasSize.width - padding {
            x = menu.anchor.x - size.width * 0.5 - 12
        }
        let minY = size.height * 0.5 + padding
        let maxY = max(canvasSize.height - size.height * 0.5 - padding, minY)
        let y = min(max(menu.anchor.y, minY), maxY)
        return CustomContextMenu(anchor: menu.anchor, position: CGPoint(x: x, y: y), tint: menu.tint, items: menu.items)
    }

    private func menuAtPoint(_ menu: CustomContextMenu, point: CGPoint) -> CustomContextMenu {
        let padding: CGFloat = 12
        let size = menu.size
        let minX = size.width * 0.5 + padding
        let maxX = max(canvasSize.width - size.width * 0.5 - padding, minX)
        let minY = size.height * 0.5 + padding
        let maxY = max(canvasSize.height - size.height * 0.5 - padding, minY)
        let x = min(max(point.x, minX), maxX)
        let y = min(max(point.y, minY), maxY)
        return CustomContextMenu(anchor: menu.anchor, position: CGPoint(x: x, y: y), tint: menu.tint, items: menu.items)
    }

    private func updateSelection(in rect: CGRect, additive: Bool) {
        let matched = effectChain.filter { node in
            rect.contains(displayNodePosition(node, in: canvasSize))
        }
        if additive {
            selectedNodeIDs.formUnion(matched.map { $0.id })
        } else {
            selectedNodeIDs = Set(matched.map { $0.id })
        }
    }

    private func handleRightClick(at point: CGPoint, in size: CGSize) {
        if tutorial.isBuildStep && tutorial.step != .buildRightClick && tutorial.step != .buildCloseContextMenu {
            return
        }
        // Check nodes
        let nodeRadius: CGFloat = 60 * nodeScale
        if let hitNode = effectChain.first(where: { node in
            let pos = displayNodePosition(node, in: size)
            return hypot(point.x - pos.x, point.y - pos.y) <= nodeRadius
        }) {
            if tutorial.step == .buildRightClick && hitNode.type != .bassBoost {
                return
            }
            var items: [CustomContextMenu.Item] = [
                CustomContextMenu.Item(
                    title: "Delete Node",
                    role: .destructive,
                    action: { removeEffect(id: hitNode.id) }
                ),
                CustomContextMenu.Item(
                    title: "Duplicate Node",
                    role: nil,
                    action: { duplicateEffect(id: hitNode.id) }
                ),
                CustomContextMenu.Item(
                    title: "Reset Node Params",
                    role: nil,
                    action: { resetEffectParameters(id: hitNode.id) }
                )
            ]
            if wiringMode == .manual {
                items.insert(
                    CustomContextMenu.Item(
                        title: "Delete Node Wires",
                        role: nil,
                        action: { removeWires(for: hitNode.id) }
                    ),
                    at: 1
                )
            }
            let tint = accentPalette[hitNode.accentIndex % accentPalette.count].fill
            let menu = CustomContextMenu(anchor: displayNodePosition(hitNode, in: size), position: point, tint: tint, items: items)
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
                            title: "Set Gain…",
                            role: nil,
                            action: {
                                selectedAutoWire = nil
                                selectedWireID = hit.id
                            }
                        )
                    ]
                )
                customContextMenu = menuAtPoint(menu, point: point)
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
                            title: "Set Gain…",
                            role: nil,
                            action: {
                                selectedWireID = nil
                                selectedAutoWire = AutoWireSelection(
                                    key: wireKey,
                                    midpoint: midpoint,
                                    tint: AppColors.neonCyan
                                )
                            }
                        )
                    ]
                )
                customContextMenu = menuAtPoint(menu, point: point)
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
                            title: "Delete Node Wires",
                            role: nil,
                            action: { removeWires(for: startNodeID) }
                        )
                    ]
                )
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
                            title: "Delete Node Wires",
                            role: nil,
                            action: { removeWires(for: endNodeID) }
                        )
                    ]
                )
                customContextMenu = menuAdjusted(menu)
                return
            }
        }

        customContextMenu = nil
    }

    private func distanceToSegment(_ p: CGPoint, _ v: CGPoint, _ w: CGPoint) -> CGFloat {
        let l2 = pow(v.x - w.x, 2) + pow(v.y - w.y, 2)
        guard l2 > 0 else { return hypot(p.x - v.x, p.y - v.y) }
        let t = max(0, min(1, ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2))
        let proj = CGPoint(x: v.x + t * (w.x - v.x), y: v.y + t * (w.y - v.y))
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    private func toggleSelection(_ id: UUID) {
        if selectedNodeIDs.contains(id) {
            selectedNodeIDs.remove(id)
        } else {
            selectedNodeIDs.insert(id)
        }
    }

    private func removeWires(for nodeID: UUID) {
        recordUndoSnapshot()
        manualConnections.removeAll { $0.fromNodeId == nodeID || $0.toNodeId == nodeID }
        normalizeOutgoingGains(from: nodeID)
        applyChainToEngine()
    }

    private func deleteManualConnection(_ id: UUID) {
        recordUndoSnapshot()
        if let connection = manualConnections.first(where: { $0.id == id }) {
            manualConnections.removeAll { $0.id == id }
            normalizeOutgoingGains(from: connection.fromNodeId)
        }
        applyChainToEngine()
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectedNodeIDs = Set(effectChain.map { $0.id })
            return
        }

        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) {
                redo()
            } else {
                undo()
            }
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            guard !selectedNodeIDs.isEmpty else { return }
            removeEffects(ids: selectedNodeIDs)
        }
    }

    private func clearCanvas() {
        recordUndoSnapshot()
        effectChain.removeAll()
        manualConnections.removeAll()
        autoGainOverrides.removeAll()
        selectedNodeIDs.removeAll()
        selectedWireID = nil
        selectedAutoWire = nil
        nextAccentIndex = 0
        applyChainToEngine()
        tutorial.advanceIf(.buildClearCanvasForDualMono)
    }

    private func resetWiring() {
        recordUndoSnapshot()
        manualConnections.removeAll()
        autoGainOverrides.removeAll()
        selectedWireID = nil
        selectedAutoWire = nil
        applyChainToEngine()
        tutorial.advanceIf(.buildResetWiringForParallel)
    }

    private func recordUndoSnapshot() {
        recordUndoSnapshot(currentGraphSnapshot())
    }

    private func recordUndoSnapshot(_ snapshot: GraphSnapshot) {
        guard !isRestoringSnapshot else { return }
        undoStack.append(snapshot)
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    private func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        isRestoringSnapshot = true
        redoStack.append(currentGraphSnapshot())
        applyGraphSnapshot(snapshot)
        isRestoringSnapshot = false
    }

    private func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        isRestoringSnapshot = true
        undoStack.append(currentGraphSnapshot())
        applyGraphSnapshot(snapshot)
        isRestoringSnapshot = false
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

    private func autoGainBinding(for key: WireKey) -> Binding<Double>? {
        Binding(
            get: { autoGainOverrides[key] ?? 1.0 },
            set: { newValue in
                autoGainOverrides[key] = min(max(newValue, 0), 1)
                applyChainToEngine()
            }
        )
    }

    private func autoGain(for fromID: UUID, toID: UUID) -> Double {
        autoGainOverrides[WireKey(from: fromID, to: toID)] ?? 1.0
    }

    private func manualConnection(for wireID: UUID) -> CanvasConnection? {
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

    private func connectionsForCanvas(path ordered: [BeginnerNode], lane: GraphLane?) -> [CanvasConnection] {
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
            return displayNodePosition(fromNode, in: size)
        }
        return nil
    }

    private func finalizeConnection(from fromID: UUID, dropPoint: CGPoint) {
        recordUndoSnapshot()

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

    private func shouldAdvanceConnectTutorial() -> Bool {
        // Tutorial expectation: Start → Bass Boost → End (stereo graph, manual wiring).
        guard let bassNode = effectChain.first(where: { $0.type == .bassBoost }) else { return false }
        let hasStartToBass = manualConnections.contains { $0.fromNodeId == startNodeID && $0.toNodeId == bassNode.id }
        let hasBassToEnd = manualConnections.contains { $0.fromNodeId == bassNode.id && $0.toNodeId == endNodeID }
        return hasStartToBass && hasBassToEnd
    }

    private struct TutorialEdge: Hashable {
        let from: UUID
        let to: UUID
    }

    private func tutorialAllowsConnection(from: UUID, to: UUID) -> Bool {
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

    private func shouldAdvanceParallelTutorial() -> Bool {
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

    private func shouldAdvanceDualMonoConnectTutorial() -> Bool {
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

    private func maybeAdvanceAutoReorderTutorial() {
        guard tutorial.step == .buildAutoReorder else { return }
        guard let bass = effectChain.first(where: { $0.type == .bassBoost }),
              let clarity = effectChain.first(where: { $0.type == .clarity })
        else { return }
        let bassPos = displayNodePosition(bass, in: canvasSize)
        let clarityPos = displayNodePosition(clarity, in: canvasSize)
        if clarityPos.x < bassPos.x {
            tutorial.advance()
        }
    }

    private func maybeAdvanceDualMonoTutorial() {
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

    private func nearestConnectionTarget(from fromID: UUID, at point: CGPoint) -> UUID? {
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


