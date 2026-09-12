import SwiftUI
import AppKit

struct HeaderView<SettingsOverlay: View>: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var runtime: MultiChainAudioEngine
    @ObservedObject var tutorial: TutorialController
    let onSave: () -> Void
    let onLoad: () -> Void
    let onSaveAs: () -> Void
    let onUnlinkPreset: () -> Void
    let hasCurrentPreset: Bool
    let presetDisplayName: String?
    let isPresetModified: Bool
    let allowSave: Bool
    let allowLoad: Bool
    @Binding var saveStatusText: String?
    @Binding var showingAudioSettings: Bool
    @ViewBuilder let settingsOverlay: () -> SettingsOverlay

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                let powerLockedByTutorial = !tutorial.step.allowsPowerControl

                // Power button with status
                VStack(spacing: 4) {
                    Button(action: {
                        guard !powerLockedByTutorial else { return }

                        if audioEngine.isRunning || audioEngine.isPowerTransitioning {
                            audioEngine.stop()
                        } else {
                            audioEngine.start()
                            if audioEngine.isRunning { tutorial.advanceIf(.buildPower) }
                        }
                    }) {
                        Group {
                            if audioEngine.isPowerTransitioning {
                                ProgressView().controlSize(.small).frame(width: 24, height: 24)
                            } else {
                                Image(systemName: audioEngine.isRunning ? "power.circle.fill" : "power.circle")
                            }
                        }
                            .font(.system(size: 24))
                            .foregroundColor(audioEngine.isRunning ? AppColors.success : AppColors.textMuted)
                            .shadow(color: audioEngine.isRunning ? AppColors.success.opacity(0.18) : .clear, radius: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Power")
                    .accessibilityValue(audioEngine.isPowerTransitioning ? "Pending" : (audioEngine.isRunning ? "On" : "Off"))
                    .disabled(powerLockedByTutorial)
                    .onChange(of: tutorial.step) { step in
                        if step == .buildPower && audioEngine.isRunning { tutorial.advanceIf(.buildPower) }
                    }
                    .onChange(of: audioEngine.isRunning) { running in
                        if running { tutorial.advanceIf(.buildPower) }
                    }
                    .opacity(powerLockedByTutorial ? 0.45 : 1)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TutorialTargetPreferenceKey.self,
                                value: [.buildPower: proxy.frame(in: .global)]
                            )
                        }
                    )

                }

                Divider()
                    .frame(height: 30)
                    .background(AppColors.controlStrokeSoft.opacity(0.65))

                // FX bypass
                Button(action: {
                    if let toggle = audioEngine.onEffectsToggle { toggle() }
                    else { audioEngine.processingEnabled.toggle() }
                }) {
                    Image(systemName: audioEngine.processingEnabled ? "slider.horizontal.3" : "slider.horizontal.3")
                        .font(.system(size: 18))
                        .foregroundColor(audioEngine.processingEnabled ? AppColors.neonCyan : AppColors.textMuted)
                        .frame(width: 34, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(audioEngine.globalBypassActive || tutorial.isActive)
                .tutorialTarget(.chainBypass)

                Divider()
                    .frame(height: 30)
                    .background(AppColors.controlStrokeSoft.opacity(0.65))

                let recordDisabled = (!audioEngine.isRunning && !runtime.isRecording) || runtime.isFinalizingRecording || tutorial.isActive
                Button(action: {
                    if runtime.isRecording {
                        runtime.stopRecording()
                    } else if let url = promptForRecordingURL() {
                        runtime.startRecording(url: url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: runtime.recordingWarningText == nil ? "circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(runtime.recordingWarningText != nil ? AppColors.warning : (runtime.isRecording ? AppColors.error : AppColors.textMuted))
                            .frame(width: 10, height: 10)
                        Text(runtime.isFinalizingRecording ? "Finishing…" : (runtime.isRecording ? "Recording" : "Record"))
                            .font(AppTypography.caption)
                            .foregroundColor(runtime.isRecording ? AppColors.error : AppColors.textSecondary)
                    }
                    .frame(width: 108, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(recordDisabled)
                .opacity(recordDisabled ? 0.4 : 1.0)
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
                    .disabled(tutorial.isActive && tutorial.step != .buildSettings)
                    .frame(width: 34, height: 28)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TutorialTargetPreferenceKey.self,
                                value: [.buildSettings: proxy.frame(in: .global)]
                            )
                        }
                    )
                    .overlay(alignment: .bottomLeading) {
                        settingsOverlay()
                            .frame(width: 640)
                            // Put the panel's top edge directly beneath the gear.
                            .alignmentGuide(.bottom) { dimensions in
                                dimensions[.top]
                            }
                    }
                    .zIndex(30)

                if audioEngine.onPowerStart == nil {
                    CaptureTargetMenu(audioEngine: audioEngine)
                        .disabled(tutorial.isActive)
                }

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

                Spacer(minLength: 16)

                // Keep preset identity beside Save/Load, sized to its text.
                // Only height is fixed; Modified does not steal a fixed name allowance.
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(presetDisplayName == nil ? "" : "PRESET")
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1)
                                .foregroundColor(AppColors.textMuted)
                                .frame(height: 12)
                                .accessibilityHidden(presetDisplayName == nil)

                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(presetDisplayName ?? saveStatusText ?? "")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(AppColors.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if presetDisplayName != nil && isPresetModified {
                                    Text("· Modified")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(AppColors.warning)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            .frame(height: 18)
                            .accessibilityHidden(presetDisplayName == nil && saveStatusText == nil)
                        }
                        .id(presetDisplayName)
                        .transition(.opacity)
                    }
                    .frame(height: 32, alignment: .leading)
                    .layoutPriority(1)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if hasCurrentPreset {
                            Button("Unlink preset", action: onUnlinkPreset)
                                .disabled(tutorial.isActive)
                        }
                    }
                    .animation(.easeOut(duration: 0.22), value: presetDisplayName)

                    if hasCurrentPreset {
                        PresetUnlinkButton(
                            isEnabled: !tutorial.isActive,
                            action: onUnlinkPreset
                        )
                    }

                    Divider()
                        .frame(height: 26)
                        .opacity(presetDisplayName != nil || saveStatusText != nil ? 1 : 0)

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


                }
            }
            .lineLimit(1)
            .padding()

        }
        .background(AppColors.panelPurple.opacity(0.84))
        // Keep the separator behind descendant overlays such as Save As.
        .background(alignment: .bottom) {
            AppColors.controlStroke.opacity(0.42)
                .frame(height: 1)
        }
        .animation(.easeInOut(duration: 0.3), value: audioEngine.isRunning)
        .animation(.easeOut(duration: 0.16), value: showingAudioSettings)
        .zIndex(20)
        // Present from the enabled header container. Attaching this sheet to
        // the Record button made its contents inherit the button's disabled
        // state after recording stopped, so neither action could be clicked.
        .sonexisDialog("Recording incomplete",
            message: runtime.recordingWarningText ?? "The recording may contain gaps.",
            tone: .warning,
            isPresented: $runtime.recordingIssuePresented,
            actions: recordingIssueActions
        )
    }

    private var recordingIssueActions: [SonexisDialogAction] {
        var actions: [SonexisDialogAction] = []
        if let url = runtime.lastRecordingURL {
            actions.append(SonexisDialogAction("Show File") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            })
        }
        actions.append(SonexisDialogAction("OK", role: .primary) {})
        return actions
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

