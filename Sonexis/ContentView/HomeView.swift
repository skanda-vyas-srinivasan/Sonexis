import SwiftUI

struct HomeView: View {
    let onBuildFromScratch: () -> Void
    let onApplyPresets: () -> Void
    let onTutorial: () -> Void
    let allowBuild: Bool
    let allowPresets: Bool
    @State private var isVisible = false
    @AppStorage("homeHasAppeared") private var homeHasAppeared = false
    @State private var floatTagline = false

    var body: some View {
        ZStack {
            ScanlinesOverlay()

            VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Sonexis")
                    .font(.system(size: 48, weight: .black, design: .default))
                    .foregroundColor(AppColors.neonPink)
                    .shadow(color: AppColors.neonPink.opacity(0.6), radius: 12)
                Text("Shape your system audio in real time")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)
            }

            HStack(spacing: 24) {
                NeonActionButton(
                    title: "Build from scratch",
                    subtitle: "New Project",
                    icon: "wand.and.stars",
                    accent: AppColors.neonCyan,
                    action: onBuildFromScratch
                )
                .disabled(!allowBuild)
                .opacity(allowBuild ? 1.0 : 0.35)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [.buildButton: proxy.frame(in: .global)]
                        )
                    }
                )

                NeonActionButton(
                    title: "Browse presets",
                    subtitle: "Saved Chains",
                    icon: "tray.full",
                    accent: AppColors.neonPink,
                    action: onApplyPresets
                )
                .disabled(!allowPresets)
                .opacity(allowPresets ? 1.0 : 0.35)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [.presetsButton: proxy.frame(in: .global)]
                        )
                    }
                )
            }

            Spacer()

            Text("Made by Skanda Vyas Srinivasan")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textMuted)
                .offset(y: floatTagline ? -6 : 0)
                .opacity(0.9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
        .onAppear {
            isVisible = false
            let duration = homeHasAppeared ? 0.45 : 0.8
            withAnimation(.easeOut(duration: duration)) {
                isVisible = true
            }
            homeHasAppeared = true
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                floatTagline = true
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onTutorial) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }
}

struct NeonActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(accent)
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                    .tracking(0.8)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isHovered ? AppColors.textSecondary : AppColors.textMuted)
            }
            .frame(width: 288, height: 176)
            .background(AppColors.darkPurple)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.midPurple, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(accent, lineWidth: 1)
                    .shadow(color: accent.opacity(0.19), radius: 12)
                    .opacity(isHovered ? 1 : 0)
            )
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: isHovered ? -4 : 0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
