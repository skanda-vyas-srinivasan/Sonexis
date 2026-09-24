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
    private var dismissalSuspended = false

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
            if self.shouldDismiss(for: event) {
                self.close()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard self?.dismissalSuspended == false else { return }
            self?.close()
        }
    }

    private func shouldDismiss(for event: NSEvent) -> Bool {
        if dismissalSuspended { return false }
        guard let eventWindow = event.window else { return true }
        if eventWindow === panel || eventWindow === statusItem?.button?.window { return false }
        // SwiftUI Menu presents an AppKit menu window. Closing the parent panel
        // during that window's mouse-down cancels or duplicates the menu action.
        return eventWindow.level.rawValue < NSWindow.Level.popUpMenu.rawValue
    }

    /// Runs Sonexis-owned file panels without letting either event monitor
    /// dismiss the menu, then returns keyboard focus to the same menu panel.
    func promptForRecordingURL() -> URL? {
        guard let owner = panel, owner.isVisible else { return nil }
        let savePanel = NSSavePanel()
        savePanel.title = "Save Recording"
        savePanel.nameFieldStringValue = "Sonexis Recording.wav"
        savePanel.allowedFileTypes = ["wav"]
        savePanel.canCreateDirectories = true

        dismissalSuspended = true
        defer {
            dismissalSuspended = false
            if panel === owner, owner.isVisible {
                owner.makeKeyAndOrderFront(nil)
            }
        }
        return savePanel.runModal() == .OK ? savePanel.url : nil
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

    func close() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        dismissalSuspended = false
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
