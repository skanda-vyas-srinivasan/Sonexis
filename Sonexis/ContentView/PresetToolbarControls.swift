import SwiftUI
import AppKit

struct PresetUnlinkButton: View {
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "link.slash")
                    .font(.system(size: 9, weight: .semibold))
                Text("Unlink")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundColor(AppColors.neonPink.opacity(isHovered ? 1 : 0.72))
            .padding(.horizontal, 3)
            .frame(height: 18)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppColors.neonPink)
                    .frame(height: 1)
                    .opacity(isHovered ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel("Unlink current preset")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

struct PresetSaveSplitButton: View {
    let tint: Color
    let isEnabled: Bool
    let hasCurrentPreset: Bool
    let onSave: () -> Void
    let onSaveAs: () -> Void
    @State private var isHovered = false
    @State private var isMenuPresented = false
    @State private var isItemHovered = false
    @StateObject private var menuEvents = PresetMenuEvents()

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                isMenuPresented = false
                if hasCurrentPreset { onSave() } else { onSaveAs() }
            }) {
                Text("Save")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary.opacity(0.94))
                    .padding(.leading, 10)
                    .padding(.trailing, 8)
                    .frame(width: 46, height: 30)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(AppColors.controlStrokeSoft.opacity(isHovered ? 0.62 : 0.42))
                .frame(width: 1, height: 18)

            Button {
                isMenuPresented.toggle()
            } label: {
                Image(systemName: isMenuPresented ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save options")
            .accessibilityValue(isMenuPresented ? "Expanded" : "Collapsed")
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? AppColors.controlPurpleRaised.opacity(0.72) : AppColors.controlPurple.opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHovered ? tint.opacity(0.44) : AppColors.controlStrokeSoft.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(PresetMenuRegion(events: menuEvents, isAnchor: true))
        .overlay(alignment: .topLeading) {
            GeometryReader { anchor in
                if isMenuPresented {
                    Button(action: chooseSaveAs) {
                        HStack {
                            Text("Save As")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(isItemHovered ? AppColors.controlPurpleRaised : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isItemHovered = $0 }
                    .padding(5)
                    .frame(width: anchor.size.width)
                    .background(AppColors.panelPurple)
                    .sonexisFloatingPanel(tint: tint, cornerRadius: 8, glowOpacity: 0)
                    .background(PresetMenuRegion(events: menuEvents, isAnchor: false))
                    .offset(y: 36)
                    .onAppear {
                        menuEvents.start(onDismiss: { isMenuPresented = false }, onSelect: chooseSaveAs)
                    }
                    .onDisappear {
                        menuEvents.stop()
                        isItemHovered = false
                    }
                }
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { isMenuPresented = false }
        }
        .onDisappear { menuEvents.stop() }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.42)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }

    private func chooseSaveAs() {
        isMenuPresented = false
        onSaveAs()
    }
}

struct PresetToolbarButton: View {
    let title: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textPrimary.opacity(0.94))
                .padding(.horizontal, 10)
                .frame(minWidth: 48, minHeight: 30)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? AppColors.controlPurpleRaised.opacity(0.72) : AppColors.controlPurple.opacity(0.46))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isHovered ? tint.opacity(0.44) : AppColors.controlStrokeSoft.opacity(0.58), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.42)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }
}


// Track actual view regions so outside-click dismissal works with either window
// coordinate orientation and does not steal clicks inside the dropdown.
private final class PresetMenuEvents: ObservableObject {
    weak var anchor: NSView?
    weak var menu: NSView?
    private var monitor: Any?

    func start(onDismiss: @escaping () -> Void, onSelect: @escaping () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                guard event.window === self.anchor?.window else {
                    onDismiss()
                    return event
                }
                switch event.keyCode {
                case 53, 48: // Escape / Tab dismiss; let Tab continue navigation.
                    onDismiss()
                    return event.keyCode == 48 ? event : nil
                case 36, 76, 49: // Return / keypad Enter / Space activate the only item.
                    onSelect()
                    return nil
                case 125, 126: // A one-item menu has no alternate selection.
                    return nil
                default:
                    onDismiss()
                    return event
                }
            }
            let inside = [self.anchor, self.menu].compactMap { $0 }.contains { view in
                view.window === event.window && view.bounds.contains(view.convert(event.locationInWindow, from: nil))
            }
            if !inside { onDismiss() }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }
}

private struct PresetMenuRegion: NSViewRepresentable {
    let events: PresetMenuEvents
    let isAnchor: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        if isAnchor { events.anchor = view } else { events.menu = view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
