import SwiftUI
import AppKit

struct HeaderView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var tutorial: TutorialController
    let onSave: () -> Void
    let onLoad: () -> Void
    let onSaveAs: () -> Void
    let allowSave: Bool
    let allowLoad: Bool
    @Binding var saveStatusText: String?

    var body: some View {
        HStack(spacing: 20) {
            // Power button with status
            VStack(spacing: 4) {
                Button(action: {
                    if audioEngine.isRunning {
                        audioEngine.stop()
                    } else {
                        // Let start() handle BlackHole setup automatically
                        audioEngine.start()
                        tutorial.advanceIf(.buildPower)
                    }
                }) {
                    Image(systemName: audioEngine.isRunning ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 24))
                        .foregroundColor(audioEngine.isRunning ? AppColors.success : AppColors.textMuted)
                }
                .buttonStyle(.plain)
                .help(audioEngine.isRunning ? "Stop Processing" : "Start Processing (Auto-routes to BlackHole)")
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [.buildPower: proxy.frame(in: .global)]
                        )
                    }
                )

                if audioEngine.isRunning {
                    Text("Routed to BlackHole")
                        .font(.system(size: 9))
                        .foregroundColor(AppColors.success.opacity(0.8))
                        .transition(.opacity)
                }
            }

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
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TutorialTargetPreferenceKey.self,
                        value: [.buildShield: proxy.frame(in: .global)]
                    )
                }
            )

            if audioEngine.betaRecordingUnlocked {
                Divider()
                    .frame(height: 30)
                    .background(AppColors.gridLines)

                Button(action: {
                    if audioEngine.isRecording {
                        audioEngine.stopRecording()
                    } else if let url = promptForRecordingURL() {
                        audioEngine.startRecording(url: url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(audioEngine.isRecording ? AppColors.error : AppColors.textMuted)
                            .frame(width: 8, height: 8)
                        Text(audioEngine.isRecording ? "Recording" : "Record")
                            .font(AppTypography.caption)
                            .foregroundColor(audioEngine.isRecording ? AppColors.error : AppColors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!audioEngine.isRunning)
                .opacity(audioEngine.isRunning ? 1.0 : 0.4)
                .help(audioEngine.isRecording ? "Stop Recording (Beta)" : "Start Recording (Beta)")
            }

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
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TutorialTargetPreferenceKey.self,
                        value: [.buildOutput: proxy.frame(in: .global)]
                    )
                }
            )

            Spacer()

            // Error message if any
            if let error = audioEngine.errorMessage {
                HStack(spacing: 8) {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.error)
                        .lineLimit(2)
                        .frame(maxWidth: 200)

                    // Show "Open Settings" button for device-related errors
                    if error.localizedCaseInsensitiveContains("Input") ||
                       error.localizedCaseInsensitiveContains("Output") ||
                       error.localizedCaseInsensitiveContains("BlackHole") {
                        Button("Open Sound Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(AppTypography.caption)
                        .tint(AppColors.neonPink)
                    } else if error.localizedCaseInsensitiveContains("Microphone") {
                        Button("Open Microphone Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(AppTypography.caption)
                        .tint(AppColors.neonPink)
                    }
                }
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
        .animation(.easeInOut(duration: 0.3), value: audioEngine.isRunning)
    }

    private func promptForRecordingURL() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Recording"
        panel.nameFieldStringValue = "Sonexis Recording.wav"
        panel.allowedFileTypes = ["wav"]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
