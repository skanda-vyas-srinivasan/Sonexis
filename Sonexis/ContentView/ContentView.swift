import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var presetManager = PresetManager()
    @StateObject private var pluginManager = PluginManager()
    @StateObject private var tutorial = TutorialController()
    @State private var activeScreen: AppScreen = .home
    @State private var showingSaveDialog = false
    @State private var showingLoadDialog = false
    @State private var presetNameInput = ""
    @State private var currentPresetID: UUID?
    @State private var saveStatusText: String?
    @State private var saveStatusClearTask: DispatchWorkItem?
    @State private var showGlitch = false
    @State private var showSetupOverlay = false
    @State private var hasShownSetupThisSession = false
    @State private var lastGraphSnapshot: GraphSnapshot?
    @State private var lastActiveScreen: AppScreen = .home
    @State private var skipRestoreOnEnter = false
    @State private var tutorialTargets: [TutorialTarget: CGRect] = [:]
    @State private var tutorialRestoreSnapshot: GraphSnapshot?
    @State private var tutorialRestorePresetID: UUID?
    @State private var showEngineStoppedAlert = false
    @State private var hasEngineBeenOnDuringTutorial = false
    @State private var homeTransitionRipple: HomeTransitionRipple?
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppTheme.classic.rawValue

    var body: some View {
        ZStack {
            AppGradients.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if activeScreen == .home {
                    HomeView(
                        onBuildFromScratch: { location in
                            beginHomeTransition(at: location)
                        },
                        onTutorial: { tutorial.startFromHelp() },
                        allowBuild: tutorial.allowBuildAction
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
                            allowSave: !tutorial.isActive || tutorial.step == .buildSave,
                            allowLoad: !tutorial.isActive || tutorial.step == .buildLoad,
                            saveStatusText: $saveStatusText
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

            if showGlitch {
                GlitchOverlay {
                    showGlitch = false
                }
            }

            if let homeTransitionRipple {
                HomeTransitionRippleView(ripple: homeTransitionRipple)
                    .allowsHitTesting(false)
            }

            if tutorial.isActive {
                TutorialOverlay(
                    step: tutorial.step,
                    targets: tutorialTargets,
                    isSetupReady: audioEngine.setupReadyForCurrentBackend,
                    usesProcessTapBackend: audioEngine.isProcessTapBackendEnabled,
                    trayTabsVisited: tutorial.hasVisitedTrayTabs,
                    onNext: { tutorial.advance() },
                    onSkip: { tutorial.endTutorial() },
                    onOpenSetup: { showSetupOverlay = true }
                )
            }

            // OnboardingOverlay must be last to appear above tutorial overlay
            if showSetupOverlay {
                OnboardingOverlay(audioEngine: audioEngine) {
                    showSetupOverlay = false
                    // User will manually click power button to advance from buildPower
                }
            }

            // Engine stopped alert - must be above everything
            if showEngineStoppedAlert {
                EngineStoppedAlert(onDismiss: {
                    showEngineStoppedAlert = false
                    hasEngineBeenOnDuringTutorial = false
                    tutorial.endTutorial()
                })
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
            if !(lastActiveScreen == .home && newValue == .beginner) {
                showGlitch = true
            }
            handleScreenChange(to: newValue)
        }
        .onChange(of: tutorial.step) { newStep in
            if newStep == .welcome {
                // Save current state for restoration when tutorial ends
                if tutorialRestoreSnapshot == nil {
                    tutorialRestoreSnapshot = audioEngine.currentGraphSnapshot
                    tutorialRestorePresetID = currentPresetID
                }

                // Reset engine tracking for new tutorial
                hasEngineBeenOnDuringTutorial = false

                // Start the tutorial from a clean, predictable state:
                // - Empty canvas (no nodes/connections)
                // - Stereo mode (not dual-mono)
                // - Automatic wiring (not manual)
                // - Auto-connect End OFF
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

                // Clear any previous graph state
                lastGraphSnapshot = nil
                currentPresetID = nil
                skipRestoreOnEnter = true
                audioEngine.requestGraphLoad(
                    resetSnapshot,
                    mode: .audioAndVisual,
                    reason: "tutorial reset"
                )
            } else if newStep == .inactive, let snapshot = tutorialRestoreSnapshot {
                // Restore the user's graph when the tutorial ends.
                audioEngine.requestGraphLoad(
                    snapshot,
                    mode: .audioAndVisual,
                    reason: "tutorial restore"
                )
                lastGraphSnapshot = snapshot
                currentPresetID = tutorialRestorePresetID
                tutorialRestoreSnapshot = nil
                tutorialRestorePresetID = nil
                hasEngineBeenOnDuringTutorial = false
            }
        }
        .onChange(of: showSetupOverlay) { isVisible in
            if !isVisible {
                tutorial.startIfNeeded(isSetupVisible: false)
            }
        }
        .onChange(of: audioEngine.isRunning) { isRunning in
            // Track if engine has been on during tutorial
            if tutorial.isActive && isRunning && tutorial.step != .buildPower {
                hasEngineBeenOnDuringTutorial = true
            }

            // If engine stops unexpectedly after being on during tutorial
            if tutorial.isActive && !isRunning && hasEngineBeenOnDuringTutorial {
                showEngineStoppedAlert = true
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
                    } else {
                        showingLoadDialog = false
                    }
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

        if overwrite, let presetID = currentPresetID {
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
                    .fill(
                        RadialGradient(
                            colors: [
                                AppColors.neonCyan.opacity(expanded ? 0.18 : 0.55),
                                AppColors.midPurple.opacity(expanded ? 0.42 : 0.72),
                                AppColors.deepBlack.opacity(expanded ? 0.50 : 0.82)
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: max(40, diameter * 0.5)
                        )
                    )
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
