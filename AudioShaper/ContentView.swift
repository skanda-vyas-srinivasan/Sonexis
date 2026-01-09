import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var presetManager = PresetManager()
    @State private var activeScreen: AppScreen = .home
    @State private var showingSaveDialog = false
    @State private var showingLoadDialog = false
    @State private var presetNameInput = ""
    @State private var showGlitch = false

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
                                presetNameInput = ""
                                showingSaveDialog = true
                            },
                            onLoad: {
                                showingLoadDialog = true
                            }
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
                                onPresetApplied: {
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
        }
        .onChange(of: activeScreen) { _ in
            showGlitch = true
        }
        .sheet(isPresented: $showingSaveDialog) {
            SavePresetDialog(
                presetName: $presetNameInput,
                onSave: {
                    saveCurrentPreset()
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
                    showingLoadDialog = false
                },
                onCancel: {
                    showingLoadDialog = false
                }
            )
        }
    }

    private func saveCurrentPreset() {
        guard !presetNameInput.isEmpty else { return }

        guard let graph = audioEngine.currentGraphSnapshot else {
            print("⚠️ No graph snapshot available to save")
            return
        }
        presetManager.savePreset(name: presetNameInput, graph: graph)

        print("✅ Preset saved: \(presetNameInput)")
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

    var body: some View {
        ZStack {
            ScanlinesOverlay()

            VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("HoldOn")
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

    var body: some View {
        HStack(spacing: 20) {
            // Power button
            Button(action: {
                if audioEngine.isRunning {
                    audioEngine.stop()
                } else {
                    audioEngine.start()
                }
            }) {
                Image(systemName: audioEngine.isRunning ? "power.circle.fill" : "power.circle")
                    .font(.system(size: 24))
                    .foregroundColor(audioEngine.isRunning ? AppColors.success : AppColors.textMuted)
            }
            .buttonStyle(.plain)
            .help(audioEngine.isRunning ? "Stop Processing" : "Start Processing")

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

            // Output device picker
            VStack(alignment: .leading, spacing: 2) {
                Text("Output")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
                Picker("", selection: $audioEngine.selectedOutputDeviceID) {
                    ForEach(audioEngine.outputDevices, id: \.id) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .labelsHidden()
                .frame(width: 200)
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
            HStack(spacing: 8) {
                Button("Save Preset") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.neonCyan)

                Button("Load Preset") {
                    onLoad()
                }
                .buttonStyle(.bordered)
                .tint(AppColors.neonPink)
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
    let onPresetApplied: () -> Void
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
                                    onPresetApplied()
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
