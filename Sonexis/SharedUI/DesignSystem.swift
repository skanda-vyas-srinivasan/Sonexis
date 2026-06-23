import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    static let storageKey = "Sonexis.ColorTheme"
    static let defaultThemeID = AppTheme.black.rawValue

    case black
    case classic
    case magenta
    case gold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:
            return "Classic"
        case .magenta:
            return "Magenta"
        case .black:
            return "Black"
        case .gold:
            return "Gold"
        }
    }

    var shortName: String {
        switch self {
        case .classic:
            return "Classic"
        case .magenta:
            return "Magenta"
        case .black:
            return "Black"
        case .gold:
            return "Gold"
        }
    }

    static func theme(for id: String) -> AppTheme {
        if id == "cream" { return .gold }
        return AppTheme(rawValue: id) ?? .black
    }

    var colorScheme: ColorScheme {
        switch self {
        case .classic, .magenta, .black, .gold:
            return .dark
        }
    }

    var palette: AppColorPalette {
        switch self {
        case .classic:
            return AppColorPalette(
                neonPink: Color(hex: "#FF006E"),
                neonCyan: Color(hex: "#00F5FF"),
                electricBlue: Color(hex: "#00D9FF"),
                synthPurple: Color(hex: "#7209B7"),
                synthOrange: Color(hex: "#F72585"),
                synthPink: Color(hex: "#FF006E"),
                deepBlack: Color(hex: "#12071F"),
                darkPurple: Color(hex: "#211039"),
                midPurple: Color(hex: "#38215E"),
                panelPurple: Color(hex: "#1A0C2C"),
                controlPurple: Color(hex: "#271642"),
                controlPurpleRaised: Color(hex: "#321D55"),
                controlStroke: Color(hex: "#5B4678"),
                controlStrokeSoft: Color(hex: "#443158"),
                success: Color(hex: "#00FF88"),
                warning: Color(hex: "#FFB800"),
                error: Color(hex: "#FF0055"),
                disabled: Color(hex: "#4A4A5E"),
                textPrimary: Color(hex: "#FFFFFF"),
                textSecondary: Color(hex: "#B8B8D1"),
                textMuted: Color(hex: "#6E6E8F"),
                wireInactive: Color(hex: "#53406D"),
                gridLines: Color(hex: "#2A1B46"),
                homeTitle: Color(hex: "#FF006E")
            )
        case .magenta:
            return AppColorPalette(
                neonPink: Color(hex: "#FF2DAA"),
                neonCyan: Color(hex: "#53E6FF"),
                electricBlue: Color(hex: "#3DA8FF"),
                synthPurple: Color(hex: "#B437FF"),
                synthOrange: Color(hex: "#FFB000"),
                synthPink: Color(hex: "#FF2DAA"),
                deepBlack: Color(hex: "#21051D"),
                darkPurple: Color(hex: "#45113C"),
                midPurple: Color(hex: "#7A246A"),
                panelPurple: Color(hex: "#310A2A"),
                controlPurple: Color(hex: "#4C1541"),
                controlPurpleRaised: Color(hex: "#662159"),
                controlStroke: Color(hex: "#A94A91"),
                controlStrokeSoft: Color(hex: "#7A3A6A"),
                success: Color(hex: "#00FF9C"),
                warning: Color(hex: "#FFD166"),
                error: Color(hex: "#FF3B73"),
                disabled: Color(hex: "#704765"),
                textPrimary: Color(hex: "#FFF7FF"),
                textSecondary: Color(hex: "#F0C8EA"),
                textMuted: Color(hex: "#BB84B0"),
                wireInactive: Color(hex: "#864276"),
                gridLines: Color(hex: "#4D1947"),
                homeTitle: Color(hex: "#FF2DAA")
            )
        case .black:
            return AppColorPalette(
                neonPink: Color(hex: "#FF2D95"),
                neonCyan: Color(hex: "#20F4FF"),
                electricBlue: Color(hex: "#2E9BFF"),
                synthPurple: Color(hex: "#7B2CFF"),
                synthOrange: Color(hex: "#FFB000"),
                synthPink: Color(hex: "#FF2D95"),
                deepBlack: Color(hex: "#030307"),
                darkPurple: Color(hex: "#080812"),
                midPurple: Color(hex: "#12101F"),
                panelPurple: Color(hex: "#060611"),
                controlPurple: Color(hex: "#10101C"),
                controlPurpleRaised: Color(hex: "#181827"),
                controlStroke: Color(hex: "#343449"),
                controlStrokeSoft: Color(hex: "#242435"),
                success: Color(hex: "#00FF88"),
                warning: Color(hex: "#FFC857"),
                error: Color(hex: "#FF3868"),
                disabled: Color(hex: "#3C3C48"),
                textPrimary: Color(hex: "#F8FAFF"),
                textSecondary: Color(hex: "#C5C8D8"),
                textMuted: Color(hex: "#747789"),
                wireInactive: Color(hex: "#343449"),
                gridLines: Color(hex: "#141421"),
                homeTitle: Color(hex: "#FF2D95")
            )
        case .gold:
            return AppColorPalette(
                neonPink: Color(hex: "#FFD21F"),
                neonCyan: Color(hex: "#F4F7FF"),
                electricBlue: Color(hex: "#DDE8FF"),
                synthPurple: Color(hex: "#F8FAFF"),
                synthOrange: Color(hex: "#FFB000"),
                synthPink: Color(hex: "#FFE38A"),
                deepBlack: Color(hex: "#050302"),
                darkPurple: Color(hex: "#120A04"),
                midPurple: Color(hex: "#241504"),
                panelPurple: Color(hex: "#0D0703"),
                controlPurple: Color(hex: "#2A1A0A"),
                controlPurpleRaised: Color(hex: "#3B260F"),
                controlStroke: Color(hex: "#9D6A20"),
                controlStrokeSoft: Color(hex: "#5F421A"),
                success: Color(hex: "#00E28A"),
                warning: Color(hex: "#FFBF32"),
                error: Color(hex: "#FF416D"),
                disabled: Color(hex: "#5E5547"),
                textPrimary: Color(hex: "#FFF2D2"),
                textSecondary: Color(hex: "#D8BE82"),
                textMuted: Color(hex: "#9D7A42"),
                wireInactive: Color(hex: "#5F421A"),
                gridLines: Color(hex: "#241707"),
                homeTitle: Color(hex: "#FFD21F")
            )
        }
    }
}

