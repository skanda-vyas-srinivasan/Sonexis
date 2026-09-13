import SwiftUI
import AppKit

struct TutorialArrowKeyHandler: NSViewRepresentable {
    let isEnabled: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeNSView(context: Context) -> KeyMonitorView { KeyMonitorView() }

    func updateNSView(_ view: KeyMonitorView, context: Context) {
        view.isEnabled = isEnabled
        view.onPrevious = onPrevious
        view.onNext = onNext
    }

    static func dismantleNSView(_ view: KeyMonitorView, coordinator: ()) { view.stop() }

    final class KeyMonitorView: NSView {
        var isEnabled = false
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled, let window = self.window,
                      event.window === window, window.isKeyWindow, window.attachedSheet == nil,
                      !event.isARepeat, [123, 124].contains(event.keyCode),
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
                // Never take arrows from a focused slider, knob, text field,
                // native menu, or other control. The canvas capture is non-editing.
                let responder = window.firstResponder
                guard responder == nil || responder === window || responder === window.contentView ||
                      responder is KeyEventCapture.KeyCaptureView else { return event }
                if event.keyCode == 123 { self.onPrevious?() } else { self.onNext?() }
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stop() }
    }
}

struct ReverbScrollHint: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .bold))
            Text("Scroll for Reverb")
                .font(AppTypography.caption.weight(.semibold))
        }
        .foregroundColor(AppColors.neonCyan)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.deepBlack.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.neonCyan.opacity(0.24), lineWidth: 1)
        )
    }
}

struct SkipTutorialConfirm: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Exit Tutorial?")
                .font(AppTypography.heading)
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("You can always restart it from the Home screen.")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 10) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .tint(AppColors.textSecondary)

                Button("Exit") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.neonPink)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.midPurple.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.neonPink.opacity(0.6), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 6)
        .frame(maxWidth: 320)
    }
}
