import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var presetManager = PresetManager()
    @State private var activeScreen: AppScreen = .home
    @State private var showingSaveDialog = false
    @State private var presetNameInput = ""

    var body: some View {
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

                HeaderView(
                    audioEngine: audioEngine,
                    onSave: {
                        presetNameInput = ""
                        showingSaveDialog = true
                    },
                    onLoad: {
                        // TODO: Show load dialog
                    }
                )

                Divider()

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
        .background(Color(NSColor.windowBackgroundColor))
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
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("HoldOn")
                    .font(.system(size: 44, weight: .semibold))
                Text("Shape your system audio in real time")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Button(action: onBuildFromScratch) {
                    VStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 28))
                        Text("Build from scratch")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(width: 220, height: 140)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onApplyPresets) {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 28))
                        Text("Apply saved presets")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(width: 220, height: 140)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
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

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
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
                .font(.headline)

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
                    .foregroundColor(audioEngine.isRunning ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(audioEngine.isRunning ? "Stop Processing" : "Start Processing")

            Divider()
                .frame(height: 30)

            // FX bypass
            Button(action: {
                audioEngine.processingEnabled.toggle()
            }) {
                Image(systemName: audioEngine.processingEnabled ? "slider.horizontal.3" : "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundColor(audioEngine.processingEnabled ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help(audioEngine.processingEnabled ? "Disable Effects" : "Enable Effects")

            Divider()
                .frame(height: 30)

            // Limiter toggle
            Button(action: {
                audioEngine.limiterEnabled.toggle()
            }) {
                Image(systemName: audioEngine.limiterEnabled ? "shield.fill" : "shield.slash")
                    .font(.system(size: 18))
                    .foregroundColor(audioEngine.limiterEnabled ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(audioEngine.limiterEnabled ? "Limiter On" : "Limiter Off")

            Divider()
                .frame(height: 30)

            // Input device (read-only, shows BlackHole)
            VStack(alignment: .leading, spacing: 2) {
                Text("Input")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(audioEngine.inputDeviceName)
                    .font(.system(size: 11))
            }

            // Output device picker
            VStack(alignment: .leading, spacing: 2) {
                Text("Output")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 250)
            }

            // Save/Load buttons
            HStack(spacing: 8) {
                Button("Save Preset") {
                    onSave()
                }

                Button("Load Preset") {
                    onLoad()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Preset View

struct PresetView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var presetManager: PresetManager
    let onPresetApplied: () -> Void

    var body: some View {
        VStack {
            if presetManager.presets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No saved presets")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Create effect chains in Beginner or Advanced mode, then save them as presets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(presetManager.presets) { preset in
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
                    .padding()
                }
            }
        }
    }
}

struct PresetCard: View {
    let preset: SavedPreset
    let onApply: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(.headline)
                    Text("\(preset.graph.nodes.count) effects")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            Spacer()

            Button("Apply") {
                onApply()
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// BeginnerView is now in BeginnerView.swift

// Preview disabled to avoid build-time macro errors.
