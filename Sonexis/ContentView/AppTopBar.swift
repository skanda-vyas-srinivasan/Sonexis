import SwiftUI

struct AppTopBar: View {
    let title: String
    let onBack: () -> Void
    let tutorialTarget: TutorialTarget?
    let allowBack: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Home")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(AppColors.textSecondary)
                .frame(minWidth: 74, minHeight: 30)
                .background(AppColors.controlPurple.opacity(0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppColors.controlStroke.opacity(0.58), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
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

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppColors.panelPurple.opacity(0.78))
        .overlay(
            AppColors.controlStroke.opacity(0.32)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
