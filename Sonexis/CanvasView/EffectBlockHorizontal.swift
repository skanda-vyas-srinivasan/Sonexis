import SwiftUI

// MARK: - Effect Block

struct EffectBlockHorizontal: View {
    @ObservedObject var audioEngine: AudioEngine
    @Binding var effect: BeginnerNode
    let isWired: Bool
    let isSelected: Bool
    let isDropAnimating: Bool
    let tileStyle: AccentStyle
    let nodeScale: CGFloat
    let isPluginLoading: Bool
    let onRemove: () -> Void
    let onUpdate: () -> Void
    let onParameterChange: () -> Void
    let onExpanded: () -> Void
    let onCollapsed: () -> Void
    let onOpenPluginEditor: () -> Void
    let allowExpand: Bool
    let tutorialStep: TutorialStep
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var dropScale: CGFloat = 1.0
    @State private var dropRotation: Double = 0.0
    private let cardBackground = Color(red: 0.08, green: 0.07, blue: 0.12)
    private let tileDisabled = Color(hex: "#1A1426")
    private let disabledText = Color(hex: "#80759D")
    private let iconGlow = Color.white.opacity(0.85)
    private let selectionColor = AppColors.neonPink

    var body: some View {
        let hoverScale: CGFloat = isHovered ? 1.03 : 1.0
        let hoverOffset: CGFloat = isHovered ? -4 : 0
        let combinedScale = hoverScale * dropScale
        ZStack(alignment: .top) {
            VStack(spacing: 8) {
                // Icon and name
                VStack(spacing: 6) {
                    ZStack {
                        NeonTile(
                            isEnabled: getEffectEnabled(),
                            style: tileStyle,
                            disabledFill: tileDisabled
                        )
                        .overlay(
                            selectionIndicator
                        )

                        VStack(spacing: 6) {
                            Image(systemName: effect.displayIcon)
                                .font(.system(size: 26, weight: .medium))
                                .symbolRenderingMode(.monochrome)
                                .foregroundColor(getEffectEnabled() ? tileStyle.text : disabledText)
                                .shadow(color: getEffectEnabled() ? Color.white.opacity(0.6) : .clear, radius: 8)
                                .shadow(color: getEffectEnabled() ? tileStyle.fill.opacity(0.5) : .clear, radius: 16)

                            Text(effect.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.2)
                                .foregroundColor((getEffectEnabled() ? tileStyle.text : disabledText).opacity(0.95))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .shadow(color: getEffectEnabled() ? tileStyle.fill.opacity(0.4) : .clear, radius: 10)
                        }
                        .overlay(alignment: .topTrailing) {
                            if let badge = effect.displayBadge {
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.6))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                    .offset(x: 6, y: -6)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if isPluginLoading {
                                Text("Loading...")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.65))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                    .offset(y: 6)
                            }
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
            .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture(count: 2) {
                if effect.type == .plugin {
                    onOpenPluginEditor()
                    return
                }
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
                    HStack {
                        Text(effect.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Spacer()
                    }

                    Rectangle()
                        .fill(AppColors.controlStrokeSoft.opacity(0.45))
                        .frame(height: 1)

                    if effect.type == .plugin {
                        PluginParametersCompactView(
                            audioEngine: audioEngine,
                            nodeId: effect.id,
                            tint: tileStyle.fill
                        )
                    } else {
                        EffectParametersViewCompact(
                            effectType: effect.type,
                            parameters: $effect.parameters,
                            tint: tileStyle.fill,
                            onChange: onParameterChange
                        )
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            setEffectEnabled(!getEffectEnabled())
                        }) {
                            Label(getEffectEnabled() ? "On" : "Off", systemImage: "power")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PanelPillButtonStyle(tint: tileStyle.fill, isActive: getEffectEnabled()))

                        Button(role: .destructive, action: onRemove) {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PanelPillButtonStyle(tint: AppColors.neonPink, isActive: false))
                    }
                }
                .padding(12)
                .frame(width: 226)
                .sonexisFloatingPanel(tint: tileStyle.fill, cornerRadius: 8, glowOpacity: 0)
                .foregroundColor(AppColors.textPrimary)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .scaleEffect(overlayScale, anchor: .top)
                .offset(y: 138)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 226, height: 130, alignment: .top)
        .zIndex(isExpanded ? 10 : 0)
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

    @ViewBuilder
    private var selectionIndicator: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(selectionColor.opacity(0.94), lineWidth: 2.8)
                .shadow(color: selectionColor.opacity(0.52), radius: 10)
                .padding(-11)
                .allowsHitTesting(false)
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

private struct PanelPillButtonStyle: ButtonStyle {
    let tint: Color
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(AppColors.textPrimary.opacity(configuration.isPressed ? 0.78 : 0.95))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? tint.opacity(0.16) : AppColors.controlPurple.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive ? tint.opacity(0.34) : AppColors.controlStrokeSoft.opacity(0.5), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
