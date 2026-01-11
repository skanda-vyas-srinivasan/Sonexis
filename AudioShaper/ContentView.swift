import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var presetManager = PresetManager()
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

    var body: some View {
        ZStack {
            AppGradients.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if activeScreen == .home {
                    HomeView(
                        onBuildFromScratch: {
                            tutorial.handleBuildClick()
                            activeScreen = .beginner
                        },
                        onApplyPresets: {
                            tutorial.handlePresetsClick()
                            activeScreen = .presets
                        },
                        onTutorial: { tutorial.startFromHelp() },
                        allowBuild: tutorial.allowBuildAction,
                        allowPresets: tutorial.allowPresetsAction
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
                            BeginnerView(audioEngine: audioEngine, tutorial: tutorial)
                        case .home:
                            EmptyView()
                        }
                    }
                }
            }
            .frame(minWidth: 800, minHeight: 700)
            .coordinateSpace(name: "tutorialRoot")
            .onPreferenceChange(TutorialTargetPreferenceKey.self) { value in
                tutorialTargets = value
            }

            if showGlitch {
                GlitchOverlay {
                    showGlitch = false
                }
            }

            if showSetupOverlay {
                OnboardingOverlay(audioEngine: audioEngine) {
                    showSetupOverlay = false
                }
            }

            if tutorial.isActive {
                TutorialOverlay(
                    step: tutorial.step,
                    targets: tutorialTargets,
                    onNext: { tutorial.advance() },
                    onSkip: { tutorial.endTutorial() }
                )
            }
        }
        .onAppear {
            guard !hasShownSetupThisSession else { return }
            hasShownSetupThisSession = true
            let ready = audioEngine.refreshSetupStatus()
            if !ready {
                showSetupOverlay = true
            }
            tutorial.startIfNeeded(isSetupVisible: showSetupOverlay)
        }
        .onChange(of: activeScreen) { newValue in
            showGlitch = true
            handleScreenChange(to: newValue)
        }
        .onChange(of: tutorial.step) { newStep in
            if newStep == .welcome {
                // Save current state for restoration when tutorial ends
                if tutorialRestoreSnapshot == nil {
                    tutorialRestoreSnapshot = audioEngine.currentGraphSnapshot
                    tutorialRestorePresetID = currentPresetID
                }

                // Start the tutorial from a clean, predictable state:
                // - Empty canvas (no nodes/connections)
                // - Stereo mode (not dual-mono)
                // - Automatic wiring (not manual)
                let resetSnapshot = GraphSnapshot(
                    graphMode: .single,
                    wiringMode: .automatic,
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
                audioEngine.requestGraphLoad(resetSnapshot)
            } else if newStep == .inactive, let snapshot = tutorialRestoreSnapshot {
                // Restore the user's graph when the tutorial ends.
                audioEngine.requestGraphLoad(snapshot)
                lastGraphSnapshot = snapshot
                currentPresetID = tutorialRestorePresetID
                tutorialRestoreSnapshot = nil
                tutorialRestorePresetID = nil
            }
        }
        .onChange(of: showSetupOverlay) { isVisible in
            if !isVisible {
                tutorial.startIfNeeded(isSetupVisible: false)
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
                    audioEngine.requestGraphLoad(preset.graph)
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
                audioEngine.requestGraphLoad(snapshot)
            }
        }

        lastActiveScreen = newScreen
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

private struct OnboardingOverlay: View {
    let audioEngine: AudioEngine
    let onDone: () -> Void
    @State private var inputDeviceName: String?
    @State private var outputDeviceName: String?
    @State private var hasVerified = false
    @State private var showSkipConfirm = false
    @State private var backdropVisible = false
    @State private var animateIn = false
    @State private var flowPulse = false

    var body: some View {
        let inputIsBlackHole = inputDeviceName?.localizedCaseInsensitiveContains("BlackHole") == true
        let outputIsBlackHole = outputDeviceName?.localizedCaseInsensitiveContains("BlackHole") == true
        let ready = inputIsBlackHole && outputIsBlackHole
        let blackHoleInstalled = audioEngine.outputDevices.contains { $0.name.localizedCaseInsensitiveContains("BlackHole") }

        ZStack {
            Color.black.opacity(backdropVisible ? 0.6 : 0.0)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        showSkipConfirm = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(6)
                            .background(AppColors.deepBlack.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Hold On! Your input and output aren’t set up yet.")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Text("Setup checklist")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 8) {
                        setupStepCard(
                            completeText: "BlackHole is installed",
                            incompleteText: "Install BlackHole",
                            isComplete: blackHoleInstalled,
                            linkText: "Install",
                            linkURL: "https://existential.audio/blackhole/"
                        )
                        setupStepCard(
                            completeText: "System sound input is set to BlackHole",
                            incompleteText: "Set system sound input to BlackHole",
                            isComplete: inputIsBlackHole
                        )
                        setupStepCard(
                            completeText: "System sound output is set to BlackHole",
                            incompleteText: "Set system sound output to BlackHole",
                            isComplete: outputIsBlackHole
                        )
                    }
                }

                signalFlowView(inputReady: inputIsBlackHole, outputReady: outputIsBlackHole)

                VStack(spacing: 10) {
                    Text("Current devices")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        deviceStatusCard(title: "Input", name: inputDeviceName, ok: inputIsBlackHole)
                        deviceStatusCard(title: "Output", name: outputDeviceName, ok: outputIsBlackHole)
                    }
                }

                VStack(spacing: 8) {
                    Button("Open Sound Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.neonPink)

                    Button("Verify Setup") {
                        inputDeviceName = audioEngine.systemDefaultInputDeviceName()
                        outputDeviceName = audioEngine.systemDefaultOutputDeviceName()
                        _ = audioEngine.refreshSetupStatus()
                        hasVerified = true
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.neonCyan)

                    Button("Start") {
                        onDone()
                    }
                    .disabled(!ready)
                    .buttonStyle(.borderedProminent)
                    .tint(ready ? AppColors.neonCyan : AppColors.textSecondary)
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.midPurple.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppColors.neonCyan.opacity(0.6), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 420)
            .shadow(color: Color.black.opacity(0.3), radius: 12, y: 6)
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : -30)
        }
        .overlay(
            Group {
                if showSkipConfirm {
                    SkipSetupConfirm(
                        onCancel: { showSkipConfirm = false },
                        onSkip: {
                            showSkipConfirm = false
                            onDone()
                        }
                    )
                    .transition(.opacity)
                }
            }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            inputDeviceName = audioEngine.systemDefaultInputDeviceName()
            outputDeviceName = audioEngine.systemDefaultOutputDeviceName()
            _ = audioEngine.refreshSetupStatus()
            hasVerified = true
            animateIn = false
            withAnimation(.easeInOut(duration: 0.9)) {
                backdropVisible = true
            }
            withAnimation(.easeOut(duration: 0.7)) {
                animateIn = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                flowPulse = true
            }
        }
        .background(OverlayKeyCapture { event in
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "r" else { return }
            animateIn = false
            backdropVisible = false
            flowPulse = false
            withAnimation(.easeInOut(duration: 0.9)) {
                backdropVisible = true
            }
            withAnimation(.easeOut(duration: 0.7)) {
                animateIn = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                flowPulse = true
            }
        })
    }

    private func setupStepCard(
        completeText: String,
        incompleteText: String,
        isComplete: Bool,
        linkText: String? = nil,
        linkURL: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Text(isComplete ? completeText : incompleteText)
                .font(AppTypography.caption)
                .foregroundColor(isComplete ? AppColors.neonCyan : AppColors.neonPink)
                .lineLimit(1)

            if !isComplete, let linkText, let linkURL {
                Button(linkText) {
                    if let url = URL(string: linkURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.neonCyan)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.deepBlack.opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke((isComplete ? AppColors.neonCyan : AppColors.neonPink).opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func deviceStatusCard(title: String, name: String?, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(ok ? AppColors.neonCyan : AppColors.neonPink)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
            }
            Text(name ?? "Not detected")
                .font(AppTypography.body)
                .foregroundColor(ok ? AppColors.textPrimary : AppColors.neonPink)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.deepBlack.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((ok ? AppColors.neonCyan : AppColors.neonPink).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func signalFlowView(inputReady: Bool, outputReady: Bool) -> some View {
        let activeColor = AppColors.neonCyan
        let inactiveColor = AppColors.textMuted.opacity(0.5)
        let lineOpacity = flowPulse ? 0.9 : 0.6

        return HStack(spacing: 10) {
            flowNode(title: "Input", active: inputReady)
            flowLine(active: inputReady, opacity: lineOpacity)
            flowNode(title: "AudioShaper", active: inputReady && outputReady)
            flowLine(active: outputReady, opacity: lineOpacity)
            flowNode(title: "Output", active: outputReady)
        }
        .padding(.vertical, 6)
        .foregroundColor(inputReady ? activeColor : inactiveColor)
    }

    private func flowNode(title: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(active ? AppColors.neonCyan : AppColors.textMuted.opacity(0.4))
                .frame(width: 10, height: 10)
                .shadow(color: active ? AppColors.neonCyan.opacity(0.6) : Color.clear, radius: 6)
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(active ? AppColors.textSecondary : AppColors.textMuted)
        }
    }

    private func flowLine(active: Bool, opacity: Double) -> some View {
        Capsule()
            .fill(active ? AppColors.neonCyan.opacity(opacity) : AppColors.textMuted.opacity(0.3))
            .frame(width: 40, height: 2)
            .shadow(color: active ? AppColors.neonCyan.opacity(0.5) : Color.clear, radius: 6)
    }
}

private struct SkipSetupConfirm: View {
    let onCancel: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Skip setup?")
                .font(AppTypography.heading)
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("AudioShaper won’t be functional without setting Input and Output to BlackHole. You won’t hear sound until you set it up.")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 10) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .tint(AppColors.textSecondary)

                Button("Skip") {
                    onSkip()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.neonPink)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.midPurple.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.neonPink.opacity(0.6), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 6)
        .frame(maxWidth: 420)
    }
}

