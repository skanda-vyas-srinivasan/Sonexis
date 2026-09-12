import AppKit
import SwiftUI

/// Owns only the status item and floating panel; audio remains editor-owned.
final class MenuBarController: NSObject, ObservableObject, NSWindowDelegate {
    var onOpen: (() -> Void)?
    private var statusItem: NSStatusItem?
    private var panel: MenuBarFloatingPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var makeContent: (() -> AnyView)?

    func install(content: @escaping () -> AnyView) {
        makeContent = content
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let mark = NSImage(named: "SonexisMark")?.copy() as? NSImage
        mark?.size = NSSize(width: 18, height: 18)
        mark?.accessibilityDescription = "Sonexis"
        item.button?.image = mark
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            close()
            return
        }
        guard let makeContent else { return }
        let panel = MenuBarFloatingPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.close() }
        let content = makeContent()
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { [weak self] in self?.resize(to: proxy.size) }
                    .onChange(of: proxy.size) { [weak self] size in self?.resize(to: size) }
            })
        let hosting = NSHostingView(rootView: content)
        panel.contentView = hosting
        self.panel = panel
        // Position while hidden; deferring this until the next run loop flashes
        // the new window at the screen origin before it reaches the status item.
        guard position(panel, size: hosting.fittingSize) else {
            self.panel = nil
            return
        }
        panel.makeKeyAndOrderFront(nil)
        onOpen?()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel && event.window !== self.statusItem?.button?.window {
                self.close()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func resize(to size: CGSize) {
        guard let panel else { return }
        // Only subsequent layout updates are deferred. Ignore updates belonging
        // to a dismissed panel if another panel has since been opened.
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel else { return }
            _ = self.position(panel, size: size)
        }
    }

    private func position(_ panel: NSPanel, size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0,
              let button = statusItem?.button, let window = button.window else { return false }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? anchor
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        let frame = NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: panel.isVisible) }
        return true
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    func close() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        let previous = panel
        panel = nil
        previous?.orderOut(nil)
    }
}

private final class MenuBarFloatingPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

struct SonexisMenuBarPanel: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var presetManager: PresetManager
    @Binding var currentPresetID: UUID?
    let loadPreset: (SavedPreset) -> Void
    let openEditor: () -> Void
    let close: () -> Void
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultThemeID
    @State private var showsPresets = false
    @State private var isQuitHovered = false

    private var palette: AppColorPalette { AppTheme.theme(for: themeID).palette }
    private var presetName: String {
        presetManager.presets.first { $0.id == currentPresetID }?.name ?? "Choose preset"
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image("SonexisMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(palette.neonPink)
                    .accessibilityHidden(true)
                Spacer()
                Button {
                    if audioEngine.isRunning {
                        audioEngine.stop()
                    } else {
                        audioEngine.start()
                        if !audioEngine.isRunning {
                            close()
                            openEditor()
                        }
                    }
                } label: {
                    Image(systemName: audioEngine.isRunning ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(audioEngine.isRunning ? palette.success : palette.textMuted)
                        .shadow(color: audioEngine.isRunning ? palette.success.opacity(0.18) : .clear, radius: 8)
                        .frame(width: 34, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(audioEngine.isRunning ? "Stop Processing" : "Start Processing")

                Rectangle().fill(palette.controlStrokeSoft).frame(width: 1, height: 24)

                Button {
                    audioEngine.processingEnabled.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18))
                        .foregroundStyle(audioEngine.processingEnabled ? palette.neonCyan : palette.textMuted)
                        .frame(width: 34, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(audioEngine.processingEnabled ? "Disable Effects" : "Enable Effects")

            }

            VStack(spacing: 6) {
                Button {
                    showsPresets.toggle()
                } label: {
                    HStack {
                        Text(presetName).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Image(systemName: showsPresets ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.neonPink)
                    }
                    .padding(10)
                    .background(palette.controlPurple, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(presetManager.presets.isEmpty)

                if showsPresets && !presetManager.presets.isEmpty {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(presetManager.presets) { preset in
                                Button {
                                    loadPreset(preset)
                                    showsPresets = false
                                } label: {
                                    HStack {
                                        Text(preset.name).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 8)
                                        if currentPresetID == preset.id {
                                            Image(systemName: "checkmark").foregroundStyle(palette.neonCyan)
                                        }
                                    }
                                    .padding(9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(currentPresetID == preset.id ? palette.controlPurple : .clear,
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(presetManager.presets.count) * 36, 180))
                }
            }
            Rectangle().fill(palette.controlStrokeSoft).frame(height: 1)
            HStack {
                Button("Open") {
                    close()
                    openEditor()
                }
                .foregroundStyle(palette.textSecondary)
                Spacer()
                Button("Quit") {
                    close()
                    NSApp.terminate(nil)
                }
                .foregroundStyle(isQuitHovered ? palette.neonPink : palette.textSecondary)
                .onHover { isQuitHovered = $0 }
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12))
        .foregroundStyle(palette.textPrimary)
        .padding(16)
        .frame(width: 280)
        .background(palette.panelPurple)
        .preferredColorScheme(.dark)
    }
}
