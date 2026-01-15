import SwiftUI

struct TutorialCardView: View {
    let title: String
    let message: String
    let showNext: Bool
    let onNext: () -> Void
    let onSkip: () -> Void
    let showSetupButtons: Bool
    let onOpenSetup: (() -> Void)?

    @State private var glowPulse = false

    init(
        title: String,
        message: String,
        showNext: Bool,
        onNext: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        showSetupButtons: Bool = false,
        onOpenSetup: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.showNext = showNext
        self.onNext = onNext
        self.onSkip = onSkip
        self.showSetupButtons = showSetupButtons
        self.onOpenSetup = onOpenSetup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(AppTypography.heading)
                    .foregroundColor(AppColors.textPrimary)
                    .shadow(color: AppColors.neonCyan.opacity(0.4), radius: 6)

                Spacer()

                Button("Skip") {
                    onSkip()
                }
                .buttonStyle(.plain)
                .foregroundColor(AppColors.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(AppColors.darkPurple.opacity(0.5))
                )
            }

            Text(message)
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if showSetupButtons {
                HStack(spacing: 12) {
                    Button("Exit Tutorial") {
                        onSkip()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.neonPink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .stroke(AppColors.neonPink, lineWidth: 1.5)
                    )

                    Button("Open Setup") {
                        onOpenSetup?()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.neonCyan, AppColors.neonPink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: AppColors.neonCyan.opacity(0.4), radius: 12)
                }
            } else if showNext {
                Button(action: onNext) {
                    HStack(spacing: 6) {
                        Text("Next")
                            .font(AppTypography.body)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.neonCyan, AppColors.neonPink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: AppColors.neonCyan.opacity(0.4), radius: 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.deepBlack,
                                AppColors.darkPurple,
                                AppColors.gridLines
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppColors.neonCyan.opacity(0.8),
                                AppColors.neonPink.opacity(0.9),
                                AppColors.synthOrange.opacity(0.7)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                    .blur(radius: 2)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    .padding(2)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppColors.neonCyan.opacity(glowPulse ? 0.9 : 0.45), lineWidth: 4)
                .blur(radius: glowPulse ? 18 : 6)
                .opacity(glowPulse ? 1 : 0.6)
        )
        .shadow(color: AppColors.neonPink.opacity(0.4), radius: 25, y: 10)
        .scaleEffect(glowPulse ? 1.02 : 0.98)
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.8)
                    .repeatForever(autoreverses: true)
            ) {
                glowPulse.toggle()
            }
        }
    }
}