struct LoadPresetDialog: View {
    @ObservedObject var presetManager: PresetManager
    let tutorialStep: TutorialStep
    let onApply: (SavedPreset) -> Void
    let onCancel: () -> Void
    @State private var searchText = ""

    var body: some View {
        let filteredPresets = presetManager.presets.filter { preset in
            searchText.isEmpty || preset.name.lowercased().contains(searchText.lowercased())
        }

        VStack(spacing: 16) {
            if tutorialStep == .buildLoad || tutorialStep == .buildCloseLoad {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tutorialStep == .buildLoad ? "Load a preset" : "Close this window")
                        .font(AppTypography.heading)
                        .foregroundColor(AppColors.textPrimary)
                    Text(tutorialStep == .buildLoad ? "Pick a preset and press Apply." : "Press Cancel to continue.")
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.darkPurple.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.neonCyan.opacity(0.6), lineWidth: 1)
                        )
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Load Preset")
                .font(AppTypography.heading)
                .foregroundColor(AppColors.textPrimary)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.neonCyan)
                TextField("Search presets...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(10)
            .background(AppColors.midPurple)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.neonCyan.opacity(0.6), lineWidth: 1)
            )
            .cornerRadius(10)

            if filteredPresets.isEmpty {
                Text("No presets found")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(filteredPresets) { preset in
                            Button {
                                onApply(preset)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.name)
                                            .font(AppTypography.heading)
                                            .foregroundColor(AppColors.textPrimary)
                                        Text("\(preset.graph.nodes.count) effects")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.neonCyan)
                                    }
                                    Spacer()
                                    Text("Apply")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                }
                                .padding()
                                .background(AppColors.darkPurple)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(AppColors.gridLines, lineWidth: 1)
                                )
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .disabled(tutorialStep == .buildCloseLoad)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 320)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 420, height: 520)
        .background(AppColors.midPurple)
        .cornerRadius(16)
    }
}

