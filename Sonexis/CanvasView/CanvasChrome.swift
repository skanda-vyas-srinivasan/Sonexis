import SwiftUI

struct CanvasToolbarMenuLabel: View {
    let title: String
    let value: String?
    let tint: Color
    @State var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)

            if let value {
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(tint)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(tint.opacity(0.82))
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? AppColors.controlPurpleRaised.opacity(0.70) : AppColors.controlPurple.opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isHovered ? tint.opacity(0.52) : AppColors.controlStrokeSoft.opacity(0.52), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }
}

struct CanvasWaveLinesBackground: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let width = max(size.width, 1)
                let height = max(size.height, 1)
                let centerY = height * 0.5
                let offsets: [CGFloat] = [-0.34, -0.17, 0.17, 0.34]
                let colors: [Color] = [
                    AppColors.neonCyan,
                    AppColors.neonPink,
                    AppColors.neonPink,
                    AppColors.neonCyan
                ]

                for index in offsets.indices {
                    var path = Path()
                    let drift = CGFloat(sin((time * 0.28) + Double(index) * 1.7)) * height * 0.018
                    let yBase = centerY + (height * offsets[index]) + drift
                    let amplitude = height * (index.isMultiple(of: 2) ? 0.021 : 0.017)
                    let wavelength = width * (index.isMultiple(of: 2) ? 0.68 : 0.74)
                    let phase = CGFloat(time * 0.22) + CGFloat(index) * 1.35

                    for x in stride(from: CGFloat(0), through: width, by: 12) {
                        let y = yBase + sin((x / wavelength * .pi * 2) + phase) * amplitude
                        if x == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    context.stroke(
                        path,
                        with: .color(colors[index].opacity(0.20)),
                        style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
