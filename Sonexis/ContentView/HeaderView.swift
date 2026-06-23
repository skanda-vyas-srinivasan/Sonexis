import SwiftUI
import AppKit

struct HeaderView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var tutorial: TutorialController
    let onSave: () -> Void
    let onLoad: () -> Void
    let onSaveAs: () -> Void
    let hasCurrentPreset: Bool
    let allowSave: Bool
    let allowLoad: Bool
    @Binding var saveStatusText: String?
    @Binding var showingAudioSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                let powerLockedByTutorial = tutorial.isActive && tutorial.step != .buildPower

                // Power button with status
                VStack(spacing: 4) {
                    Button(action: {
                        guard !powerLockedByTutorial else { return }

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
                    .disabled(powerLockedByTutorial)
                    .opacity(powerLockedByTutorial ? 0.45 : 1)
                    .help(powerLockedByTutorial ? "Power turns on later in the tutorial" : (audioEngine.isRunning ? "Stop Processing" : audioEngine.startHelpText))
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

                let recordDisabled = (!audioEngine.isRunning && !audioEngine.isRecording) || tutorial.isActive
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

                Divider()
                    .frame(height: 30)
                    .background(AppColors.controlStrokeSoft.opacity(0.65))

                AudioSettingsButton(isPresented: $showingAudioSettings)
                    .frame(width: 34, height: 28)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TutorialTargetPreferenceKey.self,
                                value: [.buildSettings: proxy.frame(in: .global)]
                            )
                        }
                    )

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
                           error.localizedCaseInsensitiveContains("Output") {
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
                        PresetSaveSplitButton(
                            tint: AppColors.neonPink,
                            isEnabled: allowSave,
                            hasCurrentPreset: hasCurrentPreset,
                            onSave: onSave,
                            onSaveAs: onSaveAs
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TutorialTargetPreferenceKey.self,
                                    value: [.buildSave: proxy.frame(in: .global)]
                                )
                            }
                        )

                        PresetToolbarButton(
                            title: "Load",
                            tint: AppColors.neonCyan,
                            isEnabled: allowLoad,
                            action: onLoad
                        )
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

        }
        .background(AppColors.panelPurple.opacity(0.84))
        .overlay(alignment: .bottom) {
            AppColors.controlStroke.opacity(0.42)
                .frame(height: 1)
        }
        .animation(.easeInOut(duration: 0.3), value: audioEngine.isRunning)
        .animation(.easeOut(duration: 0.16), value: showingAudioSettings)
        .zIndex(showingAudioSettings ? 20 : 0)
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

private struct PresetSaveSplitButton: View {
    let tint: Color
    let isEnabled: Bool
    let hasCurrentPreset: Bool
    let onSave: () -> Void
    let onSaveAs: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: hasCurrentPreset ? onSave : onSaveAs) {
                Text("Save")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary.opacity(0.94))
                    .padding(.leading, 10)
                    .padding(.trailing, 8)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(AppColors.controlStrokeSoft.opacity(isHovered ? 0.62 : 0.42))
                .frame(width: 1, height: 18)

            Menu {
                Button("Save As", action: onSaveAs)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? AppColors.controlPurpleRaised.opacity(0.72) : AppColors.controlPurple.opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHovered ? tint.opacity(0.44) : AppColors.controlStrokeSoft.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.42)
        .help(hasCurrentPreset ? "Save preset" : "Save as preset")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }
}

private struct PresetToolbarButton: View {
    let title: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textPrimary.opacity(0.94))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? AppColors.controlPurpleRaised.opacity(0.72) : AppColors.controlPurple.opacity(0.46))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isHovered ? tint.opacity(0.44) : AppColors.controlStrokeSoft.opacity(0.58), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.42)
        .help("\(title) preset")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }
}

private struct AudioSettingsButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isPresented.toggle()
            }
        } label: {
            Image(systemName: isPresented ? "gearshape.fill" : "gearshape")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppColors.neonCyan)
                .frame(width: 34, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isPresented ? "Close audio settings" : "Audio settings")
    }
}