enum AppScreen {
    case home
    case presets
    case beginner
}

struct HomeView: View {
    let onBuildFromScratch: () -> Void
    let onApplyPresets: () -> Void
    let onTutorial: () -> Void
    let allowBuild: Bool
    let allowPresets: Bool
    @State private var isVisible = false
    @AppStorage("homeHasAppeared") private var homeHasAppeared = false
    @State private var floatTagline = false

    var body: some View {
        ZStack {
            ScanlinesOverlay()

            VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("AudioShaper")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.neonPink)
                    .shadow(color: AppColors.neonPink.opacity(0.6), radius: 12)
                Text("Shape your system audio in real time")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)
            }

            HStack(spacing: 16) {
                NeonActionButton(
                    title: "Build from scratch",
                    subtitle: "New Project",
                    icon: "wand.and.stars",
                    accent: AppColors.neonCyan,
                    action: onBuildFromScratch
                )
                .disabled(!allowBuild)
                .opacity(allowBuild ? 1.0 : 0.35)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [.buildButton: proxy.frame(in: .global)]
                        )
                    }
                )

                NeonActionButton(
                    title: "Browse presets",
                    subtitle: "Saved Chains",
                    icon: "tray.full",
                    accent: AppColors.neonPink,
                    action: onApplyPresets
                )
                .disabled(!allowPresets)
                .opacity(allowPresets ? 1.0 : 0.35)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [.presetsButton: proxy.frame(in: .global)]
                        )
                    }
                )
            }

            Spacer()

            Text("Made by Skanda Vyas Srinivasan")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textMuted)
                .offset(y: floatTagline ? -6 : 0)
                .opacity(0.9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
        .onAppear {
            isVisible = false
            let duration = homeHasAppeared ? 0.45 : 0.8
            withAnimation(.easeOut(duration: duration)) {
                isVisible = true
            }
            homeHasAppeared = true
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                floatTagline = true
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onTutorial) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }
}

struct NeonActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(accent)
                Text(title.uppercased())
                    .font(AppTypography.heading)
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
            }
            .frame(width: 240, height: 150)
            .background(AppColors.midPurple)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isHovered ? accent : AppColors.neonCyan.opacity(0.4), lineWidth: 2)
            )
            .cornerRadius(16)
            .shadow(color: accent.opacity(isHovered ? 0.5 : 0.15), radius: isHovered ? 18 : 8)
            .scaleEffect(isHovered ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

private struct OverlayKeyCapture: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }

    final class KeyView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }
    }
}

struct AppTopBar: View {
    let title: String
    let onBack: () -> Void
    let tutorialTarget: TutorialTarget?
    let allowBack: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                Text("Home")
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.textSecondary)
            .disabled(!allowBack)
            .opacity(allowBack ? 1.0 : 0.35)
            .background(
                GeometryReader { proxy in
                    if let tutorialTarget {
                        Color.clear.preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [tutorialTarget: proxy.frame(in: .global)]
                        )
                    }
                }
            )

            Text(title)
                .font(AppTypography.technical)
                .foregroundColor(AppColors.textMuted)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppColors.deepBlack.opacity(0.7))
    }
}

enum TutorialTarget: Hashable {
    case buildButton
    case presetsButton
    case backButton
    case buildGraphMode
    case buildWiringMode
    case buildCanvasMenu
    case buildBassBoost
    case buildClarity
    case buildReverb
    case buildCanvas
    case buildSave
    case buildLoad
    case buildBassNode
    case buildClarityNode
    case buildReverbNode
}

