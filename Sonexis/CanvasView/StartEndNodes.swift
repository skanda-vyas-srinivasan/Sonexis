import SwiftUI

// MARK: - Start/End Nodes

struct StartNodeView: View {
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppTheme.defaultThemeID

    private var activePalette: AppColorPalette {
        AppTheme.theme(for: selectedThemeID).palette
    }

    var body: some View {
        let palette = activePalette
        let tint = palette.neonCyan

        VStack(spacing: 8) {
            Circle()
                .fill(palette.controlPurpleRaised.opacity(0.82))
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(tint.opacity(0.7), lineWidth: 2)
                        .shadow(color: tint.opacity(0.5), radius: 8)
                )
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 24))
                        .foregroundColor(palette.textPrimary)
                )
                .shadow(color: tint.opacity(0.25), radius: 9)

            Text("Start")
                .font(AppTypography.caption)
                .foregroundColor(palette.textSecondary)
        }
        .frame(width: 80)
    }
}

struct EndNodeView: View {
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppTheme.defaultThemeID

    private var activePalette: AppColorPalette {
        AppTheme.theme(for: selectedThemeID).palette
    }

    var body: some View {
        let palette = activePalette
        let tint = palette.neonPink

        VStack(spacing: 8) {
            Circle()
                .fill(palette.controlPurpleRaised.opacity(0.82))
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(tint.opacity(0.7), lineWidth: 2)
                        .shadow(color: tint.opacity(0.5), radius: 8)
                )
                .overlay(
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 24))
                        .foregroundColor(palette.textPrimary)
                )
                .shadow(color: tint.opacity(0.25), radius: 9)

            Text("End")
                .font(AppTypography.caption)
                .foregroundColor(palette.textSecondary)
        }
        .frame(width: 80)
    }
}
