import AppKit
import Combine
import SwiftUI
struct ChainMenuBarPanel: View {
    @ObservedObject var workspace: ChainWorkspace
    let openChain: (UUID) -> Void
    let chooseRecordingURL: () -> URL?
    let close: () -> Void
    @State private var apps = AudioCaptureTarget.runningApps()
    @State private var hoveredChainID: UUID?
    @State private var hoveredToggleID: UUID?
    @State private var isAddChainHovered = false
    @State private var isQuitHovered = false
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultThemeID
    private var palette: AppColorPalette { AppTheme.theme(for: themeID).palette }
    private var availableApps: [AudioCaptureTarget] {
        apps.filter { app in !workspace.chains.contains { $0.target?.id == app.id } }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image("SonexisMark")
                    .renderingMode(.template).resizable().scaledToFit().frame(width: 27, height: 27)
                    .foregroundStyle(palette.neonPink)
                Spacer()
                MenuBarRecordingControl(
                    workspace: workspace,
                    palette: palette,
                    chooseRecordingURL: chooseRecordingURL
                )
                Rectangle().fill(palette.controlStrokeSoft).frame(width: 1, height: 24)
                Button { workspace.togglePower() } label: {
                    Group {
                        if workspace.runtime.isTransitioning && workspace.runtime.state != .running {
                            ProgressView().controlSize(.small).frame(width: 24, height: 24)
                        } else {
                            Image(systemName: workspace.runtime.state == .running ? "power.circle.fill" : "power.circle")
                        }
                    }
                    .font(.system(size: 24))
                    .foregroundStyle(workspace.runtime.state == .running ? palette.success : palette.textMuted)
                    .shadow(color: workspace.runtime.state == .running ? palette.success.opacity(0.18) : .clear, radius: 8)
                }
                .accessibilityLabel("Power")
                .accessibilityValue(workspace.runtime.isTransitioning ? "Pending" : (workspace.runtime.state == .running ? "On" : "Off"))
                .disabled(!workspace.tutorial.step.allowsPowerControl)
            }
            .frame(height: 38)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.controlStrokeSoft.opacity(0.62)).frame(height: 1)
            }
            .overlay(alignment: .bottomLeading) {
                Rectangle().fill(palette.neonPink.opacity(0.72)).frame(width: 38, height: 1)
            }
            .padding(.bottom, 6)
            if let instruction = workspace.tutorial.menuInstruction {
                Text(instruction)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(palette.controlPurple.opacity(0.38))
                    .overlay {
                        Rectangle()
                            .stroke(palette.controlStrokeSoft.opacity(0.72), lineWidth: 1)
                    }
            }
            ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(workspace.chains.enumerated()), id: \.element.id) { index, chain in
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Button { openChain(chain.id) } label: {
                                    HStack(spacing: 8) {
                                        MenuBarChainIcon(chain: chain, palette: palette)
                                        Text(workspace.name(for: chain))
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .layoutPriority(1)
                                            .foregroundStyle(hoveredChainID == chain.id ? palette.textPrimary : palette.textSecondary)
                                            .overlay(alignment: .bottomLeading) {
                                                if hoveredChainID == chain.id {
                                                    Rectangle()
                                                        .fill(palette.neonPink)
                                                        .frame(height: 1)
                                                        .offset(y: 2)
                                                }
                                            }
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minWidth: 132, maxWidth: .infinity, alignment: .leading)
                                    .frame(height: 52)
                                    .contentShape(Rectangle())
                                }
                                .disabled(!workspace.canOpenChainFromMenu(chain.id))
                                .onHover { hovering in
                                    hoveredChainID = hovering ? chain.id : (hoveredChainID == chain.id ? nil : hoveredChainID)
                                }
                                .menuBarTutorialHighlight(
                                    workspace.tutorial.step == .chainsOpenEditor &&
                                    workspace.tutorial.practiceChainID == chain.id
                                )
                                ChainPresetMenu(workspace: workspace, presets: workspace.presets, chain: chain)
                                Button { workspace.toggleEffects(chain.id) } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundStyle(hoveredToggleID == chain.id ? palette.neonPink :
                                            (chain.effectsEnabled && !workspace.runtime.globallyBypassed ? palette.neonCyan : palette.textMuted))
                                        .frame(width: 24, height: 24)
                                        .contentShape(Rectangle())
                                }
                                .onHover { hovering in hoveredToggleID = hovering ? chain.id : nil }
                                .opacity(hoveredToggleID == chain.id || !chain.effectsEnabled ? 1 : 0.72)
                                .disabled(!workspace.canToggleChain(chain.id))
                                .menuBarTutorialHighlight(
                                    [.chainsDisable, .chainsEnable].contains(workspace.tutorial.step) &&
                                    workspace.tutorial.practiceChainID == chain.id
                                )
                                .accessibilityLabel(chain.effectsEnabled ? "Disable \(workspace.name(for: chain)) chain" : "Enable \(workspace.name(for: chain)) chain")
                            }
                            .padding(.horizontal, 4)
                            .contextMenu {
                                Button("Remove Chain", role: .destructive) {
                                    workspace.remove(chain.id)
                                }
                                .disabled(!workspace.canRemoveChain(chain.id))
                            }
                            if index < workspace.chains.count - 1 {
                                Rectangle().fill(palette.controlStrokeSoft.opacity(0.48)).frame(height: 1)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .id(chain.id)
                    }
                }
            }
            .frame(height: min(max(CGFloat(workspace.chains.count), 1) * 56, 224))
            .scrollIndicators(.visible)
                .onAppear {
                    if workspace.tutorial.isActive, let id = workspace.tutorial.practiceChainID {
                        scroll.scrollTo(id, anchor: .center)
                    }
                }
            }
            if workspace.chains.count > 4 {
                HStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Scroll for more")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(palette.textMuted)
                .frame(height: 18)
            }
            Rectangle().fill(palette.controlStrokeSoft.opacity(0.72)).frame(height: 1)
            Menu {
                ForEach(availableApps) { app in
                    Button { workspace.add(app) } label: {
                        Label {
                            Text(app.name)
                        } icon: {
                            Image(nsImage: AppIconCache.shared.icon(for: app.bundlePath))
                        }
                    }
                }
                if availableApps.isEmpty {
                    Text("Open another app to add it")
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add App")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(isAddChainHovered ? palette.textPrimary : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 44, alignment: .center)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(palette.neonPink)
                        .frame(width: 58, height: 1)
                        .opacity(isAddChainHovered ? 1 : 0.22)
                        .offset(y: -7)
                }
                .contentShape(Rectangle())
                .background {
                    MenuBarHoverReader { hovering in
                        isAddChainHovered = hovering && workspace.canAddChain
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(!workspace.canAddChain)
            .padding(.vertical, 8)
            Rectangle().fill(palette.controlStrokeSoft.opacity(0.72)).frame(height: 1)
            HStack {
                if workspace.tutorial.isActive && workspace.tutorial.isAppChainTour {
                    Button("Exit tutorial") { workspace.tutorial.skipTutorial(); close() }
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button {
                    close()
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .foregroundStyle(isQuitHovered ? palette.textPrimary : palette.textSecondary)
                        .frame(width: 54, height: 28)
                        .overlay {
                            if isQuitHovered {
                                Rectangle()
                                    .fill(palette.neonPink.opacity(0.85))
                                    .frame(width: 24, height: 1)
                                    .offset(y: 11)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isQuitHovered = hovering
                    }
                }
            }.foregroundStyle(palette.textSecondary)
        }
        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(palette.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 360)
        .background {
            ZStack {
                palette.panelPurple
                MenuBarPanelTexture(palette: palette)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.controlStrokeSoft.opacity(0.78), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(palette.neonPink.opacity(0.78))
                .frame(width: 46, height: 1)
                .padding(.leading, 12)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            AppIconCache.shared.preload(apps.map(\.bundlePath))
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            let refreshed = AudioCaptureTarget.runningApps()
            if refreshed != apps {
                apps = refreshed
                AppIconCache.shared.preload(refreshed.map(\.bundlePath))
            }
        }
    }
}

private struct MenuBarRecordingControl: View {
    @ObservedObject var workspace: ChainWorkspace
    let palette: AppColorPalette
    let chooseRecordingURL: () -> URL?

    private var runtime: MultiChainAudioEngine { workspace.runtime }
    private var isDisabled: Bool {
        (runtime.state != .running && !runtime.isRecording) ||
        runtime.isFinalizingRecording || workspace.tutorial.isActive
    }

    var body: some View {
        Button(action: toggleRecording) {
            Group {
                if runtime.isFinalizingRecording {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                } else if runtime.isRecording {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(elapsedTime(at: context.date))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(palette.error)
                    .frame(minWidth: 58)
                    .frame(height: 28)
                } else {
                    Image(systemName: runtime.recordingWarningText == nil ? "record.circle" : "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(runtime.recordingWarningText == nil ? palette.neonPink : palette.warning)
                        .frame(width: 34, height: 28)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !runtime.isFinalizingRecording ? 0.38 : 1)
        .accessibilityLabel(runtime.isRecording ? "Stop Recording" : "Start Recording")
        .accessibilityValue(runtime.isFinalizingRecording ? "Finishing" : (runtime.isRecording ? "Recording" : "Stopped"))
    }

    private func toggleRecording() {
        if runtime.isRecording {
            runtime.stopRecording()
        } else if let url = chooseRecordingURL() {
            runtime.startRecording(url: url)
        }
    }

    private func elapsedTime(at date: Date) -> String {
        let elapsed = max(0, Int(date.timeIntervalSince(runtime.recordingStartedAt ?? date)))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

}

private struct MenuBarPanelTexture: View {
    let palette: AppColorPalette

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            let spacing: CGFloat = 28
            for x in stride(from: CGFloat(0), through: size.width, by: spacing) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat(0), through: size.height, by: spacing) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(palette.controlStrokeSoft.opacity(0.10)), lineWidth: 0.5)

            var upperWave = Path()
            upperWave.move(to: CGPoint(x: -12, y: size.height * 0.30))
            upperWave.addCurve(
                to: CGPoint(x: size.width + 12, y: size.height * 0.25),
                control1: CGPoint(x: size.width * 0.28, y: size.height * 0.20),
                control2: CGPoint(x: size.width * 0.64, y: size.height * 0.38)
            )
            context.stroke(upperWave, with: .color(palette.neonCyan.opacity(0.075)), lineWidth: 1)

            var lowerWave = Path()
            lowerWave.move(to: CGPoint(x: -12, y: size.height * 0.74))
            lowerWave.addCurve(
                to: CGPoint(x: size.width + 12, y: size.height * 0.79),
                control1: CGPoint(x: size.width * 0.34, y: size.height * 0.86),
                control2: CGPoint(x: size.width * 0.70, y: size.height * 0.66)
            )
            context.stroke(lowerWave, with: .color(palette.neonPink.opacity(0.065)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MenuBarChainIcon: View {
    let chain: AudioChainDefinition
    let palette: AppColorPalette

    var body: some View {
        ZStack {
            Rectangle()
                .fill(palette.controlPurple.opacity(0.42))
                .frame(width: 28, height: 28)
                .overlay {
                    Rectangle().stroke(palette.controlStrokeSoft.opacity(0.52), lineWidth: 1)
            }
            if let target = chain.target {
                Image(nsImage: AppIconCache.shared.icon(for: target.bundlePath))
                    .renderingMode(.original)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.neonCyan)
            }
        }
        .frame(width: 28, height: 28)
    }
}

final class AppIconCache {
    static let shared = AppIconCache()
    private var icons: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    func preload(_ paths: [String]) {
        for path in Set(paths) where icons[path] == nil {
            icons[path] = NSWorkspace.shared.icon(forFile: path)
        }
    }
}

/// AppKit tracking remains stable when SwiftUI `Menu` temporarily moves focus
/// into its native menu window. It observes hover without intercepting clicks.
private struct MenuBarHoverReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var area: NSTrackingArea?
        private var isHovering = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let next = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(next)
            area = next
        }

        override func mouseEntered(with event: NSEvent) { setHovering(true) }
        override func mouseExited(with event: NSEvent) { setHovering(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func setHovering(_ hovering: Bool) {
            guard hovering != isHovering else { return }
            isHovering = hovering
            onChange?(hovering)
        }
    }
}


private struct ChainPresetMenu: View {
    @ObservedObject var workspace: ChainWorkspace
    @ObservedObject var presets: PresetManager
    let chain: AudioChainDefinition
    @State private var isHovered = false

    private var preset: SavedPreset? { presets.presets.first { $0.id == chain.presetID } }
    private var isTutorialTarget: Bool {
        workspace.tutorial.step == .chainsChoosePreset && workspace.tutorial.practiceChainID == chain.id
    }

    var body: some View {
        Menu {
            ForEach(presets.presets) { preset in
                Button {
                    workspace.loadPreset(preset, chainID: chain.id)
                } label: {
                    if chain.presetID == preset.id {
                        Label(preset.name, systemImage: "checkmark")
                    } else {
                        Text(preset.name)
                    }
                }
            }
            if presets.presets.isEmpty { Text("No saved presets") }
        } label: {
            HStack(spacing: 6) {
                Text(preset?.name ?? "Choose preset")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .overlay(alignment: .bottomLeading) {
                        Rectangle()
                            .fill(AppColors.neonPink)
                            .frame(height: 1)
                            .opacity(isHovered ? 1 : 0)
                            .offset(y: 2)
                    }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppColors.neonPink)
                    .allowsHitTesting(false)
                    .offset(x: isHovered ? 1 : 0)
            }
            .foregroundStyle(preset == nil && !isTutorialTarget ? AppColors.textMuted : AppColors.textPrimary)
            .padding(.horizontal, 4)
            .frame(width: 156, height: 30, alignment: .trailing)
            .background(isHovered ? AppColors.controlPurple.opacity(0.45) : Color.clear)
            .contentShape(Rectangle())
            .background {
                MenuBarHoverReader { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHovered = hovering
                    }
                }
            }
        }
        .buttonStyle(.plain).menuIndicator(.hidden)
        .disabled(!workspace.canLoadPreset(into: chain.id))
        .menuBarTutorialHighlight(isTutorialTarget)
        .accessibilityLabel("Preset for \(workspace.name(for: chain))")
    }
}

private extension View {
    func menuBarTutorialHighlight(_ isHighlighted: Bool) -> some View {
        overlay {
            if isHighlighted {
                Rectangle()
                    .stroke(AppColors.neonCyan.opacity(0.8), lineWidth: 1.25)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
    }
}
