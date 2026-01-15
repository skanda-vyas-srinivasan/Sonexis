import SwiftUI

struct AppTopBar: View {
    let title: String
    let onBack: () -> Void
    let tutorialTarget: TutorialTarget?
    let allowBack: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                Text("Home")
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.textSecondary)
            .disabled(!allowBack)
            .opacity(allowBack ? 1.0 : 0.35)
            .background(
                GeometryReader { proxy in
                    if let tutorialTarget {
                        Color.clear.preference(
                            key: TutorialTargetPreferenceKey.self,
                            value: [tutorialTarget: proxy.frame(in: .global)]
                        )
                    }
                }
            )

            Text(title)
                .font(AppTypography.technical)
                .foregroundColor(AppColors.textMuted)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppColors.deepBlack.opacity(0.7))
    }
}

