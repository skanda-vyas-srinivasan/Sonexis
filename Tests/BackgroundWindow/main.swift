import AppKit

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
// Exercise the actual controller with non-presenting windows: no audio engine,
// live capture, user workspace, or visible test windows.
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
final class TestWindow: NSWindow {
    var hideCount = 0
    var reopenCount = 0
    var deminiaturizeCount = 0
    var minimized = false
    override var isMiniaturized: Bool { minimized }
    override func orderOut(_ sender: Any?) { hideCount += 1 }
    override func makeKeyAndOrderFront(_ sender: Any?) { reopenCount += 1 }
    override func deminiaturize(_ sender: Any?) {
        deminiaturizeCount += 1
        minimized = false
    }
}
final class OriginalDelegate: NSObject, NSWindowDelegate {
    var quitCloseCount = 0
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        quitCloseCount += 1
        return true
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: 1234, height: 789)
    }
}
func makeWindow() -> TestWindow {
    TestWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.titled, .closable], backing: .buffered, defer: true)
}
let controller = EditorWindowController()
expect(!controller.reopen(), "Unattached controller claims to reopen")
let window = makeWindow()
let original = OriginalDelegate()
window.delegate = original
let content = NSView()
window.contentView = content
controller.attach(to: window)
controller.attach(to: window)
expect(window.delegate === controller, "Controller not installed")
let forwardedSize = window.delegate?.windowWillResize?(window, to: .zero)
expect(forwardedSize == NSSize(width: 1234, height: 789), "Original delegate resize callback lost")
var hideNotifications = 0
let observer = NotificationCenter.default.addObserver(forName: .sonexisEditorWillHide,
    object: window, queue: nil) { _ in hideNotifications += 1 }
for _ in 0..<3 {
    expect(!controller.windowShouldClose(window), "Close destroyed window")
    expect(controller.reopen(), "Reopen failed")
    expect(window.contentView === content && controller.window === window, "Reopen replaced editor state")
}
expect(hideNotifications == 3 && window.hideCount == 3, "Hide did not notify workspace persistence")
expect(window.reopenCount == 3 && original.quitCloseCount == 0, "Close incorrectly forwarded as teardown")
window.minimized = true
expect(controller.reopen() && window.deminiaturizeCount == 1, "Dock reopen did not unminimize")
controller.isQuitting = true
expect(controller.windowShouldClose(window), "Quit still hides instead of closing")
expect(original.quitCloseCount == 1 && hideNotifications == 3, "Quit intercepted as ordinary hide")
let replacement = makeWindow()
controller.attach(to: replacement)
expect(window.delegate === original, "Previous delegate not restored on detach")
NotificationCenter.default.removeObserver(observer)
print("PASS: hide versus quit, same window/content across reopen, workspace notification, minimized reopen, SwiftUI delegate forwarding, repeated attachment and detach")
