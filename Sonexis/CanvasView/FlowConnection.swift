import SwiftUI

// MARK: - Flow Connection

struct FlowConnection: View {
    let isActive: Bool
    let level: Float
    @State private var animationProgress: CGFloat = 0

    var body: some View {
        let intensity = min(max(Double(level) * 3.0, 0.0), 1.0)
        let glow = AppColors.neonCyan.opacity(0.2 + 0.8 * intensity)
        let baseOpacity = 0.2 + 0.6 * intensity
        let thickness: CGFloat = 2 + CGFloat(intensity) * 3

        ZStack {
            // Base line
            Rectangle()
                .fill(Color.secondary.opacity(baseOpacity))
                .frame(width: 100, height: thickness)

            // Animated flow
            if isActive {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, glow, glow, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 30, height: thickness + 1)
                    .offset(x: animationProgress * 70 - 35)
                    .shadow(color: glow.opacity(0.6), radius: 6, y: 0)
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            animationProgress = 1.0
                        }
                    }
            }
        }
    }
}

