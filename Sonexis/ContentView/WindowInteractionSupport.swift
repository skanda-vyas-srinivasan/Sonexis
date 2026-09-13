import SwiftUI
import AppKit

struct ScreenFrameReader: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> ScreenFrameReportingView {
        let view = ScreenFrameReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ScreenFrameReportingView, context: Context) {
        nsView.onChange = onChange
        nsView.scheduleReport()
    }
}
final class ScreenFrameReportingView: NSView {
    var onChange: ((CGRect) -> Void)?
    private var lastFrame: CGRect = .zero

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleReport()
    }

    override func layout() {
        super.layout()
        scheduleReport()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleReport()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        scheduleReport()
    }

    func scheduleReport() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            let rectInWindow = self.convert(self.bounds, to: nil)
            guard rectInWindow.width > 1, rectInWindow.height > 1 else { return }
            if self.lastFrame != rectInWindow {
                self.lastFrame = rectInWindow
                self.onChange?(rectInWindow)
            }
        }
    }
}

final class AudioSettingsOutsideClickCoordinator: ObservableObject {
    var panelFrame: CGRect = .zero
    private var monitor: Any?

    func start(onDismiss: @escaping () -> Void) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.panelFrame.width > 1, self.panelFrame.height > 1 else { return event }

            var clickPoints = [event.locationInWindow]
            if let contentHeight = event.window?.contentView?.bounds.height {
                clickPoints.append(
                    CGPoint(
                        x: event.locationInWindow.x,
                        y: contentHeight - event.locationInWindow.y
                    )
                )
            }

            let expandedPanelFrame = self.panelFrame.insetBy(dx: -16, dy: -16)
            if clickPoints.contains(where: { expandedPanelFrame.contains($0) }) {
                return event
            }

            DispatchQueue.main.async {
                onDismiss()
            }
            return nil
        }
    }

    func stop() {
        panelFrame = .zero
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stop()
    }
}
