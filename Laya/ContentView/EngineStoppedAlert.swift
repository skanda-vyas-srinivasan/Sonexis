import SwiftUI

struct EngineStoppedAlert: View {
    let onDismiss: () -> Void
    @State private var backdropVisible = false
    @State private var animateIn = false

    var body: some View {
        ZStack {
            Color.black.opacity(backdropVisible ? 0.7 : 0.0)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Audio Engine Stopped")
                    .font(AppTypography.heading)
                    .foregroundColor(AppColors.neonPink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Oops, looks like something happened with your input and output and the engine turned off. We have to stop the tutorial here.")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)

                Button("Exit Tutorial") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.neonPink)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.midPurple.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppColors.neonPink.opacity(0.6), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 420)
            .shadow(color: Color.black.opacity(0.3), radius: 12, y: 6)
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : -30)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6)) {
                backdropVisible = true
            }
            withAnimation(.easeOut(duration: 0.5)) {
                animateIn = true
            }
        }
    }
}