private struct PresetUnlinkButton: View {
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "link.slash")
                    .font(.system(size: 10, weight: .semibold))
                Text("Unlink")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isHovered ? AppColors.neonPink : AppColors.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(isHovered ? AppColors.controlPurpleRaised.opacity(0.52) : AppColors.controlPurple.opacity(0.24))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppColors.neonPink)
                    .frame(height: 1)
                    .opacity(isHovered ? 1 : 0.34)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel("Unlink current preset")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

private struct PresetSaveSplitButton: View {
    let tint: Color
    let isEnabled: Bool
    let hasCurrentPreset: Bool
    let onSave: () -> Void
    let onSaveAs: () -> Void
    @State private var isHovered = false
    @State private var isMenuPresented = false
    @State private var isItemHovered = false
    @StateObject private var menuEvents = PresetMenuEvents()

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                isMenuPresented = false
                if hasCurrentPreset { onSave() } else { onSaveAs() }
            }) {
                Text("Save")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary.opacity(0.94))
                    .padding(.leading, 10)
                    .padding(.trailing, 8)
                    .frame(width: 46, height: 30)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(AppColors.controlStrokeSoft.opacity(isHovered ? 0.62 : 0.42))
                .frame(width: 1, height: 18)

            Button {
                isMenuPresented.toggle()
            } label: {
                Image(systemName: isMenuPresented ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save options")
            .accessibilityValue(isMenuPresented ? "Expanded" : "Collapsed")
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
        .background(PresetMenuRegion(events: menuEvents, isAnchor: true))
        .overlay(alignment: .topLeading) {
            GeometryReader { anchor in
                if isMenuPresented {
                    Button(action: chooseSaveAs) {
                        HStack {
                            Text("Save As")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(isItemHovered ? AppColors.controlPurpleRaised : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isItemHovered = $0 }
                    .padding(5)
                    .frame(width: anchor.size.width)
                    .background(AppColors.panelPurple)
                    .sonexisFloatingPanel(tint: tint, cornerRadius: 8, glowOpacity: 0)
                    .background(PresetMenuRegion(events: menuEvents, isAnchor: false))
                    .offset(y: 36)
                    .onAppear {
                        menuEvents.start(onDismiss: { isMenuPresented = false }, onSelect: chooseSaveAs)
                    }
                    .onDisappear {
                        menuEvents.stop()
                        isItemHovered = false
                    }
                }
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { isMenuPresented = false }
        }
        .onDisappear { menuEvents.stop() }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.42)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }

    private func chooseSaveAs() {
        isMenuPresented = false
        onSaveAs()
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
                .frame(minWidth: 48, minHeight: 30)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
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
    }
}

struct AudioSettingsToolbarStrip: View {
    @Binding var trimDB: Double
    @Binding var makeupDB: Double
    @Binding var ceilingEnabled: Bool
    @Binding var selectedThemeID: String
    let isReadOnly: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AudioSettingsInspectorSlider(
                title: "Input Gain",
                valueText: String(format: "%.0f dB", trimDB),
                value: $trimDB,
                range: -30...0,
                step: 1,
                tint: AppColors.neonCyan
            )
            .frame(width: 136)
            .tutorialTarget(.inputGain)
            .disabled(isReadOnly)

            AudioSettingsGroupDivider()

            AudioSettingsInspectorSlider(
                title: "Output Gain",
                valueText: String(format: "%+.0f dB", makeupDB),
                value: $makeupDB,
                range: -12...30,
                step: 1,
                tint: AppColors.neonPink
            )
            .frame(width: 136)
            .tutorialTarget(.outputGain)
            .disabled(isReadOnly)

            AudioSettingsGroupDivider()

            CeilingToggleRow(isOn: $ceilingEnabled)
                .tutorialTarget(.ceiling)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(isReadOnly)

            AudioSettingsGroupDivider()

            ThemeCompactPicker(selectedThemeID: $selectedThemeID)
                .frame(width: 156, alignment: .leading)
                .layoutPriority(1)
                .disabled(isReadOnly)

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
            .disabled(isReadOnly)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.panelPurple)
        .overlay {
            Rectangle()
                .stroke(AppColors.controlStrokeSoft.opacity(0.58), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .tutorialTarget(.settingsStrip)
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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                Text(valueText)
                    .font(AppTypography.paramValue)
                    .foregroundColor(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
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

// Track actual view regions so outside-click dismissal works with either window
// coordinate orientation and does not steal clicks inside the dropdown.
private final class PresetMenuEvents: ObservableObject {
    weak var anchor: NSView?
    weak var menu: NSView?
    private var monitor: Any?

    func start(onDismiss: @escaping () -> Void, onSelect: @escaping () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                guard event.window === self.anchor?.window else {
                    onDismiss()
                    return event
                }
                switch event.keyCode {
                case 53, 48: // Escape / Tab dismiss; let Tab continue navigation.
                    onDismiss()
                    return event.keyCode == 48 ? event : nil
                case 36, 76, 49: // Return / keypad Enter / Space activate the only item.
                    onSelect()
                    return nil
                case 125, 126: // A one-item menu has no alternate selection.
                    return nil
                default:
                    onDismiss()
                    return event
                }
            }
            let inside = [self.anchor, self.menu].compactMap { $0 }.contains { view in
                view.window === event.window && view.bounds.contains(view.convert(event.locationInWindow, from: nil))
            }
            if !inside { onDismiss() }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }
}

private struct PresetMenuRegion: NSViewRepresentable {
    let events: PresetMenuEvents
    let isAnchor: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        if isAnchor { events.anchor = view } else { events.menu = view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