struct AppColorPalette {
    let neonPink: Color
    let neonCyan: Color
    let electricBlue: Color
    let synthPurple: Color
    let synthOrange: Color
    let synthPink: Color
    let deepBlack: Color
    let darkPurple: Color
    let midPurple: Color
    let panelPurple: Color
    let controlPurple: Color
    let controlPurpleRaised: Color
    let controlStroke: Color
    let controlStrokeSoft: Color
    let success: Color
    let warning: Color
    let error: Color
    let disabled: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let wireInactive: Color
    let gridLines: Color
    let homeTitle: Color
}

struct AppColors {
    private static var palette: AppColorPalette {
        let id = UserDefaults.standard.string(forKey: AppTheme.storageKey) ?? AppTheme.defaultThemeID
        return AppTheme.theme(for: id).palette
    }

    static var neonPink: Color { palette.neonPink }
    static var neonCyan: Color { palette.neonCyan }
    static var electricBlue: Color { palette.electricBlue }

    static var synthPurple: Color { palette.synthPurple }
    static var synthOrange: Color { palette.synthOrange }
    static var synthPink: Color { palette.synthPink }

    static var deepBlack: Color { palette.deepBlack }
    static var darkPurple: Color { palette.darkPurple }
    static var midPurple: Color { palette.midPurple }
    static var panelPurple: Color { palette.panelPurple }
    static var controlPurple: Color { palette.controlPurple }
    static var controlPurpleRaised: Color { palette.controlPurpleRaised }
    static var controlStroke: Color { palette.controlStroke }
    static var controlStrokeSoft: Color { palette.controlStrokeSoft }

    static var success: Color { palette.success }
    static var warning: Color { palette.warning }
    static var error: Color { palette.error }
    static var disabled: Color { palette.disabled }

    static var textPrimary: Color { palette.textPrimary }
    static var textSecondary: Color { palette.textSecondary }
    static var textMuted: Color { palette.textMuted }

    static var wireActive: Color { neonCyan }
    static var wireInactive: Color { palette.wireInactive }
    static var gridLines: Color { palette.gridLines }
    static var gridGlow: Color { neonPink.opacity(0.4) }
    static var homeTitle: Color { palette.homeTitle }
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

struct AppSurfaces {
    static var background: Color {
        AppColors.darkPurple
    }
}

struct SonexisFloatingPanelStyle: ViewModifier {
    let tint: Color
    var cornerRadius: CGFloat = 12
    var glowOpacity: Double = 0.16

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppColors.panelPurple.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.controlStrokeSoft.opacity(0.85), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.28), radius: 8, y: 4)
    }
}

extension View {
    func sonexisFloatingPanel(
        tint: Color,
        cornerRadius: CGFloat = 12,
        glowOpacity: Double = 0.16
    ) -> some View {
        modifier(SonexisFloatingPanelStyle(tint: tint, cornerRadius: cornerRadius, glowOpacity: glowOpacity))
    }
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