struct TutorialTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [TutorialTarget: CGRect] = [:]

    static func reduce(value: inout [TutorialTarget: CGRect], nextValue: () -> [TutorialTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum TutorialStep: Equatable {
    case inactive
    case welcome
    case homePresets
    case presetsExplore
    case presetsBack
    case homeBuild
    case buildIntro
    case buildAddBass
    case buildAutoExplain
    case buildAutoAddClarity
    case buildAutoReorder
    case buildManualExplain
    case buildDoubleClick
    case buildCloseOverlay
    case buildRightClick
    case buildCloseContextMenu
    case buildWiringManual
    case buildConnect
    case buildResetWiringForParallel
    case buildParallelExplain
    case buildParallelAddReverb
    case buildParallelConnect
    case buildClearCanvasForDualMono
    case buildGraphMode
    case buildDualMonoAdd
    case buildDualMonoConnect
    case buildReturnStereoAuto
    case buildSave
    case buildSaveConfirm
    case buildLoad
    case buildCloseLoad
    case buildFinish
}

final class TutorialController: ObservableObject {
    @Published var step: TutorialStep = .inactive
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false

    var isActive: Bool { step != .inactive }

    var allowBuildAction: Bool {
        switch step {
        case .inactive, .homeBuild:
            return true
        default:
            return false
        }
    }

    var allowPresetsAction: Bool {
        switch step {
        case .inactive, .homePresets:
            return true
        default:
            return false
        }
    }

    var allowBackAction: Bool {
        switch step {
        case .presetsBack:
            return true
        default:
            return false
        }
    }

    var isBuildStep: Bool {
        switch step {
        case .buildIntro,
             .buildAddBass,
             .buildAutoExplain,
             .buildAutoAddClarity,
             .buildAutoReorder,
             .buildManualExplain,
             .buildDoubleClick,
             .buildCloseOverlay,
             .buildRightClick,
             .buildCloseContextMenu,
             .buildWiringManual,
             .buildConnect,
             .buildParallelExplain,
             .buildParallelAddReverb,
             .buildParallelConnect,
             .buildGraphMode,
             .buildDualMonoAdd,
             .buildReturnStereoAuto,
             .buildSave,
             .buildSaveConfirm,
             .buildLoad,
             .buildCloseLoad,
             .buildFinish:
            return true
        default:
            return false
        }
    }

    func startIfNeeded(isSetupVisible: Bool) {
        guard !hasSeenTutorial, !isSetupVisible else { return }
        step = .welcome
        hasSeenTutorial = true
    }

    func startFromHelp() {
        step = .welcome
    }

    func advance() {
        switch step {
        case .welcome:
            step = .homePresets
        case .homePresets:
            step = .presetsExplore
        case .presetsExplore:
            step = .presetsBack
        case .presetsBack:
            step = .homeBuild
        case .homeBuild:
            step = .buildIntro
        case .buildIntro:
            step = .buildAddBass
        case .buildAddBass:
            step = .buildAutoExplain
        case .buildAutoExplain:
            step = .buildAutoAddClarity
        case .buildAutoAddClarity:
            step = .buildAutoReorder
        case .buildAutoReorder:
            step = .buildManualExplain
        case .buildManualExplain:
            step = .buildWiringManual
        case .buildDoubleClick:
            step = .buildCloseOverlay
        case .buildCloseOverlay:
            step = .buildRightClick
        case .buildRightClick:
            step = .buildCloseContextMenu
        case .buildCloseContextMenu:
            step = .buildResetWiringForParallel
        case .buildWiringManual:
            step = .buildConnect
        case .buildConnect:
            step = .buildDoubleClick
        case .buildResetWiringForParallel:
            step = .buildParallelExplain
        case .buildParallelExplain:
            step = .buildParallelAddReverb
        case .buildParallelAddReverb:
            step = .buildParallelConnect
        case .buildParallelConnect:
            step = .buildClearCanvasForDualMono
        case .buildClearCanvasForDualMono:
            step = .buildGraphMode
        case .buildGraphMode:
            step = .buildDualMonoAdd
        case .buildDualMonoAdd:
            step = .buildDualMonoConnect
        case .buildDualMonoConnect:
            step = .buildReturnStereoAuto
        case .buildReturnStereoAuto:
            step = .buildSave
        case .buildSave:
            step = .buildSaveConfirm
        case .buildSaveConfirm:
            step = .buildLoad
        case .buildLoad:
            step = .buildCloseLoad
        case .buildCloseLoad:
            step = .buildFinish
        case .buildFinish:
            step = .inactive
        case .inactive:
            break
        }
    }

    func handlePresetsClick() {
        if step == .homePresets {
            step = .presetsExplore
        }
    }

    func handleBuildClick() {
        if step == .homeBuild {
            step = .buildIntro
        }
    }

    func handleBackClick() {
        if step == .presetsBack {
            step = .homeBuild
        }
    }

    func advanceIf(_ expected: TutorialStep) {
        if step == expected {
            advance()
        }
    }

    func endTutorial() {
        step = .inactive
    }
}

private struct TutorialOverlay: View {
    let step: TutorialStep
    let targets: [TutorialTarget: CGRect]
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var measuredCardSize: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let highlightRects = highlightFrames(in: size, proxy: proxy)
            let primaryHighlight: CGRect? = {
                switch step {
                case .buildReturnStereoAuto:
                    guard let first = highlightRects.first else { return nil }
                    return highlightRects.dropFirst().reduce(first) { partial, rect in
                        partial.union(rect)
                    }
                default:
                    return highlightRects.first
                }
            }()

            ZStack {
                dimmingLayer(size: size, highlights: highlightRects)
                    .allowsHitTesting(false)

                ForEach(Array(highlightRects.enumerated()), id: \.offset) { _, rect in
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.neonCyan.opacity(0.9), lineWidth: 2)
                        .shadow(color: AppColors.neonCyan.opacity(0.6), radius: 14)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                calloutView(in: size, highlight: primaryHighlight)
            }
        }
        .ignoresSafeArea()
    }

    private struct TutorialCardSizePreferenceKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            let next = nextValue()
            if next != .zero {
                value = next
            }
        }
    }

    private func highlightFrames(in size: CGSize, proxy: GeometryProxy) -> [CGRect] {
        switch step {
        case .homePresets:
            return [convertToLocal(rect: targets[.presetsButton], proxy: proxy)].compactMap { $0 }
        case .presetsExplore:
            return []
        case .homeBuild:
            return [convertToLocal(rect: targets[.buildButton], proxy: proxy)].compactMap { $0 }
        case .presetsBack:
            return [convertToLocal(rect: targets[.backButton], proxy: proxy)].compactMap { $0 }
        case .buildAutoAddClarity:
            return [
                convertToLocal(rect: targets[.buildClarity], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        case .buildAutoReorder:
            return [
                convertToLocal(rect: targets[.buildBassNode], proxy: proxy),
                convertToLocal(rect: targets[.buildClarityNode], proxy: proxy)
            ].compactMap { $0 }
        case .buildWiringManual:
            return [convertToLocal(rect: targets[.buildWiringMode], proxy: proxy)].compactMap { $0 }
        case .buildResetWiringForParallel:
            return [convertToLocal(rect: targets[.buildCanvasMenu], proxy: proxy)].compactMap { $0 }
        case .buildClearCanvasForDualMono:
            return [convertToLocal(rect: targets[.buildCanvasMenu], proxy: proxy)].compactMap { $0 }
        case .buildGraphMode:
            return [convertToLocal(rect: targets[.buildGraphMode], proxy: proxy)].compactMap { $0 }
        case .buildReturnStereoAuto:
            return [
                convertToLocal(rect: targets[.buildGraphMode], proxy: proxy),
                convertToLocal(rect: targets[.buildWiringMode], proxy: proxy)
            ].compactMap { $0 }
        case .buildAddBass:
            return [
                convertToLocal(rect: targets[.buildBassBoost], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        case .buildDoubleClick:
            return [convertToLocal(rect: targets[.buildBassNode], proxy: proxy)].compactMap { $0 }
        case .buildCloseOverlay:
            return [convertToLocal(rect: targets[.buildBassNode], proxy: proxy)].compactMap { $0 }
        case .buildSave:
            return [convertToLocal(rect: targets[.buildSave], proxy: proxy)].compactMap { $0 }
        case .buildSaveConfirm:
            return []
        case .buildLoad:
            return [convertToLocal(rect: targets[.buildLoad], proxy: proxy)].compactMap { $0 }
        case .buildCloseLoad:
            return []
        case .buildRightClick:
            return [convertToLocal(rect: targets[.buildBassNode], proxy: proxy)].compactMap { $0 }
        case .buildCloseContextMenu:
            return [convertToLocal(rect: targets[.buildBassNode], proxy: proxy)].compactMap { $0 }
        case .buildParallelAddReverb:
            return [
                convertToLocal(rect: targets[.buildReverb], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        case .buildParallelConnect:
            return [
                convertToLocal(rect: targets[.buildBassNode], proxy: proxy),
                convertToLocal(rect: targets[.buildClarityNode], proxy: proxy),
                convertToLocal(rect: targets[.buildReverbNode], proxy: proxy)
            ].compactMap { $0 }
        case .buildDualMonoAdd:
            return [
                convertToLocal(rect: targets[.buildGraphMode], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        case .buildDualMonoConnect:
            return [
                convertToLocal(rect: targets[.buildBassNode], proxy: proxy),
                convertToLocal(rect: targets[.buildClarityNode], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        default:
            return []
        }
    }

    private func convertToLocal(rect: CGRect?, proxy: GeometryProxy) -> CGRect? {
        guard let rect else { return nil }
        let global = proxy.frame(in: .global)
        return rect.offsetBy(dx: -global.minX, dy: -global.minY)
    }

    @ViewBuilder
    private func dimmingLayer(size: CGSize, highlights: [CGRect]) -> some View {
        if shouldDimBackground {
            if !highlights.isEmpty {
                ZStack {
                    Color.black.opacity(0.55)
                    ForEach(Array(highlights.enumerated()), id: \.offset) { _, rect in
                        RoundedRectangle(cornerRadius: 16)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            } else {
                Color.black.opacity(0.55)
            }
        } else {
            Color.clear
        }
    }

    private var shouldDimBackground: Bool {
        switch step {
        case .presetsExplore:
            return false
        case .buildAddBass:
            return false
        case .buildAutoAddClarity:
            return false
        case .buildConnect:
            // User needs to see the whole canvas to wire.
            return false
        case .buildAutoReorder:
            return false
        case .buildSaveConfirm:
            return false
        case .buildCloseLoad:
            return false
        case .buildParallelConnect:
            return false
        case .buildParallelAddReverb:
            return false
        case .buildDualMonoAdd:
            return false
        case .buildDualMonoConnect:
            return false
        case .buildResetWiringForParallel:
            return false
        case .buildClearCanvasForDualMono:
            return false
        case .buildReturnStereoAuto:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private func calloutView(in size: CGSize, highlight: CGRect?) -> some View {
        if let content = tutorialContent() {
            let cardBase = tutorialCard(
                title: content.title,
                body: content.body,
                showNext: content.showNext
            )

            let card = cardBase
                .frame(maxWidth: highlight == nil ? 420 : 360)
                .background(
                    GeometryReader { cardProxy in
                        Color.clear.preference(
                            key: TutorialCardSizePreferenceKey.self,
                            value: cardProxy.size
                        )
                    }
                )
                .onPreferenceChange(TutorialCardSizePreferenceKey.self) { newSize in
                    measuredCardSize = newSize
                }

            if let rect = highlight {
                let position = bestCalloutPosition(
                    screen: size,
                    target: rect,
                    cardSize: measuredCardSize == .zero ? CGSize(width: 360, height: 140) : measuredCardSize
                )
                card.position(position)
            } else {
                let fallbackSize = measuredCardSize == .zero ? CGSize(width: 420, height: 140) : measuredCardSize
                let position = clamp(
                    CGPoint(x: size.width / 2, y: size.height * 0.22),
                    screen: size,
                    cardSize: fallbackSize
                )
                card.position(position)
            }
        } else {
            EmptyView()
        }
    }

    private func bestCalloutPosition(screen: CGSize, target: CGRect, cardSize: CGSize) -> CGPoint {
        let padding: CGFloat = 16
        let avoidPad: CGFloat = 10

        // Special case: For back button, force center-lower position to avoid blocking
        if step == .presetsBack {
            return clamp(
                CGPoint(x: screen.width / 2, y: screen.height * 0.65),
                screen: screen,
                cardSize: cardSize
            )
        }

        let candidates: [CGPoint]
        if step == .buildReturnStereoAuto {
            candidates = [
                CGPoint(x: target.midX, y: target.minY - padding - cardSize.height / 2), // above
                CGPoint(x: target.maxX + padding + cardSize.width / 2, y: target.midY), // right
                CGPoint(x: target.minX - padding - cardSize.width / 2, y: target.midY), // left
                CGPoint(x: target.midX, y: target.maxY + padding + cardSize.height / 2) // below
            ]
        } else {
            candidates = [
                CGPoint(x: target.maxX + padding + cardSize.width / 2, y: target.midY), // right
                CGPoint(x: target.minX - padding - cardSize.width / 2, y: target.midY), // left
                CGPoint(x: target.midX, y: target.maxY + padding + cardSize.height / 2), // below
                CGPoint(x: target.midX, y: target.minY - padding - cardSize.height / 2)  // above
            ]
        }

        let inflatedTarget = target.insetBy(dx: -avoidPad, dy: -avoidPad)
        for candidate in candidates {
            let rect = cardRect(center: candidate, cardSize: cardSize)
            if isRectOnScreen(rect, screen: screen, padding: padding),
               !rect.intersects(inflatedTarget) {
                return candidate
            }
        }

        // Fallback: prefer below, but clamp so it always stays visible.
        return clamp(candidates.last ?? CGPoint(x: screen.width / 2, y: screen.height / 2), screen: screen, cardSize: cardSize)
    }

    private func clamp(_ center: CGPoint, screen: CGSize, cardSize: CGSize) -> CGPoint {
        let padding: CGFloat = 14
        let halfW = cardSize.width / 2
        let halfH = cardSize.height / 2
        let x = min(max(center.x, padding + halfW), screen.width - padding - halfW)
        let y = min(max(center.y, padding + halfH), screen.height - padding - halfH)
        return CGPoint(x: x, y: y)
    }

    private func cardRect(center: CGPoint, cardSize: CGSize) -> CGRect {
        CGRect(
            x: center.x - cardSize.width / 2,
            y: center.y - cardSize.height / 2,
            width: cardSize.width,
            height: cardSize.height
        )
    }

    private func isRectOnScreen(_ rect: CGRect, screen: CGSize, padding: CGFloat) -> Bool {
        rect.minX >= padding &&
        rect.minY >= padding &&
        rect.maxX <= screen.width - padding &&
        rect.maxY <= screen.height - padding
    }

    private func tutorialContent() -> (title: String, body: String, showNext: Bool)? {
        switch step {
        case .welcome:
            return (
                title: "Welcome",
                body: "Hey, welcome to AudioShaper. Since it’s your first time here, let me walk you through the key screens.",
                showNext: true
            )
        case .homePresets:
            return (
                title: "Presets",
                body: "This page houses your saved chains. Tap Presets to browse them before heading back.",
                showNext: false
            )
        case .presetsExplore:
            return (
                title: "Browse presets",
                body: "Once you start saving chains, they’ll show up here. Take a quick look around, then press Next to continue.",
                showNext: true
            )
        case .presetsBack:
            return (
                title: "Back to Home",
                body: "Tap Home to return once you’ve reviewed a preset.",
                showNext: false
            )
        case .homeBuild:
            return (
                title: "Build",
                body: "Build opens a fresh canvas for crafting blocks. Tap it when you’re ready.",
                showNext: false
            )
        case .buildIntro:
            return (
                title: "Canvas",
                body: "This is where signal flow happens. Drag effects from the tray into this space.",
                showNext: true
            )
        case .buildAddBass:
            return (
                title: "Add Bass Boost",
                body: "Bass Boost fattens the lows. Drag Bass Boost from the Effects tray onto the canvas.",
                showNext: false
            )
        case .buildAutoExplain:
            return (
                title: "Automatic wiring",
                body: "Over here, Automatic wiring connects your effects for you. Add blocks and we’ll keep the signal flowing left to right.",
                showNext: true
            )
        case .buildAutoAddClarity:
            return (
                title: "Add a second block",
                body: "Drag Clarity onto the canvas. It should auto-connect into the chain.",
                showNext: false
            )
        case .buildAutoReorder:
            return (
                title: "Reorder by moving",
                body: "Drag Clarity to the left of Bass Boost. The auto-chain should reorder instantly.",
                showNext: false
            )
        case .buildManualExplain:
            return (
                title: "Manual wiring",
                body: "Manual wiring gives you full control. You can connect in series, build parallel paths, and merge them back together.",
                showNext: true
            )
        case .buildDoubleClick:
            return (
                title: "Open controls",
                body: "Double-click the Bass Boost node to open its controls.",
                showNext: false
            )
        case .buildCloseOverlay:
            return (
                title: "Close controls",
                body: "Nice. Now close the panel (double-click the node again) so we can continue.",
                showNext: false
            )
        case .buildRightClick:
            return (
                title: "Right-click menu",
                body: "Right-click the Bass Boost node to open the action menu.",
                showNext: false
            )
        case .buildCloseContextMenu:
            return (
                title: "Close the menu",
                body: "Click anywhere outside the menu to close it.",
                showNext: false
            )
        case .buildWiringManual:
            return (
                title: "Switch to Manual",
                body: "Switch Wiring to Manual so you can draw connections yourself.",
                showNext: false
            )
        case .buildConnect:
            return (
                title: "Connect nodes",
                body: "Hold Option, then drag from Start to Bass Boost. Then drag from Bass Boost to End.",
                showNext: false
            )
        case .buildResetWiringForParallel:
            return (
                title: "Reset wiring",
                body: "Before we build a new wiring pattern, reset the current wires. Open Canvas, then click Reset Wiring.",
                showNext: false
            )
        case .buildParallelExplain:
            return (
                title: "Parallel paths",
                body: "Now let’s do a parallel route. We’ll split into two effects, then merge into Reverb.",
                showNext: true
            )
        case .buildParallelAddReverb:
            return (
                title: "Add Reverb",
                body: "Drag Reverb onto the canvas. We’ll use it as the merge point.",
                showNext: false
            )
        case .buildParallelConnect:
            return (
                title: "Wire the parallel merge",
                body: "Option-drag: Start → Bass Boost, Start → Clarity, then Bass Boost → Reverb, Clarity → Reverb, and Reverb → End.",
                showNext: false
            )
        case .buildClearCanvasForDualMono:
            return (
                title: "Clear the canvas",
                body: "Clear the canvas so the next step starts clean. Open Canvas, then click Clear Canvas.",
                showNext: false
            )
        case .buildGraphMode:
            return (
                title: "Graph Mode",
                body: "Dual Mono (L/R) separates the channels. Switch to it to keep left and right processing paths independent.",
                showNext: false
            )
        case .buildDualMonoAdd:
            return (
                title: "Dual Mono demo",
                body: "With Dual Mono on, drag Bass Boost into the left lane, then drag Clarity into the right lane.",
                showNext: false
            )
        case .buildDualMonoConnect:
            return (
                title: "Wire both lanes",
                body: "Hold Option and connect Start L → Bass Boost → End L. Then connect Start R → Clarity → End R.",
                showNext: false
            )
        case .buildReturnStereoAuto:
            return (
                title: "Back to defaults",
                body: "Set Graph Mode back to Stereo, and Wiring back to Automatic.",
                showNext: false
            )
        case .buildSave:
            return (
                title: "Save your chain",
                body: "Save locks this chain into a preset you can reload later.",
                showNext: false
            )
        case .buildSaveConfirm:
            return (
                title: "Saved",
                body: "Nice. Your chain is saved. Next we’ll load a preset.",
                showNext: true
            )
        case .buildLoad:
            return (
                title: "Load presets",
                body: "Open Load, pick a preset, and press Apply.",
                showNext: false
            )
        case .buildCloseLoad:
            return (
                title: "Close Load",
                body: "Close the Load window to finish the tutorial.",
                showNext: false
            )
        case .buildFinish:
            return (
                title: "All set",
                body: "That’s the loop. Build, tweak, save, load. You’re ready to bend audio.",
                showNext: true
            )
        case .inactive:
            return nil
        }
    }

    private func tutorialCard(title: String, body: String, showNext: Bool) -> some View {
        TutorialCardView(
            title: title,
            message: body,
            showNext: showNext,
            onNext: onNext,
            onSkip: onSkip
        )
    }
}

// MARK: - Save Preset Dialog

struct SavePresetDialog: View {
    @Binding var presetName: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Save Preset")
                .font(AppTypography.heading)
                .foregroundColor(AppColors.textPrimary)

            TextField("Preset Name", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(presetName.isEmpty)
            }
        }
        .padding()
        .frame(width: 350, height: 150)
        .background(AppColors.midPurple)
        .cornerRadius(16)
    }
}

// MARK: - Header View

struct HeaderView: View {
    @ObservedObject var audioEngine: AudioEngine
    let onSave: () -> Void
    let onLoad: () -> Void
    let onSaveAs: () -> Void
    let allowSave: Bool
    let allowLoad: Bool
    @Binding var saveStatusText: String?

    var body: some View {
        HStack(spacing: 20) {
            // Power button
            Button(action: {
                if audioEngine.isRunning {
                    audioEngine.stop()
                } else {
                    _ = audioEngine.refreshSetupStatus()
                    guard audioEngine.setupReady else {
                        audioEngine.errorMessage = "System Input/Output must be BlackHole 2ch to start."
                        return
                    }
                    audioEngine.start()
                }
            }) {
                Image(systemName: audioEngine.isRunning ? "power.circle.fill" : "power.circle")
                    .font(.system(size: 24))
                    .foregroundColor(audioEngine.isRunning ? AppColors.success : AppColors.textMuted)
            }
            .buttonStyle(.plain)
            .opacity(audioEngine.setupReady ? 1.0 : 0.5)
            .help(audioEngine.isRunning ? "Stop Processing" : (audioEngine.setupReady ? "Start Processing" : "Set System Input/Output to BlackHole 2ch to start"))

            Divider()
                .frame(height: 30)
                .background(AppColors.gridLines)

            // FX bypass
            Button(action: {
                audioEngine.processingEnabled.toggle()
            }) {
                Image(systemName: audioEngine.processingEnabled ? "slider.horizontal.3" : "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundColor(audioEngine.processingEnabled ? AppColors.neonCyan : AppColors.textMuted)
            }
            .buttonStyle(.plain)
            .help(audioEngine.processingEnabled ? "Disable Effects" : "Enable Effects")

            Divider()
                .frame(height: 30)
                .background(AppColors.gridLines)

            // Limiter toggle
            Button(action: {
                audioEngine.limiterEnabled.toggle()
            }) {
                Image(systemName: audioEngine.limiterEnabled ? "shield.fill" : "shield.slash")
                    .font(.system(size: 18))
                    .foregroundColor(audioEngine.limiterEnabled ? AppColors.warning : AppColors.textMuted)
            }
            .buttonStyle(.plain)
            .help(audioEngine.limiterEnabled ? "Limiter On" : "Limiter Off")

            Divider()
                .frame(height: 30)
                .background(AppColors.gridLines)

            // Input device (read-only, shows BlackHole)
            VStack(alignment: .leading, spacing: 2) {
                Text("Input")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
                Text(audioEngine.inputDeviceName)
                    .font(AppTypography.technical)
                    .foregroundColor(AppColors.textSecondary)
            }

            // Output device picker + volume
            VStack(alignment: .leading, spacing: 6) {
                Text("Output")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
                Picker("", selection: $audioEngine.selectedOutputDeviceID) {
                    ForEach(audioEngine.outputDevices, id: \.id) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .labelsHidden()
                .frame(width: 220)

                Slider(
                    value: Binding(
                        get: { Double(audioEngine.outputVolume) },
                        set: { audioEngine.outputVolume = Float($0) }
                    ),
                    in: 0...1
                )
                .tint(AppColors.neonCyan)
                .frame(width: 220)
            }

            Spacer()

            // Error message if any
            if let error = audioEngine.errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.error)
                    .lineLimit(2)
                    .frame(maxWidth: 250)
            }

            // Save/Load buttons
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Button("Save") {
                            onSave()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .disabled(!allowSave)
                        .opacity(allowSave ? 1.0 : 0.4)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TutorialTargetPreferenceKey.self,
                                    value: [.buildSave: proxy.frame(in: .global)]
                                )
                            }
                        )

                        Divider()
                            .frame(height: 16)
                            .background(AppColors.neonCyan.opacity(0.6))

                        Menu {
                            Button("Save As…") {
                                onSaveAs()
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .frame(width: 44, height: 28)
                                )
                        }
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                        .disabled(!allowSave)
                        .opacity(allowSave ? 1.0 : 0.4)
                    }
                    .background(AppColors.neonCyan.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.neonCyan, lineWidth: 1)
                )
                    .cornerRadius(8)

                    Button("Load Preset") {
                        onLoad()
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.neonPink)
                    .disabled(!allowLoad)
                    .opacity(allowLoad ? 1.0 : 0.4)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TutorialTargetPreferenceKey.self,
                                value: [.buildLoad: proxy.frame(in: .global)]
                            )
                        }
                    )
                }

                if let saveStatusText {
                    Text(saveStatusText)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .transition(.opacity)
                }
            }
        }
        .padding()
        .background(AppColors.midPurple.opacity(0.9))
    }
}

// MARK: - Preset View

struct PresetView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var presetManager: PresetManager
    let onPresetApplied: (SavedPreset) -> Void
    @ObservedObject var tutorial: TutorialController
    @State private var searchText = ""

    var body: some View {
        let filteredPresets = presetManager.presets.filter { preset in
            searchText.isEmpty || preset.name.lowercased().contains(searchText.lowercased())
        }

        VStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.neonCyan)
                TextField("Search presets...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(10)
            .background(AppColors.midPurple)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.neonCyan.opacity(0.6), lineWidth: 1)
            )
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if filteredPresets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.textMuted)
                    Text("No saved presets")
                        .font(AppTypography.heading)
                        .foregroundColor(AppColors.textSecondary)
                    Text("Create effect chains in Beginner or Advanced mode, then save them as presets")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(filteredPresets) { preset in
                            PresetCard(
                                preset: preset,
                                onApply: {
                                    audioEngine.requestGraphLoad(preset.graph)
                                    onPresetApplied(preset)
                                },
                                onDelete: {
                                    presetManager.deletePreset(preset)
                                },
                                isDisabled: tutorial.step == .presetsBack
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
        .allowsHitTesting(!tutorial.isActive || tutorial.step != .presetsBack)
    }
}

struct PresetCard: View {
    let preset: SavedPreset
    let onApply: () -> Void
    let onDelete: () -> Void
    let isDisabled: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: onApply) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(AppTypography.heading)
                        .foregroundColor(AppColors.textPrimary)
                    Text("\(preset.graph.nodes.count) effects")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.neonCyan)
                }

                Spacer()
            }
            .padding()
            .background(isHovered ? AppColors.midPurple : AppColors.darkPurple)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? AppColors.neonPink : AppColors.gridLines, lineWidth: isHovered ? 2 : 1)
            )
            .cornerRadius(12)
            .shadow(color: AppColors.neonPink.opacity(isHovered ? 0.4 : 0), radius: 12)
            .overlay(alignment: .topTrailing) {
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.error)
                            .padding(6)
                            .background(AppColors.darkPurple.opacity(0.9))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// BeginnerView is now in BeginnerView.swift

// Preview disabled to avoid build-time macro errors.
