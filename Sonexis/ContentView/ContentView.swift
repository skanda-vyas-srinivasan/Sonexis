import SwiftUI
import AppKit

private struct ScreenFrameReader: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> ScreenFrameReportingView {
        let view = ScreenFrameReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ScreenFrameReportingView, context: Context) {
        nsView.onChange = onChange
        nsView.scheduleReport()
    }
}

private final class ScreenFrameReportingView: NSView {
    var onChange: ((CGRect) -> Void)?
    private var lastFrame: CGRect = .zero

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleReport()
    }

    override func layout() {
        super.layout()
        scheduleReport()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleReport()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        scheduleReport()
    }

    func scheduleReport() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            let rectInWindow = self.convert(self.bounds, to: nil)
            guard rectInWindow.width > 1, rectInWindow.height > 1 else { return }
            if self.lastFrame != rectInWindow {
                self.lastFrame = rectInWindow
                self.onChange?(rectInWindow)
            }
        }
    }
}

private final class AudioSettingsOutsideClickCoordinator: ObservableObject {
    var panelFrame: CGRect = .zero
    private var monitor: Any?

    func start(onDismiss: @escaping () -> Void) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.panelFrame.width > 1, self.panelFrame.height > 1 else { return event }

            var clickPoints = [event.locationInWindow]
            if let contentHeight = event.window?.contentView?.bounds.height {
                clickPoints.append(
                    CGPoint(
                        x: event.locationInWindow.x,
                        y: contentHeight - event.locationInWindow.y
                    )
                )
            }

            let expandedPanelFrame = self.panelFrame.insetBy(dx: -16, dy: -16)
            if clickPoints.contains(where: { expandedPanelFrame.contains($0) }) {
                return event
            }

            DispatchQueue.main.async {
                onDismiss()
            }
            return nil
        }
    }

    func stop() {
        panelFrame = .zero
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stop()
    }
}

struct ContentView: View {
    var openEditor: () -> Void = {}
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var presetManager: PresetManager
    @ObservedObject var chainWorkspace: ChainWorkspace
    @StateObject private var pluginManager = PluginManager()
    @ObservedObject var tutorial: TutorialController
    @StateObject private var audioSettingsOutsideClick = AudioSettingsOutsideClickCoordinator()
    @Binding var activeScreen: AppScreen
    @State private var showingSaveDialog = false
    @State private var showingLoadDialog = false
    @State private var presetNameInput = ""
    @State private var presetNameError: String?
    @Binding var currentPresetID: UUID?
    @State private var saveStatusText: String?
    @State private var saveStatusClearTask: DispatchWorkItem?
    @State private var showSetupOverlay = false
    @State private var hasShownSetupThisSession = false
    @State private var lastGraphSnapshot: GraphSnapshot?
    @State private var lastActiveScreen: AppScreen = .home
    @State private var skipRestoreOnEnter = false
    @State private var tutorialTargets: [TutorialTarget: CGRect] = [:]
    @State private var tutorialRestoreSnapshot: GraphSnapshot?
    @State private var tutorialRestorePresetID: UUID?
    @State private var tutorialWasRunning = false
    @State private var homeTransitionRipple: HomeTransitionRipple?
    @State private var showingAudioSettings = false
    @State private var workspaceReady = false
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppTheme.defaultThemeID

    private var currentPreset: SavedPreset? {
        presetManager.presets.first { $0.id == currentPresetID }
    }

    private var isPresetModified: Bool {
        guard let preset = currentPreset else { return false }
        // While loading, compare the requested graph rather than the old canvas.
        guard let current = audioEngine.pendingGraphLoadRequest?.snapshot.presetComparisonData
                ?? audioEngine.currentPresetComparisonData else { return false }
        return current != preset.graph.presetComparisonData
    }

    @ViewBuilder
    private var audioSettingsOverlay: some View {
        if showingAudioSettings {
            AudioSettingsToolbarStrip(
                trimDB: $audioEngine.processTapInputTrimDB,
                makeupDB: $audioEngine.processTapOutputMakeupDB,
                ceilingEnabled: $audioEngine.processTapOutputCeilingEnabled,
                selectedThemeID: $selectedThemeID,
                isReadOnly: tutorial.isActive
            )
            .fixedSize(horizontal: false, vertical: true)
            .background(ScreenFrameReader { frame in
                audioSettingsOutsideClick.panelFrame = frame
            })
            .contentShape(Rectangle())
            .onTapGesture {}
            .transition(.opacity)
        }
    }

