import SwiftUI
import AppKit

struct OnboardingOverlay: View {
    let audioEngine: AudioEngine
    let onDone: () -> Void
    @State private var showSkipConfirm = false
    @State private var backdropVisible = false
    @State private var animateIn = false

    var body: some View {
        let blackHoleInstalled = audioEngine.outputDevices.contains { $0.name.localizedCaseInsensitiveContains("BlackHole") }

        ZStack {
            Color.black.opacity(backdropVisible ? 0.6 : 0.0)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        showSkipConfirm = true
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

                Text(blackHoleInstalled ? "Almost Ready!" : "BlackHole Required")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Text(blackHoleInstalled
                        ? "BlackHole is installed! You're ready to go."
                        : "Sonexis needs BlackHole to route your system audio. Install it to get started.")
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)

                    if blackHoleInstalled {
                        Text("⚠️ When you press the power button, Sonexis will automatically switch your system input/output to BlackHole. It will switch back when you turn it off.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.warning)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(AppColors.deepBlack.opacity(0.5))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 20)

                if !blackHoleInstalled {
                    Button {
                        downloadAndOpenBlackHole()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Install BlackHole")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.neonCyan)
                    .padding(.top, 8)
                }

                Button(blackHoleInstalled ? "Continue" : "Skip Setup") {
                    onDone()
                }
                .buttonStyle(.bordered)
                .tint(blackHoleInstalled ? AppColors.neonCyan : AppColors.textSecondary)
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

    private func downloadAndOpenBlackHole() {
        // Look for bundled BlackHole installer in app resources
        guard let installerURL = Bundle.main.url(forResource: "BlackHole2ch-0.6.1 (1)", withExtension: "pkg") else {
            return
        }

        // Open the installer directly from the app bundle
        NSWorkspace.shared.open(installerURL)
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

            Text("Sonexis won't be functional without setting Input and Output to BlackHole. You won't hear sound until you set it up.")
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
