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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.controlPurple.opacity(0.56))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.controlStroke.opacity(0.58), lineWidth: 1)
            )
            .cornerRadius(8)
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
        .background(AppColors.panelPurple.opacity(0.78))
        .overlay(
            LinearGradient(
                colors: [AppColors.controlStroke.opacity(0.32), AppColors.neonCyan.opacity(0.10), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1),
            alignment: .bottom
        )
    }
}
