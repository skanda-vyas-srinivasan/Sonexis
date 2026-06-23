import SwiftUI

enum HomeSignalVisualSettings {
    static let signalIntensity = 0.45
}

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
                        .foregroundColor(AppColors.homeTitle)
                        .shadow(
                            color: AppColors.homeTitle.opacity(contentPulse ? 0.82 : 0.58),
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
    @State private var animationStart = Date()

    private let barHeights: [CGFloat] = [36, 64, 48, 90, 58, 74, 42, 82, 52, 68, 38]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            TimelineView(.animation) { context in
                let elapsed = max(0, context.date.timeIntervalSince(animationStart))
                let pulse = reduceMotion ? 0.5 : breathingPhase(elapsed: elapsed, offset: 0, cycle: 7.8)
                let signalIntensity = HomeSignalVisualSettings.signalIntensity
                let ringBase = min(width, height)
                let outerRingSize = ringBase * 0.78
                let innerRingSize = ringBase * 0.54
                let outerRingScale = 0.94 + (0.14 * pulse)
                let innerRingScale = 1.04 - (0.12 * pulse)
                let ringLineWidth: CGFloat = 0.9 + (0.80 * signalIntensity)
                let outerRingOpacity = 0.18 + (0.38 * signalIntensity) - (0.07 * pulse)
                let innerRingOpacity = 0.14 + (0.34 * signalIntensity) + (0.07 * pulse)
                let outerRingShadow = 0.12 + (0.30 * signalIntensity)
                let innerRingShadow = 0.10 + (0.28 * signalIntensity)
                let haloLineWidth: CGFloat = 1.8 + (3.2 * signalIntensity)
                let haloBlur = 1.2 + (3.0 * signalIntensity)

                ZStack {
                    Circle()
                        .stroke(AppColors.neonPink.opacity(0.03 + (0.15 * signalIntensity)), lineWidth: haloLineWidth)
                        .frame(width: outerRingSize)
                        .scaleEffect(outerRingScale)
                        .blur(radius: haloBlur)

                    Circle()
                        .stroke(AppColors.neonCyan.opacity(0.03 + (0.13 * signalIntensity)), lineWidth: haloLineWidth * 0.86)
                        .frame(width: innerRingSize)
                        .scaleEffect(innerRingScale)
                        .blur(radius: haloBlur * 0.9)

                    Circle()
                        .stroke(AppColors.neonPink.opacity(outerRingOpacity), lineWidth: ringLineWidth)
                        .frame(width: outerRingSize)
                        .scaleEffect(outerRingScale)
                        .blur(radius: 0.75)
                        .shadow(color: AppColors.neonPink.opacity(outerRingShadow), radius: 8 + (8 * signalIntensity))

                    Circle()
                        .stroke(AppColors.neonCyan.opacity(innerRingOpacity), lineWidth: ringLineWidth)
                        .frame(width: innerRingSize)
                        .scaleEffect(innerRingScale)
                        .blur(radius: 0.68)
                        .shadow(color: AppColors.neonCyan.opacity(innerRingShadow), radius: 7 + (7 * signalIntensity))

                    HStack(alignment: .center, spacing: 12) {
                        ForEach(Array(barHeights.enumerated()), id: \.offset) { index, barHeight in
                            let barPulse = reduceMotion ? 0.64 : breathingPhase(
                                elapsed: elapsed,
                                offset: 0,
                                cycle: 6.8
                            )
                            let heightScale = 0.34 + (0.46 * barPulse)
                            let barColor = index.isMultiple(of: 2) ? AppColors.neonCyan : AppColors.neonPink
                            let barOpacity = index.isMultiple(of: 2)
                                ? 0.22 + (0.30 * signalIntensity)
                                : 0.20 + (0.26 * signalIntensity)
                            let barShadow = 0.16 + (0.28 * signalIntensity)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(barColor.opacity(barOpacity))
                                .frame(width: 6, height: isActive ? max(14, barHeight * heightScale) : 8)
                                .shadow(color: barColor.opacity(barShadow), radius: 8 + (8 * signalIntensity))
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
        .onAppear {
            animationStart = Date()
        }
    }

    private func breathingPhase(elapsed: TimeInterval, offset: TimeInterval, cycle: TimeInterval) -> CGFloat {
        let progress = ((elapsed + offset) / cycle).truncatingRemainder(dividingBy: 1)
        return CGFloat((1 - cos(progress * .pi * 2)) / 2)
    }
}
