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
                                    Text("Modified")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(AppColors.warning)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                if hasCurrentPreset {
                                    PresetUnlinkButton(
                                        isEnabled: !tutorial.isActive,
                                        action: onUnlinkPreset
                                    )
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
