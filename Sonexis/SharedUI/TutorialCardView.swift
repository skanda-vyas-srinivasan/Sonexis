import SwiftUI

struct TutorialCardView: View {
    let title: String
    let message: String
    let showNext: Bool
    let onNext: () -> Void
    let onSkip: () -> Void
    let showSetupButtons: Bool
    let onOpenSetup: (() -> Void)?

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
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button("Skip") {
                    onSkip()
                }
                .buttonStyle(.plain)
                .foregroundColor(AppColors.textMuted)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }

            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(AppColors.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if showSetupButtons {
                HStack(spacing: 12) {
                    Button("Exit Tutorial") {
                        onSkip()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.neonPink)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(AppColors.neonPink.opacity(0.62), lineWidth: 1)
                    )

                    Button("Open Setup") {
                        onOpenSetup?()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.textPrimary)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(AppColors.neonCyan.opacity(0.72))
                    )
                }
            } else if showNext {
                Button(action: onNext) {
                    HStack(spacing: 6) {
                        Text("Next")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(AppColors.neonCyan.opacity(0.72))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppColors.deepBlack.opacity(0.96))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColors.controlStrokeSoft.opacity(0.78), lineWidth: 1)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.neonCyan.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.34), radius: 10, y: 5)
    }
}
