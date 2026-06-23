import SwiftUI
import AppKit

struct OnboardingOverlay: View {
    let audioEngine: AudioEngine
    let onDone: () -> Void
    @State private var showSkipConfirm = false
    @State private var backdropVisible = false
    @State private var animateIn = false

    var body: some View {
        ZStack {
            Color.black.opacity(backdropVisible ? 0.6 : 0.0)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        onDone()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(6)
                            .background(AppColors.deepBlack.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Process Tap Ready")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Text("Sonexis captures system audio with macOS Process Taps and plays the processed signal through your current output device.")
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)

                    Text("No virtual audio device or manual output switching is required.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.warning)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(AppColors.deepBlack.opacity(0.5))
                        .cornerRadius(8)
                }
                .padding(.horizontal, 20)

                Button("Continue") {
                    onDone()
                }
                .buttonStyle(.bordered)
                .tint(AppColors.neonCyan)
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.midPurple.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppColors.neonCyan.opacity(0.6), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 420)
            .shadow(color: Color.black.opacity(0.3), radius: 12, y: 6)
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : -30)
        }
        .overlay(
            Group {
                if showSkipConfirm {
                    SkipSetupConfirm(
                        onCancel: { showSkipConfirm = false },
                        onSkip: {
                            showSkipConfirm = false
                            onDone()
                        }
                    )
                    .transition(.opacity)
                }
            }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            animateIn = false
            withAnimation(.easeInOut(duration: 0.9)) {
                backdropVisible = true
            }
            withAnimation(.easeOut(duration: 0.7)) {
                animateIn = true
            }
        }
    }

}

private struct SkipSetupConfirm: View {
    let onCancel: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Skip setup?")
                .font(AppTypography.heading)
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("You can continue, but Sonexis needs audio capture permission before processing system audio.")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 10) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .tint(AppColors.textSecondary)

                Button("Skip") {
                    onSkip()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.neonPink)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.midPurple.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.neonPink.opacity(0.6), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 6)
        .frame(maxWidth: 420)
    }
}
