import SwiftUI

struct HomeView: View {
    let onBuildFromScratch: (CGPoint) -> Void
    let onTutorial: () -> Void
    let allowBuild: Bool
    @State private var isVisible = false
    @AppStorage("homeHasAppeared") private var homeHasAppeared = false
    @State private var floatPrompt = false
    @State private var isHovering = false
    @State private var contentPulse = false
    @State private var isStarting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ScanlinesOverlay()

            VStack(spacing: 18) {
                Spacer()

                VStack(spacing: 10) {
                    Text("Sonexis")
                        .font(.system(size: 64, weight: .black, design: .default))
                        .foregroundColor(AppColors.homeTitle)
                        .shadow(
                            color: AppColors.homeTitle.opacity(contentPulse ? 0.82 : 0.58),
                            radius: contentPulse ? 22 : 12
                        )

                    Text("Click anywhere to start")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppColors.neonCyan)
                        .offset(y: reduceMotion ? 0 : (floatPrompt ? -8 : 0))
                        .shadow(
                            color: AppColors.neonCyan.opacity(contentPulse ? 0.54 : 0.36),
                            radius: contentPulse ? 12 : 7
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TutorialTargetPreferenceKey.self,
                                    value: [.buildButton: proxy.frame(in: .global)]
                                )
                            }
                        )
                }
                .scaleEffect((isHovering ? 1.02 : 1.0) * (reduceMotion ? 1.0 : (contentPulse ? 1.028 : 0.978)))

                Spacer()

                Text("Made by Skanda Vyas Srinivasan")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
                    .opacity(0.9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    startFromClick(at: value.location)
                }
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
        .onAppear {
            isVisible = false
            let duration = homeHasAppeared ? 0.45 : 0.8
            withAnimation(.easeOut(duration: duration)) {
                isVisible = true
            }
            homeHasAppeared = true
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    floatPrompt = true
                }
                withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
                    contentPulse = true
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onTutorial) {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Tutorial")
                        .font(AppTypography.caption)
                }
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.deepBlack.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.midPurple.opacity(0.7), lineWidth: 1)
                )
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }

    private func startFromClick(at location: CGPoint) {
        guard allowBuild, !isStarting else { return }
        isStarting = true
        onBuildFromScratch(location)
    }
}
