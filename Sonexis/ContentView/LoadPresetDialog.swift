import SwiftUI

struct LoadPresetDialog: View {
    @ObservedObject var presetManager: PresetManager
    let tutorialStep: TutorialStep
    let onApply: (SavedPreset) -> Void
    let onCancel: () -> Void
    @State private var searchText = ""

    var body: some View {
        let filteredPresets = presetManager.presets.filter { preset in
            searchText.isEmpty || preset.name.lowercased().contains(searchText.lowercased())
        }

        VStack(alignment: .leading, spacing: 12) {
            if tutorialStep == .buildLoad || tutorialStep == .buildCloseLoad {
                LoadPresetTutorialCard(tutorialStep: tutorialStep)
            }

            PresetDialogHeader(
                title: "Load preset"
            )

            PresetDialogTextField(
                text: $searchText,
                placeholder: "Search presets",
                systemImage: "magnifyingglass",
                tint: AppColors.neonCyan
            )

            if filteredPresets.isEmpty {
                LoadPresetEmptyState()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 7) {
                        ForEach(filteredPresets) { preset in
                            LoadPresetRow(
                                preset: preset,
                                isDisabled: tutorialStep == .buildCloseLoad,
                                onApply: {
                                    onApply(preset)
                                }
                            )
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxHeight: 330)
            }

            HStack {
                Spacer()
                PresetDialogActionButton(
                    title: "Cancel",
                    tint: AppColors.textMuted,
                    isPrimary: false,
                    action: onCancel
                )
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 438, height: 500)
        .sonexisFloatingPanel(tint: AppColors.neonCyan, cornerRadius: 12, glowOpacity: 0)
    }
}

private struct LoadPresetTutorialCard: View {
    let tutorialStep: TutorialStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tutorialStep == .buildLoad ? "cursorarrow.click" : "xmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.neonCyan)
                .frame(width: 26, height: 26)
                .background(AppColors.controlPurpleRaised.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(tutorialStep == .buildLoad ? "Load a preset" : "Close this window")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary.opacity(0.94))

                Text(tutorialStep == .buildLoad ? "Choose any row to apply it." : "Press Cancel to continue.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.deepBlack.opacity(0.34))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppColors.neonCyan.opacity(0.38), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct LoadPresetRow: View {
    let preset: SavedPreset
    let isDisabled: Bool
    let onApply: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onApply) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? AppColors.neonCyan.opacity(0.15) : Color.black.opacity(0.36))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isHovered ? AppColors.neonCyan.opacity(0.50) : AppColors.controlStrokeSoft.opacity(0.14), lineWidth: 1)
                        )

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isHovered ? AppColors.neonCyan : AppColors.textSecondary.opacity(0.90))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary.opacity(0.94))
                        .lineLimit(1)

                    Text("\(preset.graph.nodes.count) effects")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(isHovered ? AppColors.neonCyan.opacity(0.92) : AppColors.textMuted)
                }

                Spacer(minLength: 10)
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? AppColors.controlPurpleRaised.opacity(0.38) : Color.black.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isHovered ? AppColors.neonCyan.opacity(0.44) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.42 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }
}

private struct LoadPresetEmptyState: View {
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "music.note.list")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(AppColors.textMuted.opacity(0.70))
                .frame(width: 34, height: 34)
                .background(AppColors.controlPurple.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text("No presets found")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.vertical, 28)
    }
}
