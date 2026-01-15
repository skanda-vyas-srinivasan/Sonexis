import SwiftUI

// MARK: - Effect Block

struct EffectBlockHorizontal: View {
    @Binding var effect: BeginnerNode
    let isWired: Bool
    let isSelected: Bool
    let isDropAnimating: Bool
    let tileStyle: AccentStyle
    let nodeScale: CGFloat
    let onRemove: () -> Void
    let onUpdate: () -> Void
    let onExpanded: () -> Void
    let onCollapsed: () -> Void
    let allowExpand: Bool
    let tutorialStep: TutorialStep
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var dropScale: CGFloat = 1.0
    @State private var dropRotation: Double = 0.0
    private let cardBackground = Color(red: 0.08, green: 0.07, blue: 0.12)
    private let cardBorder = AppColors.neonPink
    private let tileDisabled = Color(hex: "#1A1426")
    private let disabledText = Color(hex: "#80759D")
    private let iconGlow = Color.white.opacity(0.85)

    var body: some View {
        let hoverScale: CGFloat = isHovered ? 1.03 : 1.0
        let hoverOffset: CGFloat = isHovered ? -4 : 0
        let combinedScale = hoverScale * dropScale
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                // Icon and name
                VStack(spacing: 6) {
                    ZStack {
                        NeonTile(
                            isEnabled: getEffectEnabled(),
                            style: tileStyle,
                            disabledFill: tileDisabled
                        )

                        VStack(spacing: 6) {
                            Image(systemName: effect.type.icon)
                                .font(.system(size: 26, weight: .medium))
                                .symbolRenderingMode(.monochrome)
                                .foregroundColor(getEffectEnabled() ? tileStyle.text : disabledText)
                                .shadow(color: getEffectEnabled() ? Color.white.opacity(0.6) : .clear, radius: 8)
                                .shadow(color: getEffectEnabled() ? tileStyle.fill.opacity(0.5) : .clear, radius: 16)

                            Text(effect.type.rawValue.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.2)
                                .foregroundColor((getEffectEnabled() ? tileStyle.text : disabledText).opacity(0.95))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .shadow(color: getEffectEnabled() ? tileStyle.fill.opacity(0.4) : .clear, radius: 10)
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(width: 110, height: 110)
                }

            }
            .padding(10)
            .scaleEffect(combinedScale)
            .rotationEffect(.degrees(dropRotation))
            .offset(y: hoverOffset)
            .opacity(isWired ? 1.0 : 0.45)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? cardBorder : Color.clear, lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture(count: 2) {
                let canToggle = allowExpand || isExpanded
                guard canToggle else { return }
                let wasExpanded = isExpanded
                withAnimation(.easeOut(duration: 0.25)) {
                    isExpanded.toggle()
                    if isExpanded {
                        onExpanded()
                    } else if wasExpanded {
                        onCollapsed()
                    }
                }
            }

            // Expanded parameters
            if isExpanded {
                let overlayScale = 1.0 / max(nodeScale, 0.4)
                VStack(spacing: 12) {
                    EffectParametersViewCompact(
                        effectType: effect.type,
                        parameters: $effect.parameters,
                        tint: tileStyle.fill,
                        onChange: onUpdate
                    )

                    Divider()
                        .background(tileStyle.fill.opacity(0.2))

                    HStack(spacing: 12) {
                        Button(action: {
                            setEffectEnabled(!getEffectEnabled())
                        }) {
                            Label(getEffectEnabled() ? "On" : "Off", systemImage: "power")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .buttonStyle(.bordered)
                        .tint(tileStyle.fill)

                        Button(role: .destructive, action: onRemove) {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .buttonStyle(.bordered)
                        .tint(tileStyle.fill)
                    }
                }
                .padding()
                .frame(width: 220)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.deepBlack.opacity(0.88))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(tileStyle.fill.opacity(0.7), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 6, y: 3)
                )
                .foregroundColor(tileStyle.fill)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.top, 8)
                .scaleEffect(overlayScale, anchor: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: tutorialStep) { step in
            // Keep the panel stable during the open/close tutorial steps.
            if step == .buildDoubleClick || step == .buildCloseOverlay {
                return
            }
            if isExpanded {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded = false
                }
            }
        }
        .onChange(of: isDropAnimating) { triggered in
            guard triggered else { return }
            dropScale = 0.88
            dropRotation = -2
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
                dropScale = 1.08
                dropRotation = 1.5
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    dropScale = 1.0
                    dropRotation = 0.0
                }
            }
        }
    }

    private func getEffectEnabled() -> Bool {
        effect.isEnabled
    }

    private func setEffectEnabled(_ enabled: Bool) {
        effect.isEnabled = enabled
        onUpdate()
    }
}
