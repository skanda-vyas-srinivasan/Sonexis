import SwiftUI

struct AudioSettingsButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isPresented.toggle()
            }
        } label: {
            Image(systemName: isPresented ? "gearshape.fill" : "gearshape")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppColors.neonCyan)
                .frame(width: 34, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AudioSettingsToolbarStrip: View {
    @Binding var trimDB: Double
    @Binding var makeupDB: Double
    @Binding var ceilingEnabled: Bool
    @Binding var selectedThemeID: String
    let isReadOnly: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AudioSettingsInspectorSlider(
                title: "Input Gain",
                valueText: String(format: "%.0f dB", trimDB),
                value: $trimDB,
                range: -30...0,
                step: 1,
                tint: AppColors.neonCyan
            )
            .frame(width: 136)
            .tutorialTarget(.inputGain)
            .disabled(isReadOnly)

            AudioSettingsGroupDivider()

            AudioSettingsInspectorSlider(
                title: "Output Gain",
                valueText: String(format: "%+.0f dB", makeupDB),
                value: $makeupDB,
                range: -12...30,
                step: 1,
                tint: AppColors.neonPink
            )
            .frame(width: 136)
            .tutorialTarget(.outputGain)
            .disabled(isReadOnly)

            AudioSettingsGroupDivider()

            CeilingToggleRow(isOn: $ceilingEnabled)
                .tutorialTarget(.ceiling)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(isReadOnly)

            AudioSettingsGroupDivider()

            ThemeCompactPicker(selectedThemeID: $selectedThemeID)
                .frame(width: 156, alignment: .leading)
                .layoutPriority(1)
                .disabled(isReadOnly)

            AudioSettingsGroupDivider()

            Button {
                trimDB = ProcessTapRuntimeSettings.defaults.inputTrimDB
                makeupDB = ProcessTapRuntimeSettings.defaults.outputMakeupDB
                ceilingEnabled = ProcessTapRuntimeSettings.defaults.outputCeilingEnabled
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(AppColors.controlPurple.opacity(0.30))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.panelPurple)
        .overlay {
            Rectangle()
                .stroke(AppColors.controlStrokeSoft.opacity(0.58), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .tutorialTarget(.settingsStrip)
    }
}

private struct AudioSettingsGroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.controlStrokeSoft.opacity(0.54))
            .frame(width: 1, height: 28)
    }
}

private struct AudioSettingsInspectorSlider: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                Text(valueText)
                    .font(AppTypography.paramValue)
                    .foregroundColor(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        let steppedValue = (newValue / step).rounded() * step
                        value = min(max(steppedValue, range.lowerBound), range.upperBound)
                    }
                ),
                in: range
            )
            .controlSize(.small)
            .tint(tint)
        }
    }
}

private struct CeilingToggleRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("Ceiling")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(AppColors.warning)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ThemeCompactPicker: View {
    @Binding var selectedThemeID: String

    var body: some View {
        HStack(spacing: 7) {
            Text("Theme")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 4) {
                ForEach(AppTheme.allCases) { theme in
                    ThemeCompactButton(
                        theme: theme,
                        isSelected: selectedThemeID == theme.rawValue
                    ) {
                        selectedThemeID = theme.rawValue
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ThemeCompactButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    private var swatchColor: Color {
        switch theme {
        case .classic:
            return Color(hex: "#7209B7")
        case .magenta:
            return Color(hex: "#FF2DAA")
        case .black:
            return Color(hex: "#747789")
        case .gold:
            return Color(hex: "#FFD21F")
        }
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(swatchColor)
                .frame(width: 11, height: 11)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(theme == .black ? 0.36 : 0), lineWidth: 1)
                )
                .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? AppColors.controlPurpleRaised.opacity(0.56) : AppColors.controlPurple.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? swatchColor.opacity(0.58) : AppColors.controlStrokeSoft.opacity(0.38), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct OutputMeterSection: View {
    let level: Float
    let peakDBFS: Float
    let isActive: Bool

    private var peakText: String {
        guard isActive, peakDBFS > -90 else { return "-inf dB" }
        return String(format: "%.0f dB", peakDBFS)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("Output")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)

                Spacer(minLength: 8)

                Text(peakText)
                    .font(AppTypography.technical)
                    .foregroundColor(isActive ? AppColors.textSecondary : AppColors.textMuted)
                    .monospacedDigit()
            }

            OutputLevelBar(level: level, peakDBFS: peakDBFS, isActive: isActive)
        }
        .frame(width: 176, height: 32)
        .opacity(isActive ? 1 : 0.58)
    }
}

private struct OutputLevelBar: View {
    let level: Float
    let peakDBFS: Float
    let isActive: Bool

    private var normalizedLevel: CGFloat {
        normalized(linear: level)
    }

    private var normalizedPeak: CGFloat {
        guard peakDBFS > -90 else { return 0 }
        return CGFloat(min(max((Double(peakDBFS) + 60) / 60, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let levelWidth = max(isActive ? 2 : 0, width * normalizedLevel)
            let peakX = min(width - 1, max(0, width * normalizedPeak))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(AppColors.deepBlack.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(AppColors.controlStrokeSoft.opacity(0.72), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(AppColors.neonCyan.opacity(isActive ? 0.86 : 0.24))
                    .frame(width: levelWidth)
                    .shadow(color: AppColors.neonCyan.opacity(isActive ? 0.22 : 0), radius: 5)

                if isActive {
                    Rectangle()
                        .fill(AppColors.textPrimary.opacity(0.68))
                        .frame(width: 1.2)
                        .offset(x: peakX)
                }
            }
        }
        .frame(height: 7)
    }

    private func normalized(linear: Float) -> CGFloat {
        let clamped = max(Double(linear), 0.000_001)
        let db = 20 * log10(clamped)
        return CGFloat(min(max((db + 60) / 60, 0), 1))
    }
}