struct AudioSettingsFloatingStrip: View {
    @Binding var trimDB: Double
    @Binding var makeupDB: Double
    @Binding var ceilingEnabled: Bool
    @Binding var selectedThemeID: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AudioSettingsInspectorSlider(
                title: "Tap In",
                valueText: String(format: "%.0f dB", trimDB),
                value: $trimDB,
                range: -30...0,
                step: 1,
                tint: AppColors.neonCyan
            )
            .frame(width: 122)

            AudioSettingsGroupDivider()

            AudioSettingsInspectorSlider(
                title: "Makeup",
                valueText: String(format: "%+.0f dB", makeupDB),
                value: $makeupDB,
                range: -12...30,
                step: 1,
                tint: AppColors.neonPink
            )
            .frame(width: 122)

            AudioSettingsGroupDivider()

            CeilingToggleRow(isOn: $ceilingEnabled)
                .fixedSize(horizontal: true, vertical: false)

            AudioSettingsGroupDivider()

            ThemeCompactPicker(selectedThemeID: $selectedThemeID)
                .frame(width: 156, alignment: .leading)
                .layoutPriority(1)

            AudioSettingsGroupDivider()

            Button {
                trimDB = ProcessTapRuntimeSettings.defaults.inputTrimDB
                makeupDB = ProcessTapRuntimeSettings.defaults.outputMakeupDB
                ceilingEnabled = ProcessTapRuntimeSettings.defaults.outputCeilingEnabled
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(AppColors.controlPurple.opacity(0.30))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Reset Tap In, Makeup, and Ceiling")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(AppColors.panelPurple)
        )
        .overlay(
            Rectangle()
                .stroke(AppColors.controlStrokeSoft.opacity(0.58), lineWidth: 1)
        )
        .shadow(color: AppColors.deepBlack.opacity(0.30), radius: 8, x: 0, y: 6)
    }
}

private struct AudioSettingsGroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.controlStrokeSoft.opacity(0.54))
            .frame(width: 1, height: 28)
    }
}

private struct AudioSettingsInspectorSlider: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)

                Spacer(minLength: 8)

                Text(valueText)
                    .font(AppTypography.paramValue)
                    .foregroundColor(tint)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        let steppedValue = (newValue / step).rounded() * step
                        value = min(max(steppedValue, range.lowerBound), range.upperBound)
                    }
                ),
                in: range
            )
            .controlSize(.small)
            .tint(tint)
        }
    }
}

private struct CeilingToggleRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("Ceiling")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(AppColors.warning)
        }
        .fixedSize(horizontal: true, vertical: false)
        .help(isOn ? "Disable output ceiling" : "Enable output ceiling")
    }
}

private struct ThemeCompactPicker: View {
    @Binding var selectedThemeID: String

    var body: some View {
        HStack(spacing: 7) {
            Text("Theme")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 4) {
                ForEach(AppTheme.allCases) { theme in
                    ThemeCompactButton(
                        theme: theme,
                        isSelected: selectedThemeID == theme.rawValue
                    ) {
                        selectedThemeID = theme.rawValue
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ThemeCompactButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    private var swatchColor: Color {
        switch theme {
        case .classic:
            return Color(hex: "#7209B7")
        case .magenta:
            return Color(hex: "#FF2DAA")
        case .black:
            return Color(hex: "#747789")
        case .gold:
            return Color(hex: "#FFD21F")
        }
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(swatchColor)
                .frame(width: 11, height: 11)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(theme == .black ? 0.36 : 0), lineWidth: 1)
                )
                .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? AppColors.controlPurpleRaised.opacity(0.56) : AppColors.controlPurple.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? swatchColor.opacity(0.58) : AppColors.controlStrokeSoft.opacity(0.38), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(theme.displayName)
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
                    .fill(AppColors.neonCyan.opacity(isActive ? 0.86 : 0.24))
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
