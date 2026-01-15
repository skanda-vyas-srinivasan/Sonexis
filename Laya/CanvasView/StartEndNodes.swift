import SwiftUI

// MARK: - Start/End Nodes

struct StartNodeView: View {
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.85)],
                        center: .center,
                        startRadius: 6,
                        endRadius: 40
                    )
                )
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(AppColors.neonCyan.opacity(0.7), lineWidth: 2)
                        .shadow(color: AppColors.neonCyan.opacity(0.5), radius: 8)
                )
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                )
                .shadow(color: AppColors.neonCyan.opacity(0.25), radius: 9)

            Text("Start")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(width: 80)
    }
}

struct EndNodeView: View {
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.85)],
                        center: .center,
                        startRadius: 6,
                        endRadius: 40
                    )
                )
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(AppColors.neonPink.opacity(0.7), lineWidth: 2)
                        .shadow(color: AppColors.neonPink.opacity(0.5), radius: 8)
                )
                .overlay(
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                )
                .shadow(color: AppColors.neonPink.opacity(0.25), radius: 9)

            Text("End")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(width: 80)
    }
}

