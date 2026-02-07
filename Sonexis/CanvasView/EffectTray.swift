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
    let onTabChange: (TrayTab) -> Void
    let allowTapToAdd: Bool
    let tutorialStep: TutorialStep
    @State private var searchText = ""
    @State private var activeTab: TrayTab = .builtIn
    @State private var favoriteIDs: Set<String> = []
    private let tileWidth: CGFloat = 92
    private let tileHeight: CGFloat = 120
    private let labelHeight: CGFloat = 32
    private let iconTileSize: CGFloat = 64

    enum TrayTab: String, CaseIterable, Identifiable {
        case builtIn = "Built-in"
        case plugins = "Plugins"
        case favorites = "Favorites"

        var id: String { rawValue }
    }

    private let effects: [EffectType] = [
        .bassBoost, .enhancer, .clarity, .deMud,
        .simpleEQ, .tenBandEQ, .compressor, .reverb, .stereoWidth,
        .delay, .distortion, .tremolo, .chorus, .phaser, .flanger, .bitcrusher, .tapeSaturation,
        .resampling, .rubberBandPitch
    ]

    var body: some View {
        let gridColumns = [
            GridItem(.fixed(tileWidth), spacing: 10),
            GridItem(.fixed(tileWidth), spacing: 10)
        ]
        let filteredEffects = effects.filter { effect in
            searchText.isEmpty || effect.rawValue.lowercased().contains(searchText.lowercased())
        }
        let filteredPlugins = pluginManager.plugins.filter { plugin in
            plugin.format == .au && (searchText.isEmpty || plugin.name.lowercased().contains(searchText.lowercased()))
        }
        let favoriteEffects = effects.filter { favoriteIDs.contains(effectFavoriteID($0)) }
        let favoritePlugins = pluginManager.plugins.filter { favoriteIDs.contains(pluginFavoriteID($0)) }

        ZStack {
            VStack(spacing: 0) {
                if !isCollapsed {
                    HStack(spacing: 8) {
                        Text("Effects")
                            .font(AppTypography.technical)
                            .foregroundColor(AppColors.textMuted)
                        Spacer()
                        if activeTab == .plugins {
                            Button(action: { pluginManager.scanPlugins() }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .help("Rescan")
                        }
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

                    trayTabs

                    ScrollView(.vertical, showsIndicators: false) {
                        switch activeTab {
                        case .builtIn:
                            LazyVGrid(columns: gridColumns, spacing: 14) {
                                ForEach(filteredEffects, id: \.self) { effectType in
                                    EffectPaletteButton(
                                        effectType: effectType,
                                        previewStyle: previewStyle,
                                        isFavorite: favoriteIDs.contains(effectFavoriteID(effectType)),
                                        onToggleFavorite: { toggleFavorite(effectFavoriteID(effectType)) },
                                        onDragStart: {
                                            onDrag(effectType)
                                        },
                                        tileWidth: tileWidth,
                                        tileHeight: tileHeight,
                                        labelHeight: labelHeight,
                                        iconTileSize: iconTileSize
                                    )
                                    .opacity(allowTapToAdd ? 1.0 : 0.95)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)

                        case .plugins:
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
                                            isFavorite: favoriteIDs.contains(pluginFavoriteID(plugin)),
                                            onToggleFavorite: { toggleFavorite(pluginFavoriteID(plugin)) },
                                            onDragStart: { onDragPlugin(plugin) },
                                            tileWidth: tileWidth,
                                            tileHeight: tileHeight,
                                            labelHeight: labelHeight,
                                            iconTileSize: iconTileSize
                                        )
                                        .opacity(allowTapToAdd ? 1.0 : 0.95)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                            }

                        case .favorites:
                            if favoriteEffects.isEmpty && favoritePlugins.isEmpty {
                                Text("No favorites yet")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textMuted)
                                    .padding(.vertical, 12)
                            } else {
                                LazyVGrid(columns: gridColumns, spacing: 12) {
                                    ForEach(favoriteEffects, id: \.self) { effectType in
                                        EffectPaletteButton(
                                            effectType: effectType,
                                            previewStyle: previewStyle,
                                            isFavorite: true,
                                            onToggleFavorite: { toggleFavorite(effectFavoriteID(effectType)) },
                                            onDragStart: {
                                                onDrag(effectType)
                                            },
                                            tileWidth: tileWidth,
                                            tileHeight: tileHeight,
                                            labelHeight: labelHeight,
                                            iconTileSize: iconTileSize
                                        )
                                        .opacity(allowTapToAdd ? 1.0 : 0.95)
                                    }
                                    ForEach(favoritePlugins) { plugin in
                                        PluginPaletteButton(
                                            plugin: plugin,
                                            previewStyle: previewStyle,
                                            isFavorite: true,
                                            onToggleFavorite: { toggleFavorite(pluginFavoriteID(plugin)) },
                                            onDragStart: { onDragPlugin(plugin) },
                                            tileWidth: tileWidth,
                                            tileHeight: tileHeight,
                                            labelHeight: labelHeight,
                                            iconTileSize: iconTileSize
                                        )
                                        .opacity(allowTapToAdd ? 1.0 : 0.95)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.12), value: activeTab)
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
        .frame(width: isCollapsed ? 44 : 220)
        .background(AppColors.darkPurple.opacity(0.96))
        .overlay(
            Divider(),
            alignment: .trailing
        )
        .onAppear(perform: loadFavorites)
        .onChange(of: tutorialStep) { step in
            if step == .buildTrayTabs || step == .buildAddBass {
                activeTab = .builtIn
            }
        }
        .onAppear {
            if tutorialStep == .buildTrayTabs {
                activeTab = .builtIn
            }
        }
    }

    private var trayTabs: some View {
        HStack(spacing: 8) {
            ForEach(TrayTab.allCases) { tab in
                let isActive = tab == activeTab
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        activeTab = tab
                    }
                    onTabChange(tab)
                }) {
                    Text(tab.rawValue)
                        .font(AppTypography.caption)
                        .foregroundColor(isActive ? AppColors.textPrimary : AppColors.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.85)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isActive ? AppColors.midPurple.opacity(0.75) : AppColors.darkPurple.opacity(0.35))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isActive ? AppColors.neonCyan.opacity(0.65) : AppColors.midPurple.opacity(0.7),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TutorialTargetPreferenceKey.self,
                    value: [.buildTrayTabs: proxy.frame(in: .global)]
                )
            }
        )
    }

    private func effectFavoriteID(_ effect: EffectType) -> String {
        "effect:\(effect.rawValue)"
    }

    private func pluginFavoriteID(_ plugin: PluginDescriptor) -> String {
        "plugin:\(plugin.id)"
    }

    private func loadFavorites() {
        let key = "Sonexis.TrayFavorites"
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        guard let list = try? JSONDecoder().decode([String].self, from: data) else { return }
        favoriteIDs = Set(list)
    }

    private func saveFavorites() {
        let key = "Sonexis.TrayFavorites"
        let list = Array(favoriteIDs)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func toggleFavorite(_ id: String) {
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        saveFavorites()
    }
}

struct EffectPaletteButton: View {
    let effectType: EffectType
    let previewStyle: AccentStyle
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onDragStart: () -> Void
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let labelHeight: CGFloat
    let iconTileSize: CGFloat
    @State private var isHovered = false
    private let tileBase = AppColors.midPurple
    private let textColor = AppColors.textPrimary

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [tileBase.opacity(0.95), tileBase.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: iconTileSize, height: iconTileSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isHovered ? AppColors.neonPink : AppColors.midPurple.opacity(0.6), lineWidth: 1)
                    )

                Image(systemName: effectType.icon)
                    .font(.system(size: 30, weight: .light))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(textColor)
                    .shadow(color: AppColors.neonCyan.opacity(0.2), radius: 4, x: 0, y: 0)
                    .scaleEffect(isHovered ? 1.05 : 1.0)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isFavorite ? AppColors.neonCyan : AppColors.textMuted)
                        .padding(4)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .padding(4)
                }
                .buttonStyle(.plain)
            }

            Text(effectType.rawValue)
                .font(AppTypography.caption)
                .foregroundColor(textColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
                .frame(width: tileWidth, height: labelHeight)
        }
        .frame(width: tileWidth, height: tileHeight, alignment: .top)
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
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onDragStart: () -> Void
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let labelHeight: CGFloat
    let iconTileSize: CGFloat
    @State private var isHovered = false
    private let tileBase = AppColors.midPurple
    private let textColor = AppColors.textPrimary

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [tileBase.opacity(0.95), tileBase.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: iconTileSize, height: iconTileSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isHovered ? AppColors.neonPink : AppColors.midPurple.opacity(0.6), lineWidth: 1)
                    )

                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 30, weight: .light))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(textColor)
                    .shadow(color: AppColors.neonCyan.opacity(0.2), radius: 4, x: 0, y: 0)
            }
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .overlay(alignment: .bottomTrailing) {
                Text(plugin.format == .au ? "AU" : "VST3")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(previewStyle.text.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .offset(x: 5, y: -3)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isFavorite ? AppColors.neonCyan : AppColors.textMuted)
                        .padding(4)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .padding(4)
                }
                .buttonStyle(.plain)
            }

            Text(plugin.name)
                .font(AppTypography.caption)
                .foregroundColor(textColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
                .frame(width: tileWidth, height: labelHeight)
        }
        .frame(width: tileWidth, height: tileHeight, alignment: .top)
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
