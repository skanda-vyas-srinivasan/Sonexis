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
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var presetManager = PresetManager()
    @StateObject private var pluginManager = PluginManager()
    @StateObject private var tutorial = TutorialController()
    @StateObject private var audioSettingsOutsideClick = AudioSettingsOutsideClickCoordinator()
    @State private var activeScreen: AppScreen = .home
    @State private var showingSaveDialog = false
    @State private var showingLoadDialog = false
    @State private var presetNameInput = ""
    @State private var currentPresetID: UUID?
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
    @State private var homeTransitionRipple: HomeTransitionRipple?
    @State private var showingAudioSettings = false
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppTheme.defaultThemeID

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
                        onStartAdvancedTutorial: {
                            startAdvancedTutorialFromHome()
                        },
                        allowBuild: tutorial.allowBuildAction,
                        basicsCompleted: tutorial.basicsCompleted,
                        advancedCompleted: tutorial.advancedCompleted
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
                            tutorial: tutorial,
                            onSave: {
                                saveCurrentPreset(overwrite: true)
                            },
                            onLoad: {
                                showingLoadDialog = true
                            },
                            onSaveAs: {
                                presetNameInput = ""
                                showingSaveDialog = true
                            },
                            currentPresetName: currentPreset?.name,
                            hasCurrentPreset: currentPreset != nil,
                            allowSave: !tutorial.isActive || tutorial.step == .buildSave,
                            allowLoad: !tutorial.isActive || tutorial.step == .buildLoad,
                            saveStatusText: $saveStatusText,
                            showingAudioSettings: $showingAudioSettings
                        )
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
                            CanvasView(audioEngine: audioEngine, tutorial: tutorial, pluginManager: pluginManager)
                        case .home:
                            EmptyView()
                        }
                    }
                }
            }
            .frame(minWidth: 800, minHeight: 700)
            .animation(.easeInOut(duration: 0.2), value: selectedThemeID)
            .coordinateSpace(name: "tutorialRoot")
            .onPreferenceChange(TutorialTargetPreferenceKey.self) { value in
                DispatchQueue.main.async {
                    guard tutorialTargets != value else { return }
                    tutorialTargets = value
                }
            }

            if let homeTransitionRipple {
                HomeTransitionRippleView(ripple: homeTransitionRipple)
                    .allowsHitTesting(false)
            }

            if activeScreen == .beginner && showingAudioSettings {
                AudioSettingsRootOverlay(
                    trimDB: $audioEngine.processTapInputTrimDB,
                    makeupDB: $audioEngine.processTapOutputMakeupDB,
                    ceilingEnabled: $audioEngine.processTapOutputCeilingEnabled,
                    selectedThemeID: $selectedThemeID,
                    isReadOnly: tutorial.step == .buildSettingsExplain,
                    onPanelFrameChange: { frame in
                        audioSettingsOutsideClick.panelFrame = frame
                    }
                )
                .transition(.opacity)
                .zIndex(30)
            }

            if tutorial.isActive {
                TutorialOverlay(
                    step: tutorial.step,
                    targets: tutorialTargets,
                    isSetupReady: audioEngine.setupReadyForCurrentBackend,
                    trayTabsVisited: tutorial.hasVisitedTrayTabs,
                    onNext: { tutorial.advance() },
                    onSkip: { tutorial.skipTutorial() },
                    onOpenSetup: { showSetupOverlay = true },
                    onEndTutorial: { tutorial.finishTutorial() },
                    onContinueAdvanced: {
                        tutorial.continueToAdvanced()
                    }
                )
            }

            // OnboardingOverlay must be last to appear above tutorial overlay
            if showSetupOverlay {
                OnboardingOverlay(audioEngine: audioEngine) {
                    showSetupOverlay = false
                    // User will manually click power button to advance from buildPower
                }
            }

        }
        .environment(\.colorScheme, AppTheme.theme(for: selectedThemeID).colorScheme)
        .onAppear {
            guard !hasShownSetupThisSession else { return }
            hasShownSetupThisSession = true
            if !audioEngine.setupReadyForCurrentBackend {
                showSetupOverlay = true
            }
            tutorial.startIfNeeded(isSetupVisible: showSetupOverlay)
        }
        .onChange(of: activeScreen) { newValue in
            if newValue != .beginner {
                showingAudioSettings = false
            }
            handleScreenChange(to: newValue)
        }
        .onChange(of: showingAudioSettings) { isShowing in
            if isShowing {
                audioSettingsOutsideClick.start {
                    withAnimation(.easeOut(duration: 0.16)) {
                        showingAudioSettings = false
                    }
                }
                tutorial.advanceIf(.buildSettings)
            } else {
                audioSettingsOutsideClick.stop()
            }
        }
        .onDisappear {
            audioSettingsOutsideClick.stop()
        }
        .onChange(of: tutorial.step) { newStep in
            if newStep == .welcome || newStep == .advancedIntro {
                // Save current state for restoration when tutorial ends
                if tutorialRestoreSnapshot == nil {
                    tutorialRestoreSnapshot = audioEngine.currentGraphSnapshot
                    tutorialRestorePresetID = currentPresetID
                }

                showingAudioSettings = false
                if newStep == .welcome && audioEngine.isRunning {
                    audioEngine.stop()
                }

                if newStep == .welcome {
                    // Start Basics from a clean, predictable canvas.
                    let resetSnapshot = GraphSnapshot(
                        graphMode: .single,
                        wiringMode: .automatic,
                        autoConnectEnd: false,
                        nodes: [],
                        connections: [],
                        autoGainOverrides: [],
                        startNodeID: UUID(),
                        endNodeID: UUID(),
                        leftStartNodeID: UUID(),
                        leftEndNodeID: UUID(),
                        rightStartNodeID: UUID(),
                        rightEndNodeID: UUID(),
                        hasNodeParameters: true
                    )

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
                    audioEngine.requestGraphLoad(
                        snapshot,
                        mode: .audioAndVisual,
                        reason: "tutorial restore"
                    )
                    lastGraphSnapshot = snapshot
                    currentPresetID = tutorialRestorePresetID
                } else {
                    lastGraphSnapshot = audioEngine.currentGraphSnapshot
                }
                tutorialRestoreSnapshot = nil
                tutorialRestorePresetID = nil
                showingAudioSettings = false
            } else if newStep != .buildSettings && newStep != .buildSettingsExplain && showingAudioSettings {
                withAnimation(.easeOut(duration: 0.16)) {
                    showingAudioSettings = false
                }
            }
        }
        .onChange(of: showSetupOverlay) { isVisible in
            if !isVisible {
                tutorial.startIfNeeded(isSetupVisible: false)
                if tutorial.step == .advancedIntro {
                    ensureTutorialEngineRunningIfPossible()
                }
            }
        }
        .animation(.easeOut(duration: 0.7), value: showSetupOverlay)
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            _ = audioEngine.refreshSetupStatus()
        }
        .sheet(isPresented: $showingSaveDialog) {
            SavePresetDialog(
                presetName: $presetNameInput,
                onSave: {
                    savePresetAs()
                    showingSaveDialog = false
                },
                onCancel: {
                    showingSaveDialog = false
                }
            )
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
        .alert("Preset Save Failed", isPresented: Binding(
            get: { presetManager.saveError != nil },
            set: { if !$0 { presetManager.saveError = nil } }
        )) {
            Button("OK") { presetManager.saveError = nil }
        } message: {
            Text(presetManager.saveError ?? "")
        }
    }

    private var currentPreset: SavedPreset? {
        guard let currentPresetID else { return nil }
        return presetManager.presets.first { $0.id == currentPresetID }
    }

    private func savePresetAs() {
        guard !presetNameInput.isEmpty else { return }

        guard let graph = audioEngine.currentGraphSnapshot else {
            // No-op: missing graph snapshot.
            return
        }
        let preset = presetManager.savePreset(name: presetNameInput, graph: graph)
        currentPresetID = preset.id
        showSaveStatus("Saved at \(formattedTime())")
        tutorial.advanceIf(.buildSave)
        // Save succeeded.
    }

    private func startBasicsTutorial() {
        tutorial.startBasics()
    }

    private func startAdvancedTutorialFromHome() {
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
        guard let graph = audioEngine.currentGraphSnapshot else {
            // No-op: missing graph snapshot.
            return
        }

        if overwrite, let presetID = currentPreset?.id {
            presetManager.updatePreset(id: presetID, graph: graph)
            showSaveStatus("Saved at \(formattedTime())")
            tutorial.advanceIf(.buildSave)
            // Update succeeded.
        } else {
            presetNameInput = ""
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

private struct AudioSettingsRootOverlay: View {
    @Binding var trimDB: Double
    @Binding var makeupDB: Double
    @Binding var ceilingEnabled: Bool
    @Binding var selectedThemeID: String
    let isReadOnly: Bool
    let onPanelFrameChange: (CGRect) -> Void

    private let topPadding: CGFloat = 122

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                AudioSettingsFloatingStrip(
                    trimDB: $trimDB,
                    makeupDB: $makeupDB,
                    ceilingEnabled: $ceilingEnabled,
                    selectedThemeID: $selectedThemeID,
                    isReadOnly: isReadOnly
                )
                .frame(width: min(640, max(620, proxy.size.width - 32)))
                .background(
                    ScreenFrameReader(onChange: onPanelFrameChange)
                )
                .contentShape(Rectangle())
                .onTapGesture {}
                .padding(.top, topPadding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .ignoresSafeArea()
    }
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
