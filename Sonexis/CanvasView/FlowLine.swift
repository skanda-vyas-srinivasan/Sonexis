import SwiftUI
import AppKit

// MARK: - Flow Line

struct FlowLine: View {
    let from: CGPoint
    let to: CGPoint
    let isActive: Bool
    let level: Float
    let beatPulse: CGFloat
    let fps: Double
    let allowAnimation: Bool
    @State private var bounce: CGFloat = 0
    @State private var cachedPath: Path?

    var body: some View {
        let intensity = min(max(CGFloat(level) * 3.0, 0.0), 1.0)
        let baseOpacity = 0.25 + 0.6 * intensity
        let thickness: CGFloat = 3.5
        let path = cachedPath ?? makePath()
        Group {
            if isActive {
                ZStack {
                    path
                        .stroke(AppColors.wireActive.opacity(0.9), lineWidth: thickness + 2)
                        .blur(radius: 6)
                    path
                        .stroke(Color(hex: "#FF5FBF").opacity(0.45), lineWidth: thickness + 6)
                        .blur(radius: 14)
                    path
                        .stroke(AppColors.wireActive.opacity(baseOpacity), lineWidth: thickness)
                        .shadow(color: AppColors.wireActive.opacity(0.8), radius: 16)
                        .shadow(color: AppColors.wireActive.opacity(0.45), radius: 28)
                        .contentShape(path.strokedPath(.init(lineWidth: thickness + 10)))

                    if allowAnimation && fps > 0 {
                        TimelineView(.periodic(from: .now, by: 1.0 / max(fps, 1.0))) { context in
                            let time = context.date.timeIntervalSinceReferenceDate
                            let dx = to.x - from.x
                            let dy = to.y - from.y
                            let length = max(sqrt(dx * dx + dy * dy), 1)
                            let pixelsPerSecond: CGFloat = 90
                            let phaseSpeed = pixelsPerSecond / length
                            let phase = CGFloat((time * Double(phaseSpeed)).truncatingRemainder(dividingBy: 1.0))

                            MovingArrowheads(
                                from: from,
                                to: to,
                                color: AppColors.neonCyan.opacity(0.85),
                                phase: phase
                            )
                        }
                    } else {
                        MovingArrowheads(
                            from: from,
                            to: to,
                            color: AppColors.neonCyan.opacity(0.35),
                            phase: 0
                        )
                    }
                }
            } else {
                let inactiveOpacity = baseOpacity * 0.55
                ZStack {
                    path
                        .stroke(AppColors.wireActive.opacity(0.4), lineWidth: thickness + 2)
                        .blur(radius: 5)
                    path
                        .stroke(Color(hex: "#FF5FBF").opacity(0.2), lineWidth: thickness + 5)
                        .blur(radius: 12)
                    path
                        .stroke(AppColors.wireActive.opacity(inactiveOpacity), lineWidth: thickness)
                        .shadow(color: AppColors.wireActive.opacity(0.35), radius: 12)
                        .contentShape(path.strokedPath(.init(lineWidth: thickness + 10)))

                    MovingArrowheads(
                        from: from,
                        to: to,
                        color: AppColors.neonCyan.opacity(0.35),
                        phase: 0
                    )
                }
            }
        }
        .onAppear {
            cachedPath = makePath()
        }
        .onChange(of: from) { _ in
            cachedPath = makePath()
        }
        .onChange(of: to) { _ in
            cachedPath = makePath()
        }
    }

    private func makePath() -> Path {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
    }
}

struct WireKey: Hashable {
    let from: UUID
    let to: UUID
}

struct AutoWireSelection {
    let key: WireKey
    let midpoint: CGPoint
    let tint: Color
}

struct CanvasConnection: Identifiable {
    let id: UUID
    let fromNodeId: UUID
    let from: CGPoint
    let toNodeId: UUID
    let to: CGPoint
    let isManual: Bool
}

struct CustomContextMenu {
    struct Item {
        let title: String
        let role: ButtonRole?
        let action: () -> Void
    }

    let anchor: CGPoint
    let position: CGPoint
    let tint: Color
    let items: [Item]

    var size: CGSize {
        let rowHeight: CGFloat = 24
        let height = CGFloat(items.count) * rowHeight + 16
        return CGSize(width: 180, height: height)
    }
}

struct WindowFocusReader: NSViewRepresentable {
    let onFocusChange: (Bool) -> Void

    func makeNSView(context: Context) -> FocusView {
        let view = FocusView()
        view.onFocusChange = onFocusChange
        return view
    }

    func updateNSView(_ nsView: FocusView, context: Context) {
        nsView.onFocusChange = onFocusChange
        nsView.updateFocus()
    }

    final class FocusView: NSView {
        var onFocusChange: ((Bool) -> Void)?
        private var keyObserver: Any?
        private var resignObserver: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateFocus()
            if let window = window {
                keyObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.onFocusChange?(true)
                }
                resignObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.onFocusChange?(false)
                }
            }
        }

        func updateFocus() {
            onFocusChange?(window?.isKeyWindow ?? true)
        }

        deinit {
            if let keyObserver {
                NotificationCenter.default.removeObserver(keyObserver)
            }
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
            }
        }
    }
}

struct CustomContextMenuView: View {
    let menu: CustomContextMenu
    let onDismiss: () -> Void

    var body: some View {
        let itemFont = Font.system(size: 12, weight: .medium, design: .rounded)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(menu.items.enumerated()), id: \.offset) { index, item in
                Button(role: item.role) {
                    item.action()
                    onDismiss()
                } label: {
                    HStack {
                        Text(item.title)
                            .font(itemFont)
                            .foregroundColor(menu.tint)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < menu.items.count - 1 {
                    Divider()
                        .background(menu.tint.opacity(0.2))
                }
            }
        }
        .padding(8)
        .background(AppColors.deepBlack.opacity(0.88))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(menu.tint.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.25), radius: 6, y: 3)
        .fixedSize()
        .position(menu.position)
    }
}

