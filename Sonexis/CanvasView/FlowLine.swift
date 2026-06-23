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
    let fromEndpointSize: CGSize
    let toEndpointSize: CGSize
    let endpointClearance: CGFloat = 0

    var body: some View {
        let intensity = min(max(CGFloat(level) * 3.0, 0.0), 1.0)
        let baseOpacity = 0.25 + 0.6 * intensity
        let thickness: CGFloat = 3.5
        let segment = visibleSegment()
        let path = makePath(from: segment.from, to: segment.to)
        Group {
            if isActive {
                ZStack {
                    path
                        .stroke(AppColors.wireActive.opacity(0.62), lineWidth: thickness + 2)
                        .blur(radius: 5)
                    path
                        .stroke(Color(hex: "#FF5FBF").opacity(0.24), lineWidth: thickness + 5)
                        .blur(radius: 12)
                    path
                        .stroke(AppColors.wireActive.opacity(baseOpacity), lineWidth: thickness)
                        .shadow(color: AppColors.wireActive.opacity(0.48), radius: 12)
                        .shadow(color: AppColors.wireActive.opacity(0.24), radius: 22)
                        .contentShape(path.strokedPath(.init(lineWidth: thickness + 10)))

                    if allowAnimation && fps > 0 {
                        TimelineView(.periodic(from: .now, by: 1.0 / max(fps, 1.0))) { context in
                            let time = context.date.timeIntervalSinceReferenceDate
                            let dx = segment.to.x - segment.from.x
                            let dy = segment.to.y - segment.from.y
                            let length = max(sqrt(dx * dx + dy * dy), 1)
                            let pixelsPerSecond: CGFloat = 90
                            let phaseSpeed = pixelsPerSecond / length
                            let phase = CGFloat((time * Double(phaseSpeed)).truncatingRemainder(dividingBy: 1.0))

                            MovingArrowheads(
                                from: segment.from,
                                to: segment.to,
                                color: AppColors.neonCyan.opacity(0.85),
                                phase: phase
                            )
                        }
                    } else {
                        MovingArrowheads(
                            from: segment.from,
                            to: segment.to,
                            color: AppColors.neonCyan.opacity(0.35),
                            phase: 0
                        )
                    }
                }
            } else {
                let inactiveOpacity = baseOpacity * 0.55
                ZStack {
                    path
                        .stroke(AppColors.wireInactive.opacity(0.28), lineWidth: thickness + 2)
                        .blur(radius: 4)
                    path
                        .stroke(AppColors.wireInactive.opacity(inactiveOpacity), lineWidth: thickness)
                        .shadow(color: AppColors.controlStroke.opacity(0.18), radius: 8)
                        .contentShape(path.strokedPath(.init(lineWidth: thickness + 10)))

                    MovingArrowheads(
                        from: segment.from,
                        to: segment.to,
                        color: AppColors.wireInactive.opacity(0.44),
                        phase: 0
                    )
                }
            }
        }
    }

    private func visibleSegment() -> (from: CGPoint, to: CGPoint) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 1 else { return (from, to) }

        let direction = CGVector(dx: dx / length, dy: dy / length)
        let fromTrim = endpointTrim(for: fromEndpointSize, direction: direction)
        let toTrim = endpointTrim(for: toEndpointSize, direction: direction)
        let totalTrim = fromTrim + toTrim
        let trimScale = totalTrim > length - 1 && totalTrim > 0 ? (length - 1) / totalTrim : 1

        let scaledFromTrim = fromTrim * trimScale
        let scaledToTrim = toTrim * trimScale

        return (
            CGPoint(
                x: from.x + direction.dx * scaledFromTrim,
                y: from.y + direction.dy * scaledFromTrim
            ),
            CGPoint(
                x: to.x - direction.dx * scaledToTrim,
                y: to.y - direction.dy * scaledToTrim
            )
        )
    }

    private func endpointTrim(for size: CGSize, direction: CGVector) -> CGFloat {
        guard size.width > 0 || size.height > 0 else { return 0 }

        let halfWidth = max(size.width, 0) * 0.5
        let halfHeight = max(size.height, 0) * 0.5
        let x = abs(direction.dx)
        let y = abs(direction.dy)
        var trim = CGFloat.greatestFiniteMagnitude

        if halfWidth > 0, x > 0.0001 {
            trim = min(trim, halfWidth / x)
        }
        if halfHeight > 0, y > 0.0001 {
            trim = min(trim, halfHeight / y)
        }
        if trim == CGFloat.greatestFiniteMagnitude {
            trim = max(halfWidth, halfHeight)
        }

        return trim + endpointClearance
    }

    private func makePath(from: CGPoint, to: CGPoint) -> Path {
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

        init(title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
            self.title = title
            self.role = role
            self.action = action
        }
    }

    let anchor: CGPoint
    let position: CGPoint
    let tint: Color
    let items: [Item]

    var size: CGSize {
        let rowHeight: CGFloat = 32
        let height = CGFloat(items.count) * rowHeight + 12
        return CGSize(width: 196, height: height)
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
        private var lastFocusState: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            updateFocus()
            if let window = window {
                keyObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.deliverFocusChange(true)
                }
                resignObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.deliverFocusChange(false)
                }
            }
        }

        func updateFocus() {
            deliverFocusChange(window?.isKeyWindow ?? true)
        }

        private func deliverFocusChange(_ isKeyWindow: Bool) {
            guard lastFocusState != isKeyWindow else { return }
            lastFocusState = isKeyWindow
            DispatchQueue.main.async { [weak self] in
                self?.onFocusChange?(isKeyWindow)
            }
        }

        deinit {
            removeObservers()
        }

        private func removeObservers() {
            if let keyObserver {
                NotificationCenter.default.removeObserver(keyObserver)
            }
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
            }
            keyObserver = nil
            resignObserver = nil
        }
    }
}

