import AppKit
import SwiftUI

extension Notification.Name {
    static let sonexisEditorWillHide = Notification.Name("Sonexis.editorWillHide")
}

/// Keep the SwiftUI window and its engine alive when the editor is closed.
/// Forward other delegate methods to SwiftUI's existing window delegate.
final class EditorWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private var originalDelegate: NSWindowDelegate?
    var isQuitting = false

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        if let previous = self.window, previous.delegate === self {
            previous.delegate = originalDelegate
        }
        self.window = window
        originalDelegate = window.delegate
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isQuitting else {
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }
        NotificationCenter.default.post(name: .sonexisEditorWillHide, object: sender)
        sender.orderOut(nil)
        return false
    }

    @discardableResult
    func reopen() -> Bool {
        guard let window else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if originalDelegate?.responds(to: selector) == true { return originalDelegate }
        return super.forwardingTarget(for: selector)
    }
}

/// Register the actual editor window without replacing SwiftUI's content or
/// rebuilding its StateObjects when the Dock is clicked.
struct EditorWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window { onWindow(window) }
    }

    final class WindowView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
