import SwiftUI

// MARK: - Effect Tray

private enum EffectPaletteCategoryStyle {
    case featured
    case standard
}

private struct EffectPaletteCategory: Identifiable {
    let title: String
    let tint: Color
    let style: EffectPaletteCategoryStyle
    let effects: [EffectType]

    var id: String { title }
}

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
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppTheme.defaultThemeID
    private let expandedWidth: CGFloat = 252
    private let collapsedWidth: CGFloat = 44
    private var effectPanelHighlightTint: Color {
        let palette = AppTheme.theme(for: selectedThemeID).palette
        return AppTheme.theme(for: selectedThemeID) == .magenta ? palette.neonCyan : palette.neonPink
    }

    enum TrayTab: String, CaseIterable, Identifiable {
        case builtIn = "Built-in"
        case plugins = "Plugins"
        case favorites = "Favorites"

        var id: String { rawValue }
    }

    private var effectCategories: [EffectPaletteCategory] {
        [
            EffectPaletteCategory(
                title: "Signature",
                tint: effectPanelHighlightTint,
                style: .featured,
                effects: [.nightDrive, .chromePunch, .midnightGlow, .afterglow]
            ),
            EffectPaletteCategory(
                title: "Tone",
                tint: effectPanelHighlightTint,
                style: .standard,
                effects: [.bassBoost, .enhancer, .clarity, .simpleEQ, .rubberBandPitch]
            ),
            EffectPaletteCategory(
                title: "Space",
                tint: effectPanelHighlightTint,
                style: .standard,
                effects: [.reverb, .stereoWidth, .delay]
            ),
            EffectPaletteCategory(
                title: "Motion",
                tint: effectPanelHighlightTint,
                style: .standard,
                effects: [.tremolo, .autoPan, .chorus, .phaser, .flanger]
            ),
            EffectPaletteCategory(
                title: "Texture",
                tint: effectPanelHighlightTint,
                style: .standard,
                effects: [.amp, .bitcrusher, .tapeSaturation]
            )
        ]
    }

    private var allEffects: [EffectType] {
        effectCategories.flatMap(\.effects)
    }

    var body: some View {
        let visibleSections = visibleEffectSections(matching: searchText)
        let filteredPlugins = visiblePlugins(matching: searchText)
        let favoriteEffects = allEffects.filter { favoriteIDs.contains(effectFavoriteID($0)) }
        let favoritePlugins = pluginManager.plugins.filter { favoriteIDs.contains(pluginFavoriteID($0)) }

        ZStack {
            VStack(spacing: 0) {
                if !isCollapsed {
                    header

                    Divider()
                        .background(AppColors.controlStrokeSoft.opacity(0.54))

                    searchField

                    trayTabs

                    ScrollView(.vertical, showsIndicators: true) {
                        switch activeTab {
                        case .builtIn:
                            if visibleSections.isEmpty {
                                TrayEmptyState(
                                    icon: "magnifyingglass",
                                    title: "No matching effects",
                                    detail: "Try a sound type like width, drive, delay, or clarity."
                                )
                            } else {
                                LazyVStack(alignment: .leading, spacing: 13) {
                                    ForEach(visibleSections) { category in
                                        EffectCategorySection(
                                            category: category,
                                            previewStyle: previewStyle,
                                            favoriteIDs: favoriteIDs,
                                            allowTapToAdd: allowTapToAdd,
                                            effectFavoriteID: effectFavoriteID,
                                            onSelect: onSelect,
                                            onDrag: onDrag,
                                            onToggleFavorite: toggleFavorite
                                        )
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 12)
                            }

                        case .plugins:
                            if pluginManager.isScanning {
                                TrayLoadingState(title: "Scanning Audio Units")
                            } else if filteredPlugins.isEmpty {
                                TrayEmptyState(
                                    icon: "puzzlepiece.extension",
                                    title: pluginManager.hasScannedPlugins ? "No Audio Units found" : "Plugins not scanned",
                                    detail: pluginManager.hasScannedPlugins ? "Rescan after installing or enabling Audio Unit effects." : "Scan your installed Audio Units to add them to the chain.",
                                    buttonTitle: pluginManager.hasScannedPlugins ? "Rescan" : "Scan Plugins",
                                    action: { pluginManager.scanPlugins() }
                                )
                            } else {
                                LazyVStack(alignment: .leading, spacing: 7) {
                                    ForEach(filteredPlugins) { plugin in
                                        PluginPaletteButton(
                                            plugin: plugin,
                                            previewStyle: previewStyle,
                                            isFavorite: favoriteIDs.contains(pluginFavoriteID(plugin)),
                                            allowTapToAdd: allowTapToAdd,
                                            onSelect: { onSelectPlugin(plugin) },
                                            onToggleFavorite: { toggleFavorite(pluginFavoriteID(plugin)) },
                                            onDragStart: { onDragPlugin(plugin) }
                                        )
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 12)
                            }

                        case .favorites:
                            if favoriteEffects.isEmpty && favoritePlugins.isEmpty {
                                TrayEmptyState(
                                    icon: "star",
                                    title: "No favorites yet",
                                    detail: "Star the effects you reach for most."
                                )
                            } else {
                                LazyVStack(alignment: .leading, spacing: 13) {
                                    if !favoriteEffects.isEmpty {
                                        FavoriteSectionHeader(title: "Built-in favorites")
                                        LazyVStack(spacing: 7) {
                                            ForEach(favoriteEffects, id: \.self) { effectType in
                                                let category = category(for: effectType)
                                                EffectPaletteButton(
                                                    effectType: effectType,
                                                    tint: category.tint,
                                                    isFeatured: category.style == .featured,
                                                    previewStyle: previewStyle,
                                                    isFavorite: true,
                                                    allowTapToAdd: allowTapToAdd,
                                                    onSelect: { onSelect(effectType) },
                                                    onToggleFavorite: { toggleFavorite(effectFavoriteID(effectType)) },
                                                    onDragStart: { onDrag(effectType) }
                                                )
                                            }
                                        }
                                    }

                                    if !favoritePlugins.isEmpty {
                                        FavoriteSectionHeader(title: "Plugin favorites")
                                        LazyVStack(spacing: 7) {
                                            ForEach(favoritePlugins) { plugin in
                                                PluginPaletteButton(
                                                    plugin: plugin,
                                                    previewStyle: previewStyle,
                                                    isFavorite: true,
                                                    allowTapToAdd: allowTapToAdd,
                                                    onSelect: { onSelectPlugin(plugin) },
                                                    onToggleFavorite: { toggleFavorite(pluginFavoriteID(plugin)) },
                                                    onDragStart: { onDragPlugin(plugin) }
                                                )
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
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
                    .foregroundColor(AppColors.textSecondary)
                    .background(AppColors.controlPurple.opacity(0.80))
                    .overlay(
                        Circle()
                            .stroke(AppColors.controlStroke.opacity(0.58), lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .frame(maxHeight: .infinity)
            .zIndex(2)
        }
        .frame(width: isCollapsed ? collapsedWidth : expandedWidth)
        .background(AppColors.panelPurple.opacity(0.88))
        .overlay(
            Rectangle()
                .fill(AppColors.controlStroke.opacity(0.50))
                .frame(width: 1),
            alignment: .trailing
        )
        .onAppear {
            loadFavorites()
            scanPluginsIfNeeded(for: activeTab)
        }
        .onChange(of: tutorialStep) { step in
            if step == .buildTrayTabs || step == .buildAddBass {
                activeTab = .builtIn
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Effects")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textPrimary.opacity(0.92))
            Spacer()
            Button(action: { pluginManager.scanPlugins() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .foregroundColor(AppColors.textSecondary)
                    .background(AppColors.controlPurple.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Rescan Audio Units")
            .opacity(activeTab == .plugins ? 1 : 0)
            .disabled(activeTab != .plugins)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppColors.textMuted)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(AppColors.textPrimary)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(AppColors.controlPurple.opacity(0.34))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.controlStroke.opacity(0.42), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private var trayTabs: some View {
        HStack(spacing: 4) {
            ForEach(TrayTab.allCases) { tab in
                let isActive = tab == activeTab
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        activeTab = tab
                    }
                    scanPluginsIfNeeded(for: tab)
                    onTabChange(tab)
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: isActive ? .semibold : .medium, design: .rounded))
                        .foregroundColor(isActive ? AppColors.textPrimary : AppColors.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isActive ? AppColors.controlPurpleRaised.opacity(0.74) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppColors.controlPurple.opacity(0.28))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppColors.controlStrokeSoft.opacity(0.46), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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

    private func visibleEffectSections(matching query: String) -> [EffectPaletteCategory] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return effectCategories }

        return effectCategories.compactMap { category in
            let matches = category.effects.filter { effect in
                effect.rawValue.lowercased().contains(term) ||
                    effect.description.lowercased().contains(term) ||
                    category.title.lowercased().contains(term)
            }
            guard !matches.isEmpty else { return nil }
            return EffectPaletteCategory(
                title: category.title,
                tint: category.tint,
                style: category.style,
                effects: matches
            )
        }
    }

    private func visiblePlugins(matching query: String) -> [PluginDescriptor] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return pluginManager.plugins.filter { plugin in
            guard plugin.format == .au else { return false }
            guard !term.isEmpty else { return true }
            return plugin.displayName.lowercased().contains(term) ||
                plugin.vendor.lowercased().contains(term)
        }
    }

    private func category(for effect: EffectType) -> EffectPaletteCategory {
        effectCategories.first { $0.effects.contains(effect) } ?? effectCategories[0]
    }

    private func scanPluginsIfNeeded(for tab: TrayTab) {
        guard tab == .plugins || tab == .favorites else { return }
        guard !pluginManager.hasScannedPlugins, !pluginManager.isScanning else { return }
        pluginManager.scanPlugins()
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

private struct EffectCategorySection: View {
    let category: EffectPaletteCategory
    let previewStyle: AccentStyle
    let favoriteIDs: Set<String>
    let allowTapToAdd: Bool
    let effectFavoriteID: (EffectType) -> String
    let onSelect: (EffectType) -> Void
    let onDrag: (EffectType) -> Void
    let onToggleFavorite: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(category.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textPrimary.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVStack(spacing: 7) {
                ForEach(category.effects, id: \.self) { effectType in
                    EffectPaletteButton(
                        effectType: effectType,
                        tint: category.tint,
                        isFeatured: category.style == .featured,
                        previewStyle: previewStyle,
                        isFavorite: favoriteIDs.contains(effectFavoriteID(effectType)),
                        allowTapToAdd: allowTapToAdd,
                        onSelect: { onSelect(effectType) },
                        onToggleFavorite: { onToggleFavorite(effectFavoriteID(effectType)) },
                        onDragStart: { onDrag(effectType) }
                    )
                }
            }
        }
    }
}

private struct FavoriteSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(AppColors.textPrimary.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EffectPaletteButton: View {
    let effectType: EffectType
    let tint: Color
    let isFeatured: Bool
    let previewStyle: AccentStyle
    let isFavorite: Bool
    let allowTapToAdd: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDragStart: () -> Void
    @State private var isHovered = false
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppTheme.defaultThemeID

    private var isBlackTheme: Bool {
        AppTheme.theme(for: selectedThemeID) == .black
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 9) {
                iconBox

                Text(effectType.rawValue)
                    .font(.system(size: isFeatured ? 12 : 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 28)
            }
            .padding(.leading, 8)
            .padding(.trailing, 34)
            .padding(.vertical, isFeatured ? 8 : 7)
            .frame(maxWidth: .infinity, minHeight: isFeatured ? 50 : 46, alignment: .leading)
            .background(rowFill)
            .overlay(rowStroke)
            .clipShape(Rectangle())
            .contentShape(Rectangle())
            .opacity(allowTapToAdd ? 1.0 : 0.86)
            .onTapGesture {
                guard allowTapToAdd else { return }
                onSelect()
            }

            FavoriteIconButton(
                isFavorite: isFavorite,
                tint: tint,
                action: onToggleFavorite
            )
            .opacity(isHovered || isFavorite ? 1 : 0.44)
            .padding(.trailing, 8)
        }
        .zIndex(isHovered ? 20 : 0)
        .background(tutorialPreference)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
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

    private var iconBox: some View {
        ZStack {
            Rectangle()
                .fill(isHovered ? tint.opacity(0.15) : AppColors.controlPurpleRaised.opacity(isBlackTheme ? 0.22 : 0.12))
                .overlay(
                    Rectangle()
                        .stroke(isHovered ? tint.opacity(0.48) : AppColors.controlStrokeSoft.opacity(isBlackTheme ? 0.32 : 0.22), lineWidth: 1)
                )

            Image(systemName: effectType.icon)
                .font(.system(size: isFeatured ? 17 : 15, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundColor(isHovered ? tint : AppColors.textSecondary.opacity(0.90))
        }
        .frame(width: isFeatured ? 36 : 34, height: isFeatured ? 36 : 34)
    }

    private var rowFill: some View {
        Rectangle()
            .fill(isHovered ? AppColors.controlPurpleRaised.opacity(0.30) : AppColors.controlPurpleRaised.opacity(isBlackTheme ? 0.18 : 0.11))
    }

    private var rowStroke: some View {
        Rectangle()
            .stroke(isHovered ? tint.opacity(0.38) : AppColors.controlStrokeSoft.opacity(isBlackTheme ? 0.26 : 0.16), lineWidth: 1)
    }

    @ViewBuilder
    private var tutorialPreference: some View {
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
    }
}

struct PluginPaletteButton: View {
    let plugin: PluginDescriptor
    let previewStyle: AccentStyle
    let isFavorite: Bool
    let allowTapToAdd: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDragStart: () -> Void
    @State private var isHovered = false
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppTheme.defaultThemeID
    private var highlightTint: Color {
        let palette = AppTheme.theme(for: selectedThemeID).palette
        return AppTheme.theme(for: selectedThemeID) == .magenta ? palette.neonCyan : palette.neonPink
    }
    private var isBlackTheme: Bool {
        AppTheme.theme(for: selectedThemeID) == .black
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 9) {
                ZStack {
                    Rectangle()
                        .fill(isHovered ? highlightTint.opacity(0.14) : AppColors.controlPurpleRaised.opacity(isBlackTheme ? 0.22 : 0.12))
                        .overlay(
                            Rectangle()
                                .stroke(isHovered ? highlightTint.opacity(0.46) : AppColors.controlStrokeSoft.opacity(isBlackTheme ? 0.32 : 0.22), lineWidth: 1)
                        )

                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(isHovered ? highlightTint : AppColors.textSecondary.opacity(0.90))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 0) {
                    Text(plugin.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary.opacity(0.94))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 28)
            }
            .padding(.leading, 8)
            .padding(.trailing, 34)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(
                Rectangle()
                    .fill(isHovered ? AppColors.controlPurpleRaised.opacity(0.30) : AppColors.controlPurpleRaised.opacity(isBlackTheme ? 0.18 : 0.11))
            )
            .overlay(
                Rectangle()
                    .stroke(isHovered ? highlightTint.opacity(0.38) : AppColors.controlStrokeSoft.opacity(isBlackTheme ? 0.26 : 0.16), lineWidth: 1)
            )
            .clipShape(Rectangle())
            .contentShape(Rectangle())
            .opacity(allowTapToAdd ? 1.0 : 0.86)
            .onTapGesture {
                guard allowTapToAdd else { return }
                onSelect()
            }

            FavoriteIconButton(
                isFavorite: isFavorite,
                tint: highlightTint,
                action: onToggleFavorite
            )
            .opacity(isHovered || isFavorite ? 1 : 0.44)
            .padding(.trailing, 8)
        }
        .zIndex(isHovered ? 20 : 0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
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

private struct FavoriteIconButton: View {
    let isFavorite: Bool
    let tint: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isFavorite ? tint : (isHovered ? AppColors.textSecondary : AppColors.textMuted))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "Remove favorite" : "Add favorite")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

private struct TrayEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(AppColors.textMuted.opacity(0.70))
                .frame(width: 34, height: 34)
                .background(AppColors.controlPurple.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                Text(detail)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 210)
            }

            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColors.controlPurpleRaised.opacity(0.52))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppColors.neonCyan.opacity(0.40), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 22)
    }
}

private struct TrayLoadingState: View {
    let title: String

    var body: some View {
        VStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
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

                Text(plugin.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(tileStyle.text.opacity(0.95))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .shadow(color: tileStyle.fill.opacity(0.4), radius: 10)
            }
            .padding(.horizontal, 6)
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
