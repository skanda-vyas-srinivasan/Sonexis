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
                Text("Laya")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.neonPink)
                    .shadow(color: AppColors.neonPink.opacity(0.6), radius: 12)
                Text("Audio Shaping for System Sound")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)
            }

            HStack(spacing: 16) {
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
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(accent)
                Text(title.uppercased())
                    .font(AppTypography.heading)
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
            }
            .frame(width: 240, height: 150)
            .background(AppColors.midPurple)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isHovered ? accent : AppColors.neonCyan.opacity(0.4), lineWidth: 2)
            )
            .cornerRadius(16)
            .shadow(color: accent.opacity(isHovered ? 0.5 : 0.15), radius: isHovered ? 18 : 8)
            .scaleEffect(isHovered ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
