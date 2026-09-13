import SwiftUI

enum AppScreen {
    case home
    case presets
    case beginner
}

struct HomeTransitionRipple: Equatable {
    let id = UUID()
    let origin: CGPoint
}

struct HomeTransitionRippleView: View {
    let ripple: HomeTransitionRipple
    @State private var backdropVisible = false
    @State private var expanded = false
    @State private var fading = false
    private let expansionDuration: TimeInterval = 0.30
    private let fadeDelay: TimeInterval = 0.20
    private let fadeDuration: TimeInterval = 0.24

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let diameter = transitionDiameter(for: size)

            ZStack {
                AppColors.deepBlack
                    .opacity(fading ? 0 : (backdropVisible ? 0.34 : 0))
                    .ignoresSafeArea()

                Circle()
                    .fill(AppColors.midPurple.opacity(expanded ? 0.48 : 0.72))
                    .overlay(
                        Circle()
                            .stroke(AppColors.neonCyan.opacity(fading ? 0 : (expanded ? 0.14 : 0.8)), lineWidth: expanded ? 1 : 2)
                    )
                    .frame(width: expanded ? diameter : 18, height: expanded ? diameter : 18)
                    .shadow(color: AppColors.neonCyan.opacity(fading ? 0 : (expanded ? 0.2 : 0.9)), radius: expanded ? 28 : 10)
                    .opacity(fading ? 0 : 1)
                    .position(ripple.origin)
                    .ignoresSafeArea()
            }
            .onAppear {
                    withAnimation(.easeOut(duration: 0.12)) {
                        backdropVisible = true
                    }
                    withAnimation(.timingCurve(0.16, 0.84, 0.24, 1.0, duration: expansionDuration)) {
                        expanded = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + fadeDelay) {
                        withAnimation(.easeOut(duration: fadeDuration)) {
                            fading = true
                        }
                    }
            }
        }
    }

    private func transitionDiameter(for size: CGSize) -> CGFloat {
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height)
        ]
        let maxDistance = corners.map { corner in
            hypot(corner.x - ripple.origin.x, corner.y - ripple.origin.y)
        }.max() ?? max(size.width, size.height)
        return maxDistance * 2.2
    }
}
