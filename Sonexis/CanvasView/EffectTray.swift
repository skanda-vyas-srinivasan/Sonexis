import SwiftUI

// MARK: - Effect Tray

struct EffectTray: View {
    @Binding var isCollapsed: Bool
    let previewStyle: AccentStyle
    let onSelect: (EffectType) -> Void
    let onDrag: (EffectType) -> Void
    let allowTapToAdd: Bool
    @State private var searchText = ""

    private let effects: [EffectType] = [
        .bassBoost, .clarity, .deMud,
        .simpleEQ, .tenBandEQ, .compressor, .reverb, .stereoWidth,
        .delay, .distortion, .tremolo, .chorus, .phaser, .flanger, .bitcrusher, .tapeSaturation,
        .resampling, .rubberBandPitch
    ]

    var body: some View {
        let filteredEffects = effects.filter { effect in
            searchText.isEmpty || effect.rawValue.lowercased().contains(searchText.lowercased())
        }

        ZStack {
            VStack(spacing: 0) {
                if !isCollapsed {
                    HStack(spacing: 8) {
                        Text("Effects")
                            .font(AppTypography.technical)
                            .foregroundColor(AppColors.textMuted)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                    Divider()
                        .background(AppColors.gridLines)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppColors.neonCyan)
                        TextField("Search effects...", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .padding(8)
                    .background(AppColors.darkPurple)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.neonCyan.opacity(0.5), lineWidth: 1)
                    )
                    .cornerRadius(8)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(filteredEffects, id: \.self) { effectType in
                                EffectPaletteButton(
                                    effectType: effectType,
                                    previewStyle: previewStyle,
                                    onTap: {
                                        if allowTapToAdd {
                                            onSelect(effectType)
                                        }
                                    },
                                    onDragStart: {
                                        onDrag(effectType)
                                    }
                                )
                                .opacity(allowTapToAdd ? 1.0 : 0.95)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .overlay(alignment: .trailing) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            }) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(6)
                    .background(AppColors.midPurple.opacity(0.95))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .frame(maxHeight: .infinity)
            .zIndex(2)
        }
        .frame(width: isCollapsed ? 44 : 200)
        .background(AppColors.darkPurple.opacity(0.96))
        .overlay(
            Divider(),
            alignment: .trailing
        )
    }
}

struct EffectPaletteButton: View {
    let effectType: EffectType
    let previewStyle: AccentStyle
    let onTap: () -> Void
    let onDragStart: () -> Void
    @State private var isHovered = false
    @State private var isDragging = false
    private let tileBase = AppColors.midPurple
    private let textColor = AppColors.textPrimary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: effectType.icon)
                .font(.system(size: 22, weight: .light))
                .symbolRenderingMode(.monochrome)
                .foregroundColor(textColor)
                .frame(width: 56, height: 56)
                .background(tileBase)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isHovered ? AppColors.neonPink : Color.clear, lineWidth: 1)
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .opacity(isDragging ? 0.5 : 1.0)

            Text(effectType.rawValue)
                .font(AppTypography.caption)
                .foregroundColor(textColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
        .background(
            GeometryReader { proxy in
                switch effectType {
                case .bassBoost:
                    Color.clear.preference(
                        key: TutorialTargetPreferenceKey.self,
                        value: [.buildBassBoost: proxy.frame(in: .global)]
                    )
                case .clarity:
                    Color.clear.preference(
                        key: TutorialTargetPreferenceKey.self,
                        value: [.buildClarity: proxy.frame(in: .global)]
                    )
                case .reverb:
                    Color.clear.preference(
                        key: TutorialTargetPreferenceKey.self,
                        value: [.buildReverb: proxy.frame(in: .global)]
                    )
                default:
                    Color.clear
                }
            }
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onTap()
        }
        .onDrag({
            isDragging = true
            onDragStart()
            return NSItemProvider(object: effectType.rawValue as NSString)
        }, preview: {
            EffectDragPreview(effectType: effectType, tileStyle: previewStyle)
        })
    }
}

struct EffectDragPreview: View {
    let effectType: EffectType
    let tileStyle: AccentStyle

    var body: some View {
        ZStack {
            NeonTile(
                isEnabled: true,
                style: tileStyle,
                disabledFill: Color(hex: "#1A1426")
            )

            VStack(spacing: 6) {
                Image(systemName: effectType.icon)
                    .font(.system(size: 26, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(tileStyle.text)
                    .shadow(color: Color.white.opacity(0.6), radius: 8)
                    .shadow(color: tileStyle.fill.opacity(0.5), radius: 16)

                Text(effectType.rawValue.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(tileStyle.text.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .shadow(color: tileStyle.fill.opacity(0.4), radius: 10)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: 110, height: 110)
    }
}

