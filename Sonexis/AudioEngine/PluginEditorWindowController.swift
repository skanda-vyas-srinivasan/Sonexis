import AppKit
import Foundation

final class PluginEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = PluginEditorWindowController()
    private var windows: [UUID: NSWindowController] = [:]

    func closeWindow(for nodeId: UUID) {
        let controller = windows.removeValue(forKey: nodeId)
        controller?.close()
    }

    func showExistingWindow(for nodeId: UUID) -> Bool {
        if let controller = windows[nodeId], let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            return true
        }
        return false
    }

    func openWindow(for nodeId: UUID, title: String, contentView: NSView) {
        if let controller = windows[nodeId], let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(nodeId.uuidString)
        window.delegate = self
        window.center()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        if contentView.superview != nil {
            contentView.removeFromSuperview()
        }
        container.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        window.contentView = container

        let controller = NSWindowController(window: window)
        windows[nodeId] = controller
        controller.showWindow(nil)
    }

    func openWindow(for nodeId: UUID, title: String, contentController: NSViewController) {
        if let controller = windows[nodeId], let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(nodeId.uuidString)
        window.delegate = self
        window.center()
        window.contentViewController = contentController

        let controller = NSWindowController(window: window)
        windows[nodeId] = controller
        controller.showWindow(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
