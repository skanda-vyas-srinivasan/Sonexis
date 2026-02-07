import SwiftUI

// MARK: - Effect Tray

struct EffectTray: View {
    @Binding var isCollapsed: Bool
    @ObservedObject var pluginManager: PluginManager
    let previewStyle: AccentStyle
    let onSelect: (EffectType) -> Void
    let onDrag: (EffectType) -> Void
    let onSelectPlugin: (PluginDescriptor) -> Void
    let onDragPlugin: (PluginDescriptor) -> Void
    let allowTapToAdd: Bool
    @State private var searchText = ""

    private let effects: [EffectType] = [
        .bassBoost, .enhancer, .clarity, .deMud,
        .simpleEQ, .tenBandEQ, .compressor, .reverb, .stereoWidth,
        .delay, .distortion, .tremolo, .chorus, .phaser, .flanger, .bitcrusher, .tapeSaturation,
        .resampling, .rubberBandPitch
    ]

    var body: some View {
        let filteredEffects = effects.filter { effect in
            searchText.isEmpty || effect.rawValue.lowercased().contains(searchText.lowercased())
        }
        let filteredPlugins = pluginManager.plugins.filter { plugin in
            plugin.format == .au && (searchText.isEmpty || plugin.name.lowercased().contains(searchText.lowercased()))
        }

        let gridColumns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

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
                        LazyVGrid(columns: gridColumns, spacing: 14) {
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)

                        Divider()
                            .background(AppColors.gridLines)
                            .padding(.vertical, 6)

                        HStack {
                            Text("Plugins")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textMuted)
                            Spacer()
                            Button(action: { pluginManager.promptAddFolder() }) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .help("Add Folder")

                            Button(action: { pluginManager.scanPlugins() }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .help("Rescan")
                        }
                        .padding(.horizontal, 10)

                        if filteredPlugins.isEmpty {
                            Text("No plugins found")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textMuted)
                                .padding(.vertical, 8)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(filteredPlugins) { plugin in
                                    PluginPaletteButton(
                                        plugin: plugin,
                                        previewStyle: previewStyle,
                                        onTap: { onSelectPlugin(plugin) },
                                        onDragStart: { onDragPlugin(plugin) }
                                    )
                                    .opacity(allowTapToAdd ? 1.0 : 0.95)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                        }
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
                .font(.system(size: 20, weight: .light))
                .symbolRenderingMode(.monochrome)
                .foregroundColor(textColor)
                .frame(width: 50, height: 50)
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
                .frame(width: 62)
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
        .onDrag({
            isDragging = true
            onDragStart()
            return NSItemProvider(object: effectType.rawValue as NSString)
        }, preview: {
            EffectDragPreview(effectType: effectType, tileStyle: previewStyle)
        })
    }
}

struct PluginPaletteButton: View {
    let plugin: PluginDescriptor
    let previewStyle: AccentStyle
    let onTap: () -> Void
    let onDragStart: () -> Void
    @State private var isHovered = false
    private let tileBase = AppColors.midPurple
    private let textColor = AppColors.textPrimary

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tileBase)
                    .frame(width: 50, height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isHovered ? AppColors.neonPink : Color.clear, lineWidth: 1)
                    )

                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 20, weight: .light))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(textColor)
            }
            .scaleEffect(isHovered ? 1.05 : 1.0)

            Text(plugin.name)
                .font(AppTypography.caption)
                .foregroundColor(textColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70)

            Text(plugin.format == .au ? "AU" : "VST3")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(previewStyle.text.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(previewStyle.fill.opacity(0.2))
                .clipShape(Capsule())
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onDrag({
            onDragStart()
            return NSItemProvider(object: plugin.id as NSString)
        }, preview: {
            PluginDragPreview(plugin: plugin, tileStyle: previewStyle)
        })
    }
}

struct PluginDragPreview: View {
    let plugin: PluginDescriptor
    let tileStyle: AccentStyle

    var body: some View {
        ZStack {
            NeonTile(
                isEnabled: true,
                style: tileStyle,
                disabledFill: Color(hex: "#1A1426")
            )

            VStack(spacing: 6) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 26, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(tileStyle.text)
                    .shadow(color: Color.white.opacity(0.6), radius: 8)
                    .shadow(color: tileStyle.fill.opacity(0.5), radius: 16)

                Text(plugin.name)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(tileStyle.text.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .shadow(color: tileStyle.fill.opacity(0.4), radius: 10)
            }
            .padding(.horizontal, 6)
            .overlay(alignment: .topTrailing) {
                Text(plugin.format == .au ? "AU" : "VST3")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .offset(x: 6, y: -6)
            }
        }
        .frame(width: 110, height: 110)
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

                Text(effectType.rawValue)
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