struct CustomContextMenuView: View {
    let menu: CustomContextMenu
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(menu.items.enumerated()), id: \.offset) { _, item in
                ContextMenuRow(item: item, tint: menu.tint) {
                    onDismiss()
                }
            }
        }
        .padding(5)
        .sonexisFloatingPanel(tint: menu.tint, cornerRadius: 8, glowOpacity: 0)
        .fixedSize()
        .position(menu.position)
    }
}

private struct ContextMenuRow: View {
    let item: CustomContextMenu.Item
    let tint: Color
    let onSelect: () -> Void
    @State private var isHovered = false

    private var isDestructive: Bool {
        if case .destructive? = item.role { return true }
        return false
    }

    var body: some View {
        Button(role: item.role) {
            item.action()
            onSelect()
        } label: {
            HStack {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(isDestructive ? AppColors.neonPink.opacity(0.92) : AppColors.textPrimary.opacity(0.92))

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 10)
            .frame(width: 184, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? AppColors.controlPurpleRaised.opacity(0.62) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

struct GainPopoverView: View {
    let tint: Color
    let value: Binding<Double>
    let onDone: () -> Void

    var body: some View {
        let itemFont = Font.system(size: 12, weight: .semibold, design: .rounded)
        VStack(spacing: 8) {
            Text("Gain")
                .font(itemFont)
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
            Slider(value: value, in: 0...1)
                .tint(tint)
                .controlSize(.mini)
                .frame(width: 160)
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.caption2)
                .monospacedDigit()
                .foregroundColor(tint.opacity(0.86))
                .frame(maxWidth: .infinity)
            Button("Done") {
                onDone()
            }
            .buttonStyle(.plain)
            .font(itemFont)
            .foregroundColor(AppColors.textPrimary)
            .frame(width: 160, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppColors.controlPurple.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColors.controlStrokeSoft.opacity(0.5), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(10)
        .sonexisFloatingPanel(tint: tint, cornerRadius: 8, glowOpacity: 0)
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
        let coreFill = isEnabled ? style.fillDark.opacity(0.88) : disabledFill
        let shape = RoundedRectangle(cornerRadius: 22)

        return ZStack {
            shape.fill(coreFill)

            if isEnabled {
                shape
                    .fill(style.fill.opacity(0.08))
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
                .stroke(isEnabled ? style.highlight.opacity(0.58) : .clear, lineWidth: 1.5)
                .blendMode(.screen)

            shape
                .fill(Color.white.opacity(isEnabled ? 0.05 : 0))
                .blendMode(.screen)
                .padding(6)
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
