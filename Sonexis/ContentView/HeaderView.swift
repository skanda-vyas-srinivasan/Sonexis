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
    @State private var showingAudioSettings = false

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

            OutputMeterSection(
                level: audioEngine.outputMeterLevel,
                peakDBFS: audioEngine.outputMeterPeakDBFS,
                isActive: audioEngine.isRunning
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TutorialTargetPreferenceKey.self,
                        value: [.buildOutput: proxy.frame(in: .global)]
                    )
                }
            )

            if audioEngine.isProcessTapBackendEnabled {
                Divider()
                    .frame(height: 30)
                    .background(AppColors.controlStrokeSoft.opacity(0.65))

                AudioSettingsButton(
                    isPresented: $showingAudioSettings,
                    trimDB: $audioEngine.processTapInputTrimDB,
                    makeupDB: $audioEngine.processTapOutputMakeupDB,
                    ceilingEnabled: $audioEngine.processTapOutputCeilingEnabled
                )
            }

            Spacer()

            if let warning = audioEngine.processTapWarningText {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.badge.exclamationmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text(warning)
                        .font(AppTypography.caption)
                        .lineLimit(2)
                }
                .foregroundColor(AppColors.warning)
                .frame(maxWidth: 260, alignment: .leading)
                .help("The Process Tap output ring underflowed. This means Sonexis did not produce processed audio fast enough for playback.")
            }

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

private struct AudioSettingsButton: View {
    @Binding var isPresented: Bool
    @Binding var trimDB: Double
    @Binding var makeupDB: Double
    @Binding var ceilingEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isPresented.toggle()
                }
            } label: {
                Image(systemName: isPresented ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isPresented ? AppColors.neonPink : AppColors.neonCyan)
                    .frame(width: 34, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isPresented ? "Close audio settings" : "Audio settings")

            if isPresented {
                AudioSettingsInlinePanel(
                    trimDB: $trimDB,
                    makeupDB: $makeupDB,
                    ceilingEnabled: $ceilingEnabled
                )
                .transition(
                    .scale(scale: 0.96, anchor: .leading)
                        .combined(with: .opacity)
                )
            }
        }
        .animation(.easeOut(duration: 0.18), value: isPresented)
    }
}

private struct AudioSettingsInlinePanel: View {
    @Binding var trimDB: Double
    @Binding var makeupDB: Double
    @Binding var ceilingEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            AudioSettingsCompactSlider(
                title: "Tap In",
                valueText: String(format: "%.0f dB", trimDB),
                value: Binding(
                    get: { trimDB },
                    set: { trimDB = min(max($0, -30), 0) }
                ),
                range: -30...0,
                step: 1,
                tint: AppColors.neonCyan
            )

            AudioSettingsCompactSlider(
                title: "Makeup",
                valueText: String(format: "%+.0f dB", makeupDB),
                value: Binding(
                    get: { makeupDB },
                    set: { makeupDB = min(max($0, -12), 30) }
                ),
                range: -12...30,
                step: 1,
                tint: AppColors.neonPink
            )

            OutputCeilingButton(isOn: $ceilingEnabled)

            Button {
                trimDB = -12
                makeupDB = 12
                ceilingEnabled = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reset to defaults")
        }
        .frame(height: 44)
    }
}

private struct AudioSettingsCompactSlider: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)

                Spacer(minLength: 4)

                Text(valueText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(tint)
                    .monospacedDigit()
            }

            Slider(
                value: $value,
                in: range,
                step: step
            )
            .controlSize(.mini)
            .tint(tint)
        }
        .frame(width: 102)
    }
}

private struct OutputCeilingButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                Text("Ceiling")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)

                Text(isOn ? "On" : "Off")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(isOn ? AppColors.warning : AppColors.textMuted)
                    .monospacedDigit()
            }
            .frame(width: 78, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppColors.deepBlack.opacity(0.26))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isOn ? AppColors.warning.opacity(0.48) : AppColors.controlStrokeSoft.opacity(0.48), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(isOn ? "Disable output ceiling" : "Enable output ceiling")
    }
}

private struct OutputMeterSection: View {
    let level: Float
    let peakDBFS: Float
    let isActive: Bool

    private var peakText: String {
        guard isActive, peakDBFS > -90 else { return "-inf dB" }
        return String(format: "%.0f dB", peakDBFS)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("Output")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)

                Spacer(minLength: 8)

                Text(peakText)
                    .font(AppTypography.technical)
                    .foregroundColor(isActive ? AppColors.textSecondary : AppColors.textMuted)
                    .monospacedDigit()
            }

            OutputLevelBar(level: level, peakDBFS: peakDBFS, isActive: isActive)
        }
        .frame(width: 176, height: 32)
        .opacity(isActive ? 1 : 0.58)
        .help("Processed output level after Sonexis effects.")
    }
}

private struct OutputLevelBar: View {
    let level: Float
    let peakDBFS: Float
    let isActive: Bool

    private var normalizedLevel: CGFloat {
        normalized(linear: level)
    }

    private var normalizedPeak: CGFloat {
        guard peakDBFS > -90 else { return 0 }
        return CGFloat(min(max((Double(peakDBFS) + 60) / 60, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let levelWidth = max(isActive ? 2 : 0, width * normalizedLevel)
            let peakX = min(width - 1, max(0, width * normalizedPeak))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(AppColors.deepBlack.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(AppColors.controlStrokeSoft.opacity(0.72), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.neonCyan.opacity(isActive ? 0.92 : 0.28),
                                AppColors.neonPink.opacity(isActive ? 0.88 : 0.24)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: levelWidth)
                    .shadow(color: AppColors.neonCyan.opacity(isActive ? 0.22 : 0), radius: 5)

                if isActive {
                    Rectangle()
                        .fill(AppColors.textPrimary.opacity(0.68))
                        .frame(width: 1.2)
                        .offset(x: peakX)
                }
            }
        }
        .frame(height: 7)
    }

    private func normalized(linear: Float) -> CGFloat {
        let clamped = max(Double(linear), 0.000_001)
        let db = 20 * log10(clamped)
        return CGFloat(min(max((db + 60) / 60, 0), 1))
    }
}