    var body: some View {
        ZStack {
            AppSurfaces.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if activeScreen == .home {
                    HomeView(
                        onBuildFromScratch: { location in
                            beginHomeTransition(at: location)
                        },
                        onStartBasicsTutorial: {
                            startBasicsTutorial()
                        },
                        onStartChainsTutorial: {
                            tutorial.startChains()
                            activeScreen = .beginner
                        },
                        onStartAdvancedTutorial: {
                            startAdvancedTutorialFromHome()
                        },
                        allowBuild: tutorial.allowBuildAction,
                        basicsCompleted: tutorial.basicsCompleted,
                        advancedCompleted: tutorial.advancedCompleted,
                        chainsCompleted: tutorial.chainsCompleted
                    )
                } else {
                    AppTopBar(
                        title: activeScreen == .beginner ? "Build" : "Presets",
                        onBack: {
                            tutorial.handleBackClick()
                            activeScreen = .home
                        },
                        tutorialTarget: .backButton,
                        allowBack: !tutorial.isActive || tutorial.allowBackAction
                    )

                    if activeScreen == .beginner {
                        HeaderView(
                            audioEngine: audioEngine,
                            runtime: chainWorkspace.runtime,
                            tutorial: tutorial,
                            onSave: {
                                saveCurrentPreset(overwrite: true)
                            },
                            onLoad: {
                                showingLoadDialog = true
                            },
                            onSaveAs: {
                                presetNameInput = ""
                                presetNameError = nil
                                showingSaveDialog = true
                            },
                            onUnlinkPreset: {
                                guard !tutorial.isActive, currentPreset != nil else { return }
                                currentPresetID = nil
                                saveStatusText = nil
                            },
                            hasCurrentPreset: currentPreset != nil,
                            presetDisplayName: currentPreset?.name,
                            isPresetModified: isPresetModified,
                            allowSave: !tutorial.isActive || tutorial.step == .buildSave,
                            allowLoad: !tutorial.isActive || tutorial.step == .buildLoad,
                            saveStatusText: $saveStatusText,
                            showingAudioSettings: $showingAudioSettings,
                            settingsOverlay: { audioSettingsOverlay }
                        )
                        // The dropdown extends beyond the header's layout bounds.
                        // Set sibling ordering here, above the divider and canvas.
                        .zIndex(20)
                    }

                    Divider()
                        .background(AppColors.gridLines)

                    Group {
                        switch activeScreen {
                        case .presets:
                            PresetView(
                                audioEngine: audioEngine,
                                presetManager: presetManager,
                                onPresetApplied: { preset in
                                    currentPresetID = preset.id
                                    skipRestoreOnEnter = true
                                    activeScreen = .beginner
                                },
                                tutorial: tutorial
                            )
                        case .beginner:
                            CanvasView(audioEngine: audioEngine, tutorial: tutorial, pluginManager: pluginManager, chainWorkspace: chainWorkspace)
                        case .home:
                            EmptyView()
                        }
                    }
                }
            }
            .frame(minWidth: 1100, minHeight: 700)
            .animation(.easeInOut(duration: 0.2), value: selectedThemeID)
            .coordinateSpace(name: "tutorialRoot")
            .allowsHitTesting(!tutorial.isReviewing)

            if let homeTransitionRipple {
                HomeTransitionRippleView(ripple: homeTransitionRipple)
                    .allowsHitTesting(false)
            }

            if tutorial.isActive {
                TutorialOverlay(
                    step: tutorial.displayedStep,
                    isReviewing: tutorial.isReviewing,
                    targets: tutorialTargets,
                    isSetupReady: audioEngine.setupReadyForCurrentBackend,
                    trayTabsVisited: tutorial.hasVisitedTrayTabs,
                    practiceAppName: tutorial.practiceAppName,
                    onNext: { tutorial.nextButtonTapped() },
                    onSkip: { tutorial.skipTutorial() },
                    onOpenSetup: { showSetupOverlay = true },
                    onEndTutorial: { tutorial.finishTutorial() },
                    onContinueTutorial: { tutorial.continueToNextLesson() },
                    onPreviousInstruction: { tutorial.previousInstruction() },
                    onNextInstruction: { advanceTutorialInstruction() }
                )
                .zIndex(40)
            }

            // OnboardingOverlay must be last to appear above tutorial overlay
            if showSetupOverlay {
                OnboardingOverlay(audioEngine: audioEngine) {
                    showSetupOverlay = false
                    // User will manually click power button to advance from buildPower
                }
                .zIndex(50)
            }

        }
        .onPreferenceChange(TutorialTargetPreferenceKey.self) { value in
            DispatchQueue.main.async {
                guard tutorialTargets != value else { return }
                tutorialTargets = value
            }
        }
        .environment(\.colorScheme, AppTheme.theme(for: selectedThemeID).colorScheme)
        .onAppear {
            guard !hasShownSetupThisSession else { return }
            hasShownSetupThisSession = true
            restoreWorkspace()
            if !audioEngine.setupReadyForCurrentBackend {
                showSetupOverlay = true
            }
            if chainWorkspace.issue == nil {
                tutorial.startIfNeeded(isSetupVisible: showSetupOverlay)
            }
            startNextTutorialWhenReady()
        }
        .onChange(of: activeScreen) { newValue in
            if newValue != .beginner {
                showingAudioSettings = false
            }
            handleScreenChange(to: newValue)
        }
        .onChange(of: showingAudioSettings) { isShowing in
            if isShowing {
                if !tutorial.isActive {
                    audioSettingsOutsideClick.start {
                        withAnimation(.easeOut(duration: 0.16)) {
                            showingAudioSettings = false
                        }
                    }
                }
                tutorial.advanceIf(.buildSettings)
            } else {
                audioSettingsOutsideClick.stop()
            }
        }
        .onDisappear {
            audioSettingsOutsideClick.stop()
            audioEngine.refreshPresetPluginState()
            captureWorkspace()
            chainWorkspace.store.flush()
        }
        .onChange(of: tutorial.isActive) { active in
            guard !tutorial.isAppChainTour else { return }
            // Keep practice state excluded until the canvas has applied the restore.
            chainWorkspace.suspendSaving(for: audioEngine, suspended: active || tutorialRestoreSnapshot != nil)
        }
        .onChange(of: tutorial.step) { newStep in
            if tutorial.isAppChainTour {
                if newStep == .inactive {
                    lastGraphSnapshot = audioEngine.pendingGraphLoadRequest?.snapshot ?? audioEngine.currentGraphSnapshot
                    skipRestoreOnEnter = true
                }
                showingAudioSettings = false
                return
            }
            if newStep == .welcome || newStep == .advancedIntro {
                captureTutorialRestorePoint()

                showingAudioSettings = false
                if newStep == .welcome && audioEngine.isRunning {
                    audioEngine.stop()
                }

                if newStep == .welcome {
                    // Start Basics from a clean, predictable canvas.
                    let resetSnapshot = emptyWorkspaceGraph()

                    lastGraphSnapshot = nil
                    currentPresetID = nil
                    skipRestoreOnEnter = true
                    audioEngine.requestGraphLoad(
                        resetSnapshot,
                        mode: .audioAndVisual,
                        reason: "tutorial reset"
                    )
                } else if newStep == .advancedIntro {
                    ensureTutorialEngineRunningIfPossible()
                }
            } else if newStep == .inactive, let snapshot = tutorialRestoreSnapshot {
                if tutorial.shouldRestoreOnEnd {
                    // Exiting from Welcome has no mounted canvas to apply a load.
                    // Restore audio now and queue only the visual state for later.
                    let needsHeadlessRestore = activeScreen != .beginner
                    if needsHeadlessRestore { audioEngine.applyIndependentGraph(snapshot) }
                    audioEngine.requestGraphLoad(
                        snapshot,
                        mode: needsHeadlessRestore ? .visualOnly : .audioAndVisual,
                        reason: "tutorial restore"
                    )
                    lastGraphSnapshot = snapshot
                    currentPresetID = tutorialRestorePresetID
                    if tutorialWasRunning && !audioEngine.isRunning { audioEngine.start() }
                    if !tutorialWasRunning && (audioEngine.isRunning || audioEngine.isPowerTransitioning) { audioEngine.stop() }
                    if needsHeadlessRestore {
                        tutorialRestoreSnapshot = nil
                        tutorialRestorePresetID = nil
                        chainWorkspace.suspendSaving(for: audioEngine, suspended: false)
                        captureWorkspace()
                    }
                } else {
                    lastGraphSnapshot = audioEngine.currentGraphSnapshot
                }
                showingAudioSettings = false
            } else if newStep.isAudioSettingsExplanation {
                // Keyboard readers can reach these explanations without clicking the gear.
                showingAudioSettings = true
            } else if !newStep.showsAudioSettings && showingAudioSettings {
                withAnimation(.easeOut(duration: 0.16)) {
                    showingAudioSettings = false
                }
            }
        }
        .onChange(of: audioEngine.pendingGraphLoadRequest == nil) { didApply in
            guard didApply, !tutorial.isActive else { return }
            if tutorialRestoreSnapshot != nil {
                tutorialRestoreSnapshot = nil
                tutorialRestorePresetID = nil
                chainWorkspace.suspendSaving(for: audioEngine, suspended: false)
                captureWorkspace()
            }
            startNextTutorialWhenReady()
        }
        .onChange(of: tutorial.pendingNextLesson) { _ in
            // Let the inactive-step observer queue restoration before checking readiness.
            DispatchQueue.main.async { startNextTutorialWhenReady() }
        }
        .onChange(of: chainWorkspace.issue) { issue in
            if issue == nil { startNextTutorialWhenReady() }
        }
        .onChange(of: showSetupOverlay) { isVisible in
            if !isVisible {
                if chainWorkspace.issue == nil {
                    tutorial.startIfNeeded(isSetupVisible: false)
                }
                if tutorial.step == .advancedIntro {
                    ensureTutorialEngineRunningIfPossible()
                }
                startNextTutorialWhenReady()
            }
        }
        .animation(.easeOut(duration: 0.7), value: showSetupOverlay)
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            _ = audioEngine.refreshSetupStatus()
            audioEngine.refreshPresetPluginState()
            captureWorkspace()
        }
        .onReceive(audioEngine.$graphSnapshotRevision) { _ in captureWorkspace() }
        .onChange(of: currentPresetID) { _ in captureWorkspace() }
        .onChange(of: audioEngine.processingEnabled) { _ in captureWorkspace() }
        .onChange(of: audioEngine.processTapInputTrimDB) { _ in captureWorkspace() }
        .onChange(of: audioEngine.processTapOutputMakeupDB) { _ in captureWorkspace() }
        .onChange(of: audioEngine.processTapOutputCeilingEnabled) { _ in captureWorkspace() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            audioEngine.refreshPresetPluginState()
            captureWorkspace()
            chainWorkspace.store.flush()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sonexisEditorWillHide)) { _ in
            audioEngine.refreshPresetPluginState()
            captureWorkspace()
            chainWorkspace.store.flush()
        }
        .sheet(isPresented: $showingSaveDialog) {
            SavePresetDialog(
                presetName: $presetNameInput,
                errorMessage: presetNameError,
                onSave: {
                    savePresetAs()
                },
                onCancel: {
                    presetNameError = nil
                    showingSaveDialog = false
                }
            )
        }
        .onChange(of: presetNameInput) { _ in
            presetNameError = nil
        }
        .sheet(isPresented: $showingLoadDialog) {
            LoadPresetDialog(
                presetManager: presetManager,
                tutorialStep: tutorial.step,
                onApply: { preset in
                    audioEngine.requestGraphLoad(
                        preset.graph,
                        mode: .audioAndVisual,
                        reason: "load preset dialog"
                    )
                    currentPresetID = preset.id
                    if tutorial.step == .buildLoad {
                        tutorial.advance()
                    }
                    showingLoadDialog = false
                },
                onCancel: {
                    showingLoadDialog = false
                }
            )
        }
        .onChange(of: showingLoadDialog) { isShowing in
            if !isShowing, tutorial.step == .buildCloseLoad {
                tutorial.advance()
            }
        }
        .sonexisDialog("Preset Storage",
            message: presetManager.saveError ?? "",
            tone: .error,
            isPresented: Binding(
            get: { presetManager.saveError != nil && !showingSaveDialog && !showingLoadDialog },
            set: { if !$0 { presetManager.saveError = nil } }
            ),
            actions: [SonexisDialogAction("OK", role: .primary) { presetManager.saveError = nil }]
        )

    }

    private func emptyWorkspaceGraph() -> GraphSnapshot {
        GraphSnapshot(graphMode: .single, wiringMode: .automatic, nodes: [], connections: [],
            startNodeID: UUID(), endNodeID: UUID(), leftStartNodeID: UUID(), leftEndNodeID: UUID(),
            rightStartNodeID: UUID(), rightEndNodeID: UUID())
    }

    private func restoreWorkspace() {
        if let graph = audioEngine.pendingGraphLoadRequest?.snapshot ?? audioEngine.currentGraphSnapshot {
            lastGraphSnapshot = graph
            skipRestoreOnEnter = true
        }
        workspaceReady = true
    }

    private func captureWorkspace() {
        guard workspaceReady, !tutorial.isActive, tutorialRestoreSnapshot == nil else { return }
        chainWorkspace.capture()
    }

    private func savePresetAs() {
        audioEngine.refreshPresetPluginState()
        guard !presetNameInput.isEmpty else { return }

        guard let graph = audioEngine.currentGraphSnapshot else {
            // No-op: missing graph snapshot.
            return
        }
        guard let preset = presetManager.savePreset(name: presetNameInput, graph: graph) else {
            // Keep validation/storage feedback inside Save Preset so the name
            // can be corrected without opening a second modal dialog.
            presetNameError = presetManager.saveError ?? "The preset could not be saved."
            presetManager.saveError = nil
            showSaveStatus("Not saved — try again")
            return
        }
        presetNameError = nil
        showingSaveDialog = false
        currentPresetID = preset.id
        showSaveStatus("Saved at \(formattedTime())")
        tutorial.advanceIf(.buildSave)
        // Save succeeded.
    }

    private func captureTutorialRestorePoint() {
        guard tutorialRestoreSnapshot == nil else { return }
        // Capture before mounting the advanced canvas: its onAppear seeds demo nodes.
        audioEngine.refreshPresetPluginState()
        chainWorkspace.capture()
        chainWorkspace.store.flush()
        tutorialRestoreSnapshot = audioEngine.pendingGraphLoadRequest?.snapshot
            ?? audioEngine.currentGraphSnapshot ?? emptyWorkspaceGraph()
        tutorialRestorePresetID = currentPresetID
        tutorialWasRunning = audioEngine.isRunning
        chainWorkspace.suspendSaving(for: audioEngine, suspended: true)
    }

    private func startBasicsTutorial() {
        captureTutorialRestorePoint()
        tutorial.startBasics()
    }

    private func advanceTutorialInstruction() {
        let entersWorkspace = tutorial.step == .homeBuild && !tutorial.isReviewing
        tutorial.nextInstruction()
        if entersWorkspace && tutorial.step == .buildPower {
            skipRestoreOnEnter = true
            activeScreen = .beginner
        }
    }

    private func startNextTutorialWhenReady() {
        guard !tutorial.isActive, let next = tutorial.pendingNextLesson,
              tutorialRestoreSnapshot == nil,
              audioEngine.pendingGraphLoadRequest == nil,
              !showSetupOverlay, chainWorkspace.issue == nil else { return }
        if next == .manualWiring {
            captureTutorialRestorePoint()
        }
        tutorial.startPendingLesson()
        if tutorial.isActive {
            skipRestoreOnEnter = true
            activeScreen = .beginner
        }
    }

    private func startAdvancedTutorialFromHome() {
        captureTutorialRestorePoint()
        tutorial.startAdvanced()
        skipRestoreOnEnter = true
        activeScreen = .beginner
    }

    private func ensureTutorialEngineRunningIfPossible() {
        guard tutorial.isActive else { return }
        guard audioEngine.setupReadyForCurrentBackend else {
            showSetupOverlay = true
            return
        }
        if !audioEngine.isRunning {
            audioEngine.start()
        }
    }

    private func handleScreenChange(to newScreen: AppScreen) {
        if lastActiveScreen == .beginner {
            lastGraphSnapshot = audioEngine.currentGraphSnapshot
        }

        if newScreen == .beginner {
            if skipRestoreOnEnter {
                skipRestoreOnEnter = false
            } else if let snapshot = lastGraphSnapshot {
                audioEngine.requestGraphLoad(
                    snapshot,
                    mode: .visualOnly,
                    reason: "screen navigation"
                )
            } else if audioEngine.currentGraphSnapshot == nil && audioEngine.pendingGraphLoadRequest == nil {
                audioEngine.requestGraphLoad(emptyWorkspaceGraph(), reason: "new workspace")
            }
        }

        lastActiveScreen = newScreen
    }

    private func beginHomeTransition(at location: CGPoint) {
        guard activeScreen == .home, homeTransitionRipple == nil else { return }

        tutorial.handleBuildClick()
        homeTransitionRipple = HomeTransitionRipple(origin: location)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                activeScreen = .beginner
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            homeTransitionRipple = nil
        }
    }

    private func saveCurrentPreset(overwrite: Bool = false) {
        audioEngine.refreshPresetPluginState()
        guard let graph = audioEngine.currentGraphSnapshot else {
            // No-op: missing graph snapshot.
            return
        }

        if overwrite, let presetID = currentPresetID {
            guard presetManager.updatePreset(id: presetID, graph: graph) else {
                showSaveStatus("Not saved — try again")
                return
            }
            showSaveStatus("Saved at \(formattedTime())")
            tutorial.advanceIf(.buildSave)
            // Update succeeded.
        } else {
            presetNameInput = ""
            presetNameError = nil
            showingSaveDialog = true
        }
    }

    private func showSaveStatus(_ message: String) {
        saveStatusClearTask?.cancel()
        saveStatusText = message
        let task = DispatchWorkItem {
            saveStatusText = nil
        }
        saveStatusClearTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
    }

    private func formattedTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }
}