struct GainPopoverView: View {
    let tint: Color
    let value: Binding<Double>
    let onDone: () -> Void

    var body: some View {
        let itemFont = Font.system(size: 12, weight: .medium, design: .rounded)
        VStack(spacing: 6) {
            Text("Gain")
                .font(itemFont)
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
            Slider(value: value, in: 0...1)
                .tint(tint)
                .controlSize(.mini)
                .frame(width: 160)
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.caption2)
                .monospacedDigit()
                .foregroundColor(tint.opacity(0.7))
                .frame(maxWidth: .infinity)
            Button("Done") {
                onDone()
            }
            .buttonStyle(.plain)
            .font(itemFont)
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .padding(8)
        .background(AppColors.deepBlack.opacity(0.88))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.25), radius: 6, y: 3)
        .fixedSize()
    }
}

struct RightClickCapture: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRightClick: onRightClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = RightClickView()
        view.onRightClick = context.coordinator.onRightClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator: NSObject {
        let onRightClick: (CGPoint) -> Void
        init(onRightClick: @escaping (CGPoint) -> Void) {
            self.onRightClick = onRightClick
        }
    }

    final class RightClickView: NSView {
        var onRightClick: ((CGPoint) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            if let type = NSApp.currentEvent?.type,
               type == .rightMouseDown || type == .rightMouseUp || type == .rightMouseDragged {
                return self
            }
            return nil
        }

        override func rightMouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            let adjusted = CGPoint(x: location.x, y: bounds.height - location.y)
            onRightClick?(adjusted)
        }
    }
}


struct AccentStyle {
    let fill: Color
    let fillDark: Color
    let highlight: Color
    let text: Color

    static let defaultPreview = AccentStyle(
        fill: Color(hex: "#8B3DFF"),
        fillDark: Color(hex: "#3A0B73"),
        highlight: Color(hex: "#00D9FF"),
        text: .white
    )
}

struct NeonTile: View {
    let isEnabled: Bool
    let style: AccentStyle
    let disabledFill: Color

    var body: some View {
        let coreFill: LinearGradient = isEnabled
            ? LinearGradient(
                colors: [
                    style.fillDark.opacity(0.35),
                    style.fillDark.opacity(0.75),
                    style.fillDark.opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [disabledFill, disabledFill.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        let edgeGlow = RadialGradient(
            colors: [
                style.fill.opacity(0.22),
                style.fill.opacity(0.08),
                Color.clear
            ],
            center: .center,
            startRadius: 70,
            endRadius: 150
        )

        let accentSheen = LinearGradient(
            colors: [
                Color.clear,
                style.highlight.opacity(0.75),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let accentStroke = LinearGradient(
            colors: [
                style.highlight.opacity(0.12),
                style.highlight.opacity(0.9),
                style.highlight.opacity(0.2)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let accentStrokeStyle = isEnabled
            ? AnyShapeStyle(accentStroke)
            : AnyShapeStyle(Color.clear)

        let shape = RoundedRectangle(cornerRadius: 22)

        return ZStack {
            shape.fill(coreFill)

            if isEnabled {
                shape
                    .fill(edgeGlow)
                    .blendMode(.screen)
            }

            shape
                .stroke(isEnabled ? style.fill.opacity(1.0) : disabledFill.opacity(0.6), lineWidth: 4)
                .shadow(color: isEnabled ? style.fill.opacity(0.95) : .clear, radius: 6)
                .shadow(color: isEnabled ? style.fill.opacity(0.6) : .clear, radius: 20)
                .shadow(color: isEnabled ? style.fill.opacity(0.3) : .clear, radius: 48)

            shape
                .stroke(isEnabled ? style.fill.opacity(0.7) : .clear, lineWidth: 10)
                .blur(radius: 12)
                .mask(
                    shape
                        .fill(Color.white)
                        .padding(6)
                )

            shape
                .stroke(accentStrokeStyle, lineWidth: 1.5)
                .blendMode(.screen)

            shape
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.screen)
                .padding(6)

            shape
                .fill(accentSheen)
                .rotationEffect(.degrees(-12))
                .blendMode(.screen)
                .opacity(isEnabled ? 0.9 : 0)
                .padding(10)
        }
    }
}

struct KeyEventCapture: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyCaptureView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }
    }
}

struct MovingArrowheads: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    let phase: CGFloat

    var body: some View {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(sqrt(dx * dx + dy * dy), 1)
        let spacing: CGFloat = 140
        let arrowSize: CGFloat = 6
        let steps = max(Int(length / spacing), 1)

        return ZStack {
            ForEach(0..<steps, id: \.self) { index in
                let base = CGFloat(index + 1) / CGFloat(steps + 1)
                let t = (base + phase).truncatingRemainder(dividingBy: 1.0)
                let point = CGPoint(x: from.x + dx * t, y: from.y + dy * t)
                let angle = atan2(dy, dx)

                Path { path in
                    let tip = point
                    let left = CGPoint(
                        x: tip.x - arrowSize * cos(angle - .pi / 6),
                        y: tip.y - arrowSize * sin(angle - .pi / 6)
                    )
                    let right = CGPoint(
                        x: tip.x - arrowSize * cos(angle + .pi / 6),
                        y: tip.y - arrowSize * sin(angle + .pi / 6)
                    )
                    path.move(to: left)
                    path.addLine(to: tip)
                    path.addLine(to: right)
                }
                .stroke(color, lineWidth: 1.5)
            }
        }
    }
}


