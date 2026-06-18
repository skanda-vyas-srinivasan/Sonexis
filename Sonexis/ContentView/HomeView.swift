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

            HomeSignalBackdrop(isActive: isVisible, reduceMotion: reduceMotion)

            VStack(spacing: 18) {
                Spacer()

                VStack(spacing: 10) {
                    Text("Sonexis")
                        .font(.system(size: 56, weight: .black, design: .default))
                        .foregroundColor(AppColors.neonPink)
                        .shadow(
                            color: AppColors.neonPink.opacity(contentPulse ? 0.82 : 0.58),
                            radius: contentPulse ? 22 : 12
                        )

                    Text("Click anywhere to start")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isHovering ? AppColors.neonCyan : AppColors.textSecondary)
                        .offset(y: reduceMotion ? 0 : (floatPrompt ? -8 : 0))
                        .shadow(
                            color: AppColors.neonCyan.opacity(isHovering ? 0.7 : (contentPulse ? 0.46 : 0.24)),
                            radius: isHovering ? 14 : (contentPulse ? 11 : 6)
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

private struct HomeSignalBackdrop: View {
    let isActive: Bool
    let reduceMotion: Bool

    private let barHeights: [CGFloat] = [72, 128, 96, 180, 116, 148, 84, 164, 104, 136, 76]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            TimelineView(.animation) { context in
                let pulse = reduceMotion ? 0.5 : phase(at: context.date, offset: 0)

                ZStack {
                    Circle()
                        .stroke(AppColors.neonPink.opacity(0.22 - (0.12 * pulse)), lineWidth: 1)
                        .frame(width: min(width, height) * 0.78)
                        .scaleEffect(0.94 + (0.14 * pulse))
                        .blur(radius: 1)

                    Circle()
                        .stroke(AppColors.neonCyan.opacity(0.10 + (0.14 * pulse)), lineWidth: 1)
                        .frame(width: min(width, height) * 0.54)
                        .scaleEffect(1.04 - (0.12 * pulse))
                        .blur(radius: 1)

                    HStack(alignment: .center, spacing: 12) {
                        ForEach(Array(barHeights.enumerated()), id: \.offset) { index, barHeight in
                            let barPulse = reduceMotion ? 0.5 : phase(at: context.date, offset: Double(index) * 0.08)
                            let heightScale = 0.82 + (0.26 * barPulse)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(index.isMultiple(of: 2) ? AppColors.neonCyan.opacity(0.22) : AppColors.neonPink.opacity(0.18))
                                .frame(width: 6, height: isActive ? barHeight * heightScale : 24)
                                .shadow(color: AppColors.neonCyan.opacity(0.18), radius: 12)
                        }
                    }
                    .scaleEffect(x: 0.985 + (0.03 * pulse), y: 1.02 - (0.04 * pulse))
                    .opacity(0.78 + (0.15 * pulse))
                    .offset(y: 86)
                }
                .frame(width: width, height: height)
            }
            .animation(.easeInOut(duration: 1.6), value: isActive)
            .allowsHitTesting(false)
        }
    }

    private func phase(at date: Date, offset: TimeInterval) -> CGFloat {
        let cycle = 3.4
        let radians = ((date.timeIntervalSinceReferenceDate + offset) / cycle) * .pi * 2
        return CGFloat((sin(radians) + 1) / 2)
    }
}