enum AppScreen {
    case home
    case presets
    case beginner
}

private struct HomeTransitionRipple: Equatable {
    let id = UUID()
    let origin: CGPoint
}

private struct HomeTransitionRippleView: View {
    let ripple: HomeTransitionRipple
    @State private var backdropVisible = false
    @State private var expanded = false
    @State private var fading = false
    private let expansionDuration: TimeInterval = 0.30
    private let fadeDelay: TimeInterval = 0.20
    private let fadeDuration: TimeInterval = 0.24

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let diameter = transitionDiameter(for: size)

            ZStack {
                AppColors.deepBlack
                    .opacity(fading ? 0 : (backdropVisible ? 0.34 : 0))
                    .ignoresSafeArea()

                Circle()
                    .fill(AppColors.midPurple.opacity(expanded ? 0.48 : 0.72))
                    .overlay(
                        Circle()
                            .stroke(AppColors.neonCyan.opacity(fading ? 0 : (expanded ? 0.14 : 0.8)), lineWidth: expanded ? 1 : 2)
                    )
                    .frame(width: expanded ? diameter : 18, height: expanded ? diameter : 18)
                    .shadow(color: AppColors.neonCyan.opacity(fading ? 0 : (expanded ? 0.2 : 0.9)), radius: expanded ? 28 : 10)
                    .opacity(fading ? 0 : 1)
                    .position(ripple.origin)
                    .ignoresSafeArea()
            }
            .onAppear {
                    withAnimation(.easeOut(duration: 0.12)) {
                        backdropVisible = true
                    }
                    withAnimation(.timingCurve(0.16, 0.84, 0.24, 1.0, duration: expansionDuration)) {
                        expanded = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + fadeDelay) {
                        withAnimation(.easeOut(duration: fadeDuration)) {
                            fading = true
                        }
                    }
            }
        }
    }

    private func transitionDiameter(for size: CGSize) -> CGFloat {
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height)
        ]
        let maxDistance = corners.map { corner in
            hypot(corner.x - ripple.origin.x, corner.y - ripple.origin.y)
        }.max() ?? max(size.width, size.height)
        return maxDistance * 2.2
    }
}
