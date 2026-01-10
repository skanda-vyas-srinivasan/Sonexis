import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var presetManager = PresetManager()
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

    var body: some View {
        ZStack {
            AppGradients.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if activeScreen == .home {
                    HomeView(
                        onBuildFromScratch: { activeScreen = .beginner },
                        onApplyPresets: { activeScreen = .presets }
                    )
                } else {
                    AppTopBar(
                        title: activeScreen == .beginner ? "Build" : "Presets",
                        onBack: { activeScreen = .home }
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
                                }
                            )
                        case .beginner:
                            BeginnerView(audioEngine: audioEngine)
                        case .home:
                            EmptyView()
                        }
                    }
                }
            }
            .frame(minWidth: 800, minHeight: 700)

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
        }
        .onAppear {
            guard !hasShownSetupThisSession else { return }
            hasShownSetupThisSession = true
            let ready = audioEngine.refreshSetupStatus()
            if !ready {
                showSetupOverlay = true
            }
        }
        .onChange(of: activeScreen) { newValue in
            showGlitch = true
            handleScreenChange(to: newValue)
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
                onApply: { preset in
                    audioEngine.requestGraphLoad(preset.graph)
                    currentPresetID = preset.id
                    showingLoadDialog = false
                },
                onCancel: {
                    showingLoadDialog = false
                }
            )
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
        .alert("Skip setup?", isPresented: $showSkipConfirm) {
            Button("Skip", role: .destructive) {
                onDone()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AudioShaper won’t be functional without setting Input and Output to BlackHole. You won’t hear sound until you set it up.")
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

struct LoadPresetDialog: View {
    @ObservedObject var presetManager: PresetManager
    let onApply: (SavedPreset) -> Void
    let onCancel: () -> Void
    @State private var searchText = ""

    var body: some View {
        let filteredPresets = presetManager.presets.filter { preset in
            searchText.isEmpty || preset.name.lowercased().contains(searchText.lowercased())
        }

        VStack(spacing: 16) {
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

                NeonActionButton(
                    title: "Browse presets",
                    subtitle: "Saved Chains",
                    icon: "tray.full",
                    accent: AppColors.neonPink,
                    action: onApplyPresets
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

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                Text("Home")
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.textSecondary)

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
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
    }
}

struct PresetCard: View {
    let preset: SavedPreset
    let onApply: () -> Void
    let onDelete: () -> Void
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
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// BeginnerView is now in BeginnerView.swift

// Preview disabled to avoid build-time macro errors.
