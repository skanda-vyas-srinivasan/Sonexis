import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var presetManager = PresetManager()
    @State private var selectedTab = 1 // Start on Beginner mode
    @State private var showingSaveDialog = false
    @State private var presetNameInput = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            // Tab selector
            Picker("Mode", selection: $selectedTab) {
                Text("Presets").tag(0)
                Text("Beginner").tag(1)
                Text("Advanced").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Content area based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    PresetView(
                        audioEngine: audioEngine,
                        presetManager: presetManager
                    )
                case 1:
                    BeginnerView(
                        audioEngine: audioEngine,
                        presetManager: presetManager
                    )
                case 2:
                    AdvancedView(audioEngine: audioEngine)
                default:
                    EmptyView()
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

        // Get current effect chain from audio engine
        let chain = audioEngine.getCurrentEffectChain()
        presetManager.savePreset(name: presetNameInput, chain: chain)

        print("✅ Preset saved: \(presetNameInput)")
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
                                    audioEngine.applyEffectChain(preset.chain)
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
                Text("\(preset.chain.activeEffects.count) effects")
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

// MARK: - Advanced View

struct AdvancedView: View {
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        VStack {
            Spacer()
            Text("Advanced Mode")
                .font(.title)
                .foregroundColor(.secondary)
            Text("Node graph editor coming soon")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
