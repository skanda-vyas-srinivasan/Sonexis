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
        HStack(spacing: 16) {
            // Power button with status
            VStack(spacing: 4) {
                Button(action: {
                    if audioEngine.isRunning {
                        audioEngine.stop()
                    } else {
                        audioEngine.start()
                        tutorial.advanceIf(.buildPower)
                    }
                }) {
                    Image(systemName: audioEngine.isRunning ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 24))
                        .foregroundColor(audioEngine.isRunning ? AppColors.success : AppColors.textMuted)
                        .shadow(color: audioEngine.isRunning ? AppColors.success.opacity(0.18) : .clear, radius: 8)
                }
                .buttonStyle(.plain)
                .help(audioEngine.isRunning ? "Stop Processing" : audioEngine.startHelpText)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [.buildPower: proxy.frame(in: .global)]
                        )
                    }
                )

                if audioEngine.isRunning {
                    Text(audioEngine.activeRouteLabel)
                        .font(.system(size: 9))
                        .foregroundColor(AppColors.success.opacity(0.8))
                        .transition(.opacity)
                }
            }

            Divider()
                .frame(height: 30)
                .background(AppColors.controlStrokeSoft.opacity(0.65))

            // FX bypass
            Button(action: {
                audioEngine.processingEnabled.toggle()
            }) {
                Image(systemName: audioEngine.processingEnabled ? "slider.horizontal.3" : "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundColor(audioEngine.processingEnabled ? AppColors.neonCyan : AppColors.textMuted)
                    .frame(width: 34, height: 28)
            }
            .buttonStyle(.plain)
            .help(audioEngine.processingEnabled ? "Disable Effects" : "Enable Effects")

            Divider()
                .frame(height: 30)
                .background(AppColors.controlStrokeSoft.opacity(0.65))

            let recordDisabled = !audioEngine.isRunning || tutorial.isActive
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
                .frame(width: 108, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(recordDisabled)
            .opacity(recordDisabled ? 0.4 : 1.0)
            .help(audioEngine.isRecording ? "Stop Recording" : "Start Recording")
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TutorialTargetPreferenceKey.self,
                        value: [.buildRecord: proxy.frame(in: .global)]
                    )
                }
            )

            Divider()
                .frame(height: 30)
                .background(AppColors.controlStrokeSoft.opacity(0.65))

            // Output route
            VStack(alignment: .leading, spacing: 2) {
                Text("Output")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)

                if audioEngine.isProcessTapBackendEnabled {
                    Text("macOS Default")
                        .font(AppTypography.technical)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 220, alignment: .leading)
                        .help("Process Tap playback follows the current macOS default output device.")
                } else {
                    Picker("", selection: $audioEngine.selectedOutputDeviceID) {
                        ForEach(audioEngine.outputDevices, id: \.id) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .onTapGesture {
                        audioEngine.refreshOutputDevices()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.controlPurple.opacity(0.48))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.controlStroke.opacity(0.56), lineWidth: 1)
            )
            .cornerRadius(8)
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
                        .foregroundColor(AppColors.textPrimary)
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
                            .background(AppColors.controlStroke.opacity(0.62))

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
                        .foregroundColor(AppColors.textPrimary)
                    }
                    .background(AppColors.controlPurple.opacity(0.70))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.controlStroke.opacity(0.76), lineWidth: 1)
                )
                    .cornerRadius(8)

                    Button("Load Preset") {
                        onLoad()
                    }
                    .buttonStyle(.plain)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppColors.controlPurple.opacity(0.70))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.controlStroke.opacity(0.76), lineWidth: 1)
                    )
                    .cornerRadius(8)
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
        .background(AppColors.panelPurple.opacity(0.84))
        .overlay(
            LinearGradient(
                colors: [AppColors.controlStroke.opacity(0.42), AppColors.neonCyan.opacity(0.16), AppColors.neonPink.opacity(0.12)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1),
            alignment: .bottom
        )
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
