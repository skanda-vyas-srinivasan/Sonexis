import SwiftUI
import AppKit

// MARK: - Canvas View

let canvasRootCoordinateSpace = "CanvasViewRootLayer"

enum CanvasLayerZIndex {
    static let canvasPane: Double = 0
    static let effectTray: Double = 10
    static let floatingBackdrop: Double = 90
    static let floatingMenu: Double = 100
}

struct CanvasFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct CanvasDocumentFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct CanvasView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var tutorial: TutorialController
    @ObservedObject var pluginManager: PluginManager
    var chainWorkspace: ChainWorkspace? = nil
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(AppTheme.storageKey) var selectedThemeID = AppTheme.defaultThemeID
    @State var effectChain: [BeginnerNode] = []
    @State var draggedEffectType: EffectType?
    @State var draggedPlugin: PluginDescriptor?
    @State var showSignalFlow = false
    @State var arrowFpsIndex = 3
    @State var canvasSize: CGSize = .zero
    @State var minimumCanvasSize: CGSize = .zero
    @State var draggingNodeID: UUID?
    @State var dragStartPosition: CGPoint = .zero
    @State var manualConnections: [BeginnerConnection] = []
    @State var activeConnectionFromID: UUID?
    @State var activeConnectionPoint: CGPoint = .zero
    @State var wiringMode: WiringMode = .automatic
    @State var autoConnectEnd: Bool = false
    @State var selectedNodeIDs: Set<UUID> = []
    @State var lassoStart: CGPoint?
    @State var lassoCurrent: CGPoint?
    @State var selectionDragStartPositions: [UUID: CGPoint] = [:]
    @State var selectedWireID: UUID?
    @State var selectedAutoWire: AutoWireSelection?
    @State var wireGainPopoverAnchor: CGPoint?
    @State var autoGainOverrides: [WireKey: Double] = [:]
    @State var pluginStatusToken = 0

    @State var startNodeID = UUID()
    @State var endNodeID = UUID()
    @State var leftStartNodeID = UUID()
    @State var leftEndNodeID = UUID()
    @State var rightStartNodeID = UUID()
    @State var rightEndNodeID = UUID()
    @State var graphMode: GraphMode = .single
    @State var nextAccentIndex = 0
    @State var isAppActive = true
    @State var isTrayCollapsed = false
    @State var dropAnimatedNodeIDs: Set<UUID> = []
    @State var beatPulse: CGFloat = 0
    @State var nodeScale: CGFloat = 1.0
    @State var nodeStartScale: CGFloat = 1.0
    @State var customContextMenu: CustomContextMenu?
    @State var wireContextMenu: CustomContextMenu?
    @State var isRestoringSnapshot = false
    @State var isCanvasHovering = false
    @State var isOptionHeld = false
    @State var flagsMonitor: Any?
    @State var isWindowKey = true
    @State var betaUnlockBuffer = ""
    @State var lastAppliedAudioGraphSignature: Int?
    @State var pendingAudioGraphApplyWorkItem: DispatchWorkItem?
    @State var pendingAudioGraphApplyReason = "graph edit"
    @State var pendingAudioGraphApplyForce = false
    @State var canvasFrameInRoot: CGRect = .zero
    @State var canvasDocumentFrameInRoot: CGRect = .zero
    @State var didPrepareAdvancedTutorialCanvas = false
    @State var expandedControlPanelLifts: [UUID: CGFloat] = [:]
    let connectionSnapRadius: CGFloat = 120
    let wireContextMenuOverlap: CGFloat = 18
    let effectEndpointVisualSize = CGSize(width: 110, height: 110)
    let terminalEndpointVisualSize = CGSize(width: 60, height: 60)
    let arrowFpsOptions: [Double] = [0, 12, 20, 24, 30, 40]
    let betaUnlockPhrase = "poopymcbutt"
    let debugGraphLifecycle = false


    var activeTheme: AppTheme {
        AppTheme.theme(for: selectedThemeID)
    }

    var accentPalette: [AccentStyle] {
        let palette = activeTheme.palette

        if activeTheme == .gold {
            return [
                AccentStyle(
                    fill: palette.neonCyan,
                    fillDark: palette.textSecondary.opacity(0.38),
                    highlight: palette.neonPink,
                    text: palette.textPrimary
                ),
                AccentStyle(
                    fill: palette.neonPink,
                    fillDark: palette.neonPink.opacity(0.34),
                    highlight: palette.neonCyan,
                    text: palette.textPrimary
                ),
                AccentStyle(
                    fill: palette.textSecondary,
                    fillDark: palette.textSecondary.opacity(0.34),
                    highlight: palette.neonPink,
                    text: palette.textPrimary
                ),
                AccentStyle(
                    fill: palette.synthPink,
                    fillDark: palette.synthPink.opacity(0.30),
                    highlight: palette.neonCyan,
                    text: palette.textPrimary
                )
            ]
        }

        return [
            AccentStyle(
                fill: palette.neonCyan,
                fillDark: palette.neonCyan.opacity(0.34),
                highlight: palette.neonPink,
                text: palette.textPrimary
            ),
            AccentStyle(
                fill: palette.neonPink,
                fillDark: palette.neonPink.opacity(0.34),
                highlight: palette.neonCyan,
                text: palette.textPrimary
            ),
            AccentStyle(
                fill: palette.synthPurple,
                fillDark: palette.synthPurple.opacity(0.34),
                highlight: palette.warning,
                text: palette.textPrimary
            ),
            AccentStyle(
                fill: palette.success,
                fillDark: palette.success.opacity(0.34),
                highlight: palette.electricBlue,
                text: palette.textPrimary
            ),
            AccentStyle(
                fill: palette.warning,
                fillDark: palette.warning.opacity(0.34),
                highlight: palette.neonPink,
                text: palette.textPrimary
            ),
            AccentStyle(
                fill: palette.synthOrange,
                fillDark: palette.synthOrange.opacity(0.34),
                highlight: palette.synthPurple,
                text: palette.textPrimary
            ),
            AccentStyle(
                fill: palette.electricBlue,
                fillDark: palette.electricBlue.opacity(0.34),
                highlight: palette.success,
                text: palette.textPrimary
            )
        ]
    }

    var isCanvasMenuLimitedForTutorial: Bool {
        tutorial.step == .buildResetWiringForParallel || tutorial.step == .buildClearCanvasForDualMono
    }

    var canUseClearCanvasAction: Bool {
        !isCanvasMenuLimitedForTutorial || tutorial.step == .buildClearCanvasForDualMono
    }

    var canUseResetWiringAction: Bool {
        !isCanvasMenuLimitedForTutorial || tutorial.step == .buildResetWiringForParallel
    }

    enum WiringMode {
        case automatic  // Position-based with manual override
        case manual     // Pure manual wiring only
    }

    var graphModeLabel: String {
        graphMode == .single ? "Stereo" : "Dual Mono"
    }

    var wiringModeLabel: String {
        wiringMode == .automatic ? "Automatic" : "Manual"
    }

    @ViewBuilder
    var toolbarView: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Stereo") {
                    changeGraphMode(to: .single)
                }
                Button("Dual Mono") {
                    changeGraphMode(to: .split)
                }
            } label: {
                CanvasToolbarMenuLabel(
                    title: "Graph Mode",
                    value: graphModeLabel,
                    tint: AppColors.neonCyan
                )
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
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
                guard !isRestoringSnapshot else { return }
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

            Menu {
                Button("Automatic") {
                    changeWiringMode(to: .automatic)
                }
                Button("Manual") {
                    changeWiringMode(to: .manual)
                }
            } label: {
                CanvasToolbarMenuLabel(
                    title: "Wiring",
                    value: wiringModeLabel,
                    tint: AppColors.neonPink
                )
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .disabled(tutorial.isBuildStep && ![.buildWiringManual, .buildReturnStereoAuto].contains(tutorial.step))
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

            HStack(spacing: 8) {
                Text("Auto-connect End")
                    .lineLimit(1)
                    .fixedSize()
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
                Toggle("", isOn: $autoConnectEnd)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(wiringMode == .automatic || tutorial.isBuildStep)
                    .opacity(wiringMode == .automatic || tutorial.isBuildStep ? 0.4 : 1.0)
                    .onChange(of: autoConnectEnd) { _ in
                        guard !isRestoringSnapshot else { return }
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

            Spacer()

            Menu {
                if canUseClearCanvasAction {
                    Button("Clear Canvas") {
                        clearCanvas()
                    }
                }
                if canUseResetWiringAction {
                    Button("Reset Wiring") {
                        resetWiring()
                    }
                    .disabled(manualConnections.isEmpty && autoGainOverrides.isEmpty)
                }
            } label: {
                CanvasToolbarMenuLabel(
                    title: "Canvas",
                    value: nil,
                    tint: AppColors.neonCyan
                )
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
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
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColors.panelPurple.opacity(0.72))
        .overlay(
            AppColors.controlStroke.opacity(0.30)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    var leftAutoPath: [BeginnerNode] {
        graphMode == .split ? chainPath(for: .left) : chainPath(for: nil)
    }

    var rightAutoPath: [BeginnerNode] {
        graphMode == .split ? chainPath(for: .right) : []
    }

    var pathIDs: Set<UUID> {
        if wiringMode == .automatic {
            return Set((leftAutoPath + rightAutoPath).map { $0.id })
        }
        return reachableNodeIDsFromStart()
    }

    var isAnimating: Bool {
        audioEngine.isRunning && showSignalFlow && isAppActive
    }

    var arrowFps: Double {
        arrowFpsOptions[arrowFpsIndex]
    }

    @ViewBuilder
    func canvasContent(in geometry: GeometryProxy) -> some View {
                    ZStack {
                    AppSurfaces.background
                        .ignoresSafeArea()

                    CanvasWaveLinesBackground()

                    StaticGrid()
                        .opacity(0.34)

                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            clearGraphSelection()
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    // Allow lasso selection during connection steps for better UX
                                    let allowLassoDuringTutorial = tutorial.step == .buildSelection ||
                                                                   tutorial.step == .buildConnect ||
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
                                    let allowLassoDuringTutorial = tutorial.step == .buildSelection ||
                                                                   tutorial.step == .buildConnect ||
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
                                allowAnimation: isAppActive,
                                fromEndpointSize: endpointVisualSize(for: connection.fromNodeId),
                                toEndpointSize: endpointVisualSize(for: connection.toNodeId)
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
                                allowAnimation: isAppActive,
                                fromEndpointSize: endpointVisualSize(for: connection.fromNodeId),
                                toEndpointSize: endpointVisualSize(for: connection.toNodeId)
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

                    // Keep the initial wire menu in the same document
                    // coordinate space as the correctly placed gain editor.
                    if let menu = wireContextMenu {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture { dismissCustomContextMenu() }
                            .zIndex(CanvasLayerZIndex.floatingBackdrop)

                        CustomContextMenuView(menu: menu) {
                            dismissCustomContextMenu()
                        }
                        .zIndex(CanvasLayerZIndex.floatingMenu)
                    }

                    if let wireID = selectedWireID,
                       let binding = gainBinding(for: wireID),
                       let wire = manualConnection(for: wireID) {
                        let midpoint = CGPoint(
                            x: (wire.from.x + wire.to.x) * 0.5,
                            y: (wire.from.y + wire.to.y) * 0.5 - 28
                        )
                        let anchor = wireGainPopoverAnchor ?? midpoint
                        GainPopoverView(
                            tint: AppColors.neonCyan,
                            value: binding
                        ) {
                            selectedWireID = nil
                            wireGainPopoverAnchor = nil
                            tutorial.didFinishWireGain()
                        }
                        .position(CanvasViewportLayout.contextMenuPosition(
                            click: anchor,
                            size: CGSize(width: 180, height: 128),
                            visibleRect: visibleCanvasRect
                        ))
                        .zIndex(5)
                    } else if let autoWire = selectedAutoWire,
                              let binding = autoGainBinding(for: autoWire.key) {
                        GainPopoverView(
                            tint: autoWire.tint,
                            value: binding
                        ) {
                            selectedAutoWire = nil
                            wireGainPopoverAnchor = nil
                        }
                        .position(CanvasViewportLayout.contextMenuPosition(
                            click: autoWire.popoverAnchor,
                            size: CGSize(width: 180, height: 128),
                            visibleRect: visibleCanvasRect
                        ))
                        .zIndex(5)
                    }

                    if let start = lassoStart, let current = lassoCurrent {
                        let rect = selectionRect(from: start, to: current)
                        Path { path in
                            path.addRect(rect)
                        }
                        .fill(Color.blue.opacity(0.08))

                        Path { path in
                            path.addRect(rect)
                        }
                        .stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
                                        let canWire = wiringMode == .manual && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect)
                                        // Only check Option when starting a new connection
                                        let shouldStartConnection = activeConnectionFromID == nil && NSEvent.modifierFlags.contains(.option)
                                        let isDraggingConnection = activeConnectionFromID == leftStartNodeID

                                        if canWire && (shouldStartConnection || isDraggingConnection) {
                                            let start = startNodePosition(in: geometry.size, lane: .left)
                                            activeConnectionFromID = leftStartNodeID
                                            activeConnectionPoint = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { value in
                                        // Finalize if we were dragging a connection from this node
                                        if activeConnectionFromID == leftStartNodeID {
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
                                        let canWire = wiringMode == .manual && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect)
                                        let shouldStartConnection = activeConnectionFromID == nil && NSEvent.modifierFlags.contains(.option)
                                        let isDraggingConnection = activeConnectionFromID == rightStartNodeID

                                        if canWire && (shouldStartConnection || isDraggingConnection) {
                                            let start = startNodePosition(in: geometry.size, lane: .right)
                                            activeConnectionFromID = rightStartNodeID
                                            activeConnectionPoint = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { value in
                                        if activeConnectionFromID == rightStartNodeID {
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
                                        let canWire = wiringMode == .manual && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect)
                                        let shouldStartConnection = activeConnectionFromID == nil && NSEvent.modifierFlags.contains(.option)
                                        let isDraggingConnection = activeConnectionFromID == startNodeID

                                        if canWire && (shouldStartConnection || isDraggingConnection) {
                                            let start = startNodePosition(in: geometry.size, lane: nil)
                                            activeConnectionFromID = startNodeID
                                            activeConnectionPoint = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { value in
                                        if activeConnectionFromID == startNodeID {
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
                            audioEngine: audioEngine,
                            effect: effect,
                            isWired: isWired,
                            isSelected: isSelected,
                            isDropAnimating: isDropAnimating,
                            tileStyle: accentPalette[effectValue.accentIndex % accentPalette.count],
                            nodeScale: nodeScale,
                            pluginStatusText: effectValue.type == .plugin
                                ? audioEngine.pluginStatusText(effectValue.id)
                                : nil,
                            onRemove: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    removeEffect(id: effectValue.id)
                                }
                            },
                            onUpdate: {
                                applyChainToEngine()
                            },
                            onParameterChange: {
                                updateChainParametersOnly()
                                if effectValue.type == .bassBoost { tutorial.advanceIf(.buildEffectControls) }
                            },
                            onExpanded: {
                                setControlPanelLift(for: effectValue, in: geometry.size)
                                tutorial.advanceIf(.buildDoubleClick)
                            },
                            onCollapsed: {
                                clearControlPanelLift(for: effectValue.id)
                                tutorial.advanceIf(.buildCloseOverlay)
                            },
                            onOpenPluginEditor: {
                                openPluginEditor(for: effectValue.id)
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
                                    let canWire = wiringMode == .manual && (!tutorial.isBuildStep || tutorial.step == .buildConnect || tutorial.step == .buildParallelConnect || tutorial.step == .buildDualMonoConnect)
                                    // Only check Option when starting a new connection
                                    let shouldStartConnection = activeConnectionFromID == nil && NSEvent.modifierFlags.contains(.option)
                                    let isDraggingConnection = activeConnectionFromID == effectValue.id

                                    if canWire && (shouldStartConnection || isDraggingConnection) {
                                        // Wiring mode
                                        activeConnectionFromID = effectValue.id
                                        activeConnectionPoint = CGPoint(
                                            x: nodePos.x + value.translation.width,
                                            y: nodePos.y + value.translation.height
                                        )
                                    } else if activeConnectionFromID == nil {
                                        // Only allow move mode if not dragging a connection
                                        // Allow node movement during reorder and connection steps
                                        let allowMoveDuringTutorial = tutorial.step == .buildSelection ||
                                                                      tutorial.step == .buildAutoReorder ||
                                                                      tutorial.step == .buildConnect ||
                                                                      tutorial.step == .buildParallelConnect ||
                                                                      tutorial.step == .buildDualMonoConnect
                                        if tutorial.isBuildStep && !allowMoveDuringTutorial {
                                            return
                                        }
                                        if tutorial.step == .buildAutoReorder && effectValue.type != .clarity {
                                            return
                                        }
                                        // Move mode
                                        if draggingNodeID != effectValue.id {
                                            // Keep scrolling anchored while the outermost node moves inward.
                                            minimumCanvasSize = canvasSize
                                            draggingNodeID = effectValue.id
                                            dragStartPosition = nodePosition(effectValue, in: geometry.size)
                                            if !selectedNodeIDs.contains(effectValue.id) && !NSEvent.modifierFlags.contains(.shift) {
                                                selectedNodeIDs = [effectValue.id]
                                            }
                                            if selectedNodeIDs.contains(effectValue.id) {
                                                selectionDragStartPositions = selectedNodeIDs.reduce(into: [:]) { result, id in
                                                    if let node = effectChain.first(where: { $0.id == id }) {
                                                        result[id] = nodePosition(node, in: geometry.size)
                                                    }
                                                }
                                            } else {
                                                selectionDragStartPositions.removeAll()
                                            }
                                        }
                                        let delta = CGSize(width: value.translation.width, height: value.translation.height)
                                        if selectedNodeIDs.contains(effectValue.id), !selectionDragStartPositions.isEmpty {
                                            moveSelectedNodes(by: delta, in: geometry.size)
                                        } else {
                                            let newPosition = CGPoint(
                                                x: dragStartPosition.x + delta.width,
                                                y: dragStartPosition.y + delta.height
                                            )
                                            updateNodePosition(
                                                effectValue.id,
                                                position: clampNodePosition(
                                                    newPosition,
                                                    id: effectValue.id,
                                                    to: geometry.size,
                                                    lane: graphMode == .split ? effectValue.lane : nil
                                                )
                                            )
                                        }
                                    }
                                }
                                .onEnded { value in
                                    // Check if we were dragging a connection from this node
                                    if activeConnectionFromID == effectValue.id {
                                        // Finalize wiring
                                        let dropPoint = CGPoint(
                                            x: nodePos.x + value.translation.width,
                                            y: nodePos.y + value.translation.height
                                        )
                                        finalizeConnection(from: effectValue.id, dropPoint: dropPoint)
                                    } else {
                                        // Allow node movement during reorder and connection steps
                                        let allowMoveDuringTutorial = tutorial.step == .buildSelection ||
                                                                      tutorial.step == .buildAutoReorder ||
                                                                      tutorial.step == .buildConnect ||
                                                                      tutorial.step == .buildParallelConnect ||
                                                                      tutorial.step == .buildDualMonoConnect
                                        if tutorial.isBuildStep && !allowMoveDuringTutorial {
                                            activeConnectionFromID = nil
                                            activeConnectionPoint = .zero
                                            return
                                        }
                                        if tutorial.step == .buildAutoReorder && effectValue.type != .clarity {
                                            activeConnectionFromID = nil
                                            activeConnectionPoint = .zero
                                            return
                                        }
                                        activeConnectionFromID = nil
                                        activeConnectionPoint = .zero
                                        // Finalize move
                                        draggingNodeID = nil
                                        selectionDragStartPositions.removeAll()
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
                                .font(.system(size: 30, weight: .light))
                                .foregroundColor(AppColors.neonCyan.opacity(0.32))
                            Text("Drop effects here")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(AppColors.textSecondary.opacity(0.62))
                        }
                    }
                }
    }

    @ViewBuilder
    var canvasView: some View {
        GeometryReader { viewport in
            let size = CanvasViewportLayout.contentSize(
                viewport: viewport.size, positions: effectChain.map(\.position),
                nodeScale: nodeScale, minimumSize: minimumCanvasSize
            )
            ScrollView([.horizontal, .vertical]) {
                canvasDocumentView
                    .frame(width: size.width, height: size.height)
                    .background(GeometryReader { document in
                        Color.clear.preference(
                            key: CanvasDocumentFramePreferenceKey.self,
                            value: document.frame(in: .named(canvasRootCoordinateSpace))
                        )
                    })
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(
                    key: TutorialTargetPreferenceKey.self,
                    value: [.buildCanvas: proxy.frame(in: .global)]
                )
            })
        }
    }

    @ViewBuilder
    var canvasDocumentView: some View {
        GeometryReader { geometry in
            canvasContent(in: geometry)
                .onHover { hovering in
                    isCanvasHovering = hovering
                    updateCursor()
                }
                .onAppear {
                    updateCanvasSizeIfNeeded(geometry.size)
                }
                .onChange(of: geometry.size) { newSize in
                    updateCanvasSizeIfNeeded(newSize)
                }
                .background(WindowFocusReader { isKey in
                    updateFocusState(isKeyWindow: isKey)
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
                    draggedPlugin: $draggedPlugin,
                    canvasSize: geometry.size,
                    graphMode: graphMode,
                    laneProvider: { point in
                        laneForPoint(point, in: geometry.size)
                    },
                    onAdd: { newNode in
                        let stepAtDrop = tutorial.step
                        if tutorial.isBuildStep && ![
                            TutorialStep.buildAddBass,
                            .buildAutoAddClarity,
                            .buildParallelAddReverb,
                            .buildDualMonoAdd,
                            .chainsOverrides
                        ].contains(stepAtDrop) {
                            return
                        }
                        if [.buildAddBass, .chainsOverrides].contains(stepAtDrop) && newNode.type != .bassBoost {
                            return
                        }
                        if stepAtDrop == .buildAutoAddClarity && newNode.type != .clarity {
                            return
                        }
                        if stepAtDrop == .buildAutoAddClarity,
                           let bassNode = effectChain.first(where: { $0.type == .bassBoost }) {
                            let bassPosition = displayNodePosition(bassNode, in: geometry.size)
                            guard newNode.position.x < bassPosition.x else { return }
                        }
                        if stepAtDrop == .buildParallelAddReverb && newNode.type != .reverb {
                            return
                        }
                        if stepAtDrop == .buildDualMonoAdd && ![EffectType.bassBoost, .clarity].contains(newNode.type) {
                            return
                        }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            var node = newNode
                            node.accentIndex = nextAccentIndex
                            nextAccentIndex = (nextAccentIndex + 1) % accentPalette.count
                            effectChain.append(node)
                            triggerDropAnimation(for: node.id)
                            applyChainToEngine()
                            switch stepAtDrop {
                            case .buildAddBass, .buildAutoAddClarity, .buildParallelAddReverb, .chainsOverrides:
                                tutorial.advance()
                            case .buildDualMonoAdd:
                                maybeAdvanceDualMonoTutorial()
                            default:
                                break
                            }
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
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                EffectTray(
                    isCollapsed: $isTrayCollapsed,
                    pluginManager: pluginManager,
                    previewStyle: accentPalette[nextAccentIndex % accentPalette.count],
                    onDrag: { type in
                        draggedEffectType = type
                    },
                    onDragPlugin: { plugin in
                        draggedPlugin = plugin
                    },
                    onTabChange: { tab in
                        if tutorial.step == .buildTrayTabs && tab != .builtIn {
                            tutorial.hasVisitedTrayTabs = true
                        }
                    },
                    tutorialStep: tutorial.step
                )
                .zIndex(CanvasLayerZIndex.effectTray)

                VStack(spacing: 0) {
                    if let chainWorkspace {
                        ChainStrip(workspace: chainWorkspace).disabled(tutorial.isActive && !tutorial.isAppChainTour)
                    }
                    toolbarView

                    Divider()
                        .background(AppColors.gridLines)

                    canvasView
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: CanvasFramePreferenceKey.self,
                                    value: proxy.frame(in: .named(canvasRootCoordinateSpace))
                                )
                            }
                        )
                }
                .frame(minWidth: 820, maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(CanvasLayerZIndex.canvasPane)
            }

            floatingContextMenuLayer
        }
        .coordinateSpace(name: canvasRootCoordinateSpace)
        .animation(.easeInOut(duration: 0.18), value: selectedThemeID)
        .onPreferenceChange(CanvasFramePreferenceKey.self) { frame in
            canvasFrameInRoot = frame
        }
        .onPreferenceChange(CanvasDocumentFramePreferenceKey.self) { frame in
            canvasDocumentFrameInRoot = frame
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
            updateSignalFlowVisibility()
            prepareAdvancedTutorialCanvasIfNeeded()
        }
        .onChange(of: tutorial.step) { step in
            if step == .advancedIntro {
                prepareAdvancedTutorialCanvasIfNeeded()
            } else if step == .inactive || step == .welcome {
                didPrepareAdvancedTutorialCanvas = false
            }
            if step != .buildRightClick && step != .buildActionMenu {
                customContextMenu = nil
                wireContextMenu = nil
            }
            if step != .buildWireLevels {
                selectedWireID = nil
                selectedAutoWire = nil
            }
            if step == .buildWiringManual && wiringMode == .manual {
                tutorial.advance()
            }
            if step == .buildGraphMode && graphMode == .split {
                tutorial.advance()
            }
        }
        .onChange(of: effectChain.isEmpty) { isEmpty in
            if isEmpty { minimumCanvasSize = .zero }
        }
        .onChange(of: audioEngine.isRunning) { isRunning in
            updateSignalFlowVisibility(isRunning: isRunning)
        }
        .onChange(of: scenePhase) { phase in
            updateSignalFlowVisibility(scenePhase: phase)
        }
        .onReceive(audioEngine.$pendingGraphLoadRequest) { request in
            guard let request else { return }
            DispatchQueue.main.async {
                restorePendingGraphSnapshot(
                    request.snapshot,
                    mode: request.mode,
                    reason: request.reason
                )
                audioEngine.pendingGraphLoadRequest = nil
            }
        }
        .onReceive(audioEngine.$signalFlowToken) { _ in
            // WindowFocusReader tracks this canvas's window. A popup or plugin
            // window becoming/resigning key must not overwrite that state.
            updateSignalFlowVisibility()
        }
        .onReceive(audioEngine.$pluginStatusToken) { token in
            guard pluginStatusToken != token else { return }
            pluginStatusToken = token
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
            if pendingAudioGraphApplyWorkItem != nil {
                let reason = pendingAudioGraphApplyReason
                let force = pendingAudioGraphApplyForce
                cancelPendingAudioGraphApply()
                performChainApplyToEngine(reason: "canvas disappear: \(reason)", forceAudioApply: force)
            }
        }
    }
}
