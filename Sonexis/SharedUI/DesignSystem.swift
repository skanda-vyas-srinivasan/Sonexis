import SwiftUI

struct AppColors {
    static let neonPink = Color(hex: "#FF006E")
    static let neonCyan = Color(hex: "#00F5FF")
    static let electricBlue = Color(hex: "#00D9FF")

    static let synthPurple = Color(hex: "#7209B7")
    static let synthOrange = Color(hex: "#F72585")
    static let synthPink = Color(hex: "#FF006E")

    static let deepBlack = Color(hex: "#0A0A0F")
    static let darkPurple = Color(hex: "#1A0B2E")
    static let midPurple = Color(hex: "#2D1B4E")

    static let success = Color(hex: "#00FF88")
    static let warning = Color(hex: "#FFB800")
    static let error = Color(hex: "#FF0055")
    static let disabled = Color(hex: "#4A4A5E")

    static let textPrimary = Color(hex: "#FFFFFF")
    static let textSecondary = Color(hex: "#B8B8D1")
    static let textMuted = Color(hex: "#6E6E8F")

    static let wireActive = neonCyan
    static let wireInactive = Color(hex: "#3D3D5C")
    static let gridLines = Color(hex: "#1F1F3D")
    static let gridGlow = neonPink.opacity(0.4)
}

struct AppTypography {
    static let title = Font.system(size: 28, weight: .black, design: .default)
    static let heading = Font.system(size: 18, weight: .semibold, design: .default)
    static let technical = Font.system(size: 12, weight: .medium, design: .monospaced)

    static let effectName = Font.system(size: 14, weight: .bold, design: .rounded)
    static let body = Font.system(size: 13, weight: .medium, design: .rounded)
    static let caption = Font.system(size: 11, weight: .regular, design: .rounded)

    static let paramValue = Font.system(size: 12, weight: .semibold, design: .monospaced)
}

struct AppGradients {
    static let background = LinearGradient(
        colors: [AppColors.deepBlack, AppColors.darkPurple, AppColors.deepBlack],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let nodeAccent = LinearGradient(
        colors: [AppColors.synthPurple, AppColors.synthOrange, AppColors.synthPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glow = RadialGradient(
        colors: [AppColors.neonCyan.opacity(0.8), AppColors.neonCyan.opacity(0.2), .clear],
        center: .center,
        startRadius: 5,
        endRadius: 40
    )
}

struct AnimatedGrid: View {
    let intensity: Double

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let offset = CGFloat(time.truncatingRemainder(dividingBy: 30))
            Canvas { context, size in
                let spacing: CGFloat = 30
                var path = Path()
                for x in stride(from: -offset, through: size.width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: -offset, through: size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(
                    path,
                    with: .color(AppColors.gridLines.opacity(0.6 + 0.4 * intensity)),
                    lineWidth: 1
                )
            }
        }
    }
}

final class GridPathCache: ObservableObject {
    private var cachedSize: CGSize = .zero
    private var cachedPath = Path()

    func path(for size: CGSize) -> Path {
        guard size != cachedSize else { return cachedPath }
        cachedSize = size

        let spacing: CGFloat = 30
        var path = Path()
        for x in stride(from: 0, through: size.width, by: spacing) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: 0, through: size.height, by: spacing) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }

        cachedPath = path
        return path
    }
}

struct StaticGrid: View {
    @StateObject private var cache = GridPathCache()

    var body: some View {
        Canvas { context, size in
            let path = cache.path(for: size)
            context.stroke(path, with: .color(AppColors.gridLines.opacity(0.5)), lineWidth: 1)
        }
    }
}

struct ScanlinesOverlay: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let offset = CGFloat(time.truncatingRemainder(dividingBy: 1.6)) * 18
            Canvas { context, size in
                var path = Path()
                let spacing: CGFloat = 16
                for y in stride(from: -offset, through: size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
            }
        }
        .blendMode(.screen)
    }
}

struct GlitchOverlay: View {
    @State private var phase: CGFloat = 0
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.white.opacity(0.25 * (1 - phase))

            VStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Rectangle()
                        .fill(AppColors.neonCyan.opacity(0.12 + Double(index) * 0.04))
                        .frame(height: 18)
                        .offset(x: phase * CGFloat(12 + index * 6))
                        .blur(radius: 1.5)
                }
            }
            .padding(.horizontal, 40)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.15)) {
                phase = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                onComplete()
            }
        }
    }
}

extension Color {
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
