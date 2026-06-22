import SwiftUI

// MARK: - Compact Parameters View

struct EffectParametersViewCompact: View {
    let effectType: EffectType
    @Binding var parameters: NodeEffectParameters
    let tint: Color
    let onChange: () -> Void

    var body: some View {
        LazyVGrid(columns: knobColumns, spacing: 8) {
            switch effectType {
            case .enhancer:
                CompactSlider(label: "Intensity", value: $parameters.enhancerAmount, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .nightDrive:
                CompactSlider(label: "Intensity", value: $parameters.nightDriveIntensity, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Width", value: $parameters.nightDriveWidth, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .chromePunch:
                CompactSlider(label: "Punch", value: $parameters.chromePunchPunch, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Body", value: $parameters.chromePunchBody, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .midnightGlow:
                CompactSlider(label: "Glow", value: $parameters.midnightGlowGlow, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Warmth", value: $parameters.midnightGlowWarmth, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .afterglow:
                CompactSlider(label: "Air", value: $parameters.afterglowAir, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Space", value: $parameters.afterglowSpace, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .bassBoost:
                CompactSlider(label: "Amount", value: $parameters.bassBoostAmount, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .pitchShift:
                EmptyView()

            case .rubberBandPitch:
                CompactSlider(label: "Semitones", value: $parameters.rubberBandPitchSemitones, range: -12...12, format: .semitones, tint: tint, onChange: onChange)

            case .clarity:
                CompactSlider(label: "Amount", value: $parameters.clarityAmount, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .deMud:
                CompactSlider(label: "Strength", value: $parameters.deMudStrength, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .simpleEQ:
                CompactSlider(label: "Bass", value: $parameters.eqBass, range: -1...1, format: .db, tint: tint, onChange: onChange)
                CompactSlider(label: "Mids", value: $parameters.eqMids, range: -1...1, format: .db, tint: tint, onChange: onChange)
                CompactSlider(label: "Treble", value: $parameters.eqTreble, range: -1...1, format: .db, tint: tint, onChange: onChange)

            case .appleThreeBandEQ:
                CompactSlider(label: "Bass", value: $parameters.eqBass, range: -1...1, format: .db, tint: tint, onChange: onChange)
                CompactSlider(label: "Mids", value: $parameters.eqMids, range: -1...1, format: .db, tint: tint, onChange: onChange)
                CompactSlider(label: "Treble", value: $parameters.eqTreble, range: -1...1, format: .db, tint: tint, onChange: onChange)

            case .tenBandEQ:
                CompactSlider(label: "31", value: bandBinding(0), range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "62", value: bandBinding(1), range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "125", value: bandBinding(2), range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "250", value: bandBinding(3), range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "500", value: bandBinding(4), range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "1k", value: bandBinding(5), range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "2k", value: bandBinding(6), range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "4k", value: bandBinding(7), range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "8k", value: bandBinding(8), range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "16k", value: bandBinding(9), range: -12...12, format: .dbValue, tint: tint, onChange: onChange)

            case .compressor:
                CompactSlider(label: "Threshold", value: $parameters.compressorThresholdDB, range: -60...0, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Ratio", value: $parameters.compressorRatio, range: 1...20, format: .ratio, tint: tint, onChange: onChange)
                CompactSlider(label: "Attack", value: $parameters.compressorAttackMS, range: 0.1...200, format: .msValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Release", value: $parameters.compressorReleaseMS, range: 5...2000, format: .msValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Makeup", value: $parameters.compressorMakeupDB, range: -24...24, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.compressorMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .reverb:
                CompactSlider(label: "Mix", value: $parameters.reverbMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Size", value: $parameters.reverbSize, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .stereoWidth:
                CompactSlider(label: "Width", value: $parameters.stereoWidthAmount, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .delay:
                CompactSlider(label: "Time", value: $parameters.delayTime, range: 0.01...2.0, format: .ms, tint: tint, onChange: onChange)
                CompactSlider(label: "Feedback", value: $parameters.delayFeedback, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.delayMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .amp:
                CompactSlider(label: "Input", value: $parameters.ampInputGain, range: -24...24, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Drive", value: $parameters.ampDrive, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Gain", value: $parameters.ampOutputGain, range: -24...24, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.ampMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .distortion:
                CompactSlider(label: "Drive", value: $parameters.distortionDrive, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.distortionMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .tremolo:
                CompactSlider(label: "Rate", value: $parameters.tremoloRate, range: 0.1...20, format: .hz, tint: tint, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.tremoloDepth, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .autoPan:
                CompactSlider(label: "Rate", value: $parameters.autoPanRate, range: 0.05...8, format: .hz, tint: tint, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.autoPanDepth, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .chorus:
                CompactSlider(label: "Rate", value: $parameters.chorusRate, range: 0.1...5, format: .hz, tint: tint, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.chorusDepth, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.chorusMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .phaser:
                CompactSlider(label: "Rate", value: $parameters.phaserRate, range: 0.1...5, format: .hz, tint: tint, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.phaserDepth, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .flanger:
                CompactSlider(label: "Rate", value: $parameters.flangerRate, range: 0.1...5, format: .hz, tint: tint, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.flangerDepth, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Feedback", value: $parameters.flangerFeedback, range: 0...0.95, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.flangerMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .bitcrusher:
                CompactSlider(label: "Bit Depth", value: $parameters.bitcrusherBitDepth, range: 4...16, format: .integer, tint: tint, onChange: onChange)
                CompactSlider(label: "Downsample", value: $parameters.bitcrusherDownsample, range: 1...20, format: .integer, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.bitcrusherMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .tapeSaturation:
                CompactSlider(label: "Drive", value: $parameters.tapeSaturationDrive, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.tapeSaturationMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .resampling:
                CompactSlider(label: "Rate", value: $parameters.resampleRate, range: 0.5...2.0, format: .ratio, tint: tint, onChange: onChange)
                CompactSlider(label: "Smooth", value: $parameters.resampleCrossfade, range: 0.05...0.6, format: .percent, tint: tint, onChange: onChange)

            case .plugin:
                EmptyView()
            }
        }
    }

    private var knobColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 76), spacing: 8)]
    }

    private func bandBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard parameters.tenBandGains.indices.contains(index) else { return 0 }
                return parameters.tenBandGains[index]
            },
            set: { newValue in
                if parameters.tenBandGains.count < 10 {
                    parameters.tenBandGains += Array(repeating: 0, count: 10 - parameters.tenBandGains.count)
                }
                if parameters.tenBandGains.indices.contains(index) {
                    parameters.tenBandGains[index] = newValue
                }
            }
        )
    }
}

struct CompactSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: ValueFormat
    let tint: Color
    let onChange: (() -> Void)?
    @State private var dragStartValue: Double?
    @State private var draftValue: String
    @FocusState private var valueFieldFocused: Bool

    private let knobSize: CGFloat = 54

    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: ValueFormat,
        tint: Color,
        onChange: (() -> Void)? = nil
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.format = format
        self.tint = tint
        self.onChange = onChange
        self._draftValue = State(initialValue: format.editText(for: value.wrappedValue))
    }

    enum ValueFormat {
        case percent
        case db
        case dbValue
        case ms
        case hz
        case integer
        case ratio
        case semitones
        case msValue
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                tint.opacity(0.28),
                                AppColors.controlPurpleRaised.opacity(0.92),
                                AppColors.panelPurple.opacity(0.98)
                            ],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: knobSize
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(AppColors.controlStrokeSoft.opacity(0.82), lineWidth: 1)
                    )
                    .shadow(color: tint.opacity(0.2), radius: 7)

                Circle()
                    .trim(from: 0.10, to: 0.10 + 0.80 * normalizedValue)
                    .stroke(
                        tint.opacity(0.94),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(126))
                    .padding(5)

                Capsule()
                    .fill(AppColors.textPrimary.opacity(0.92))
                    .frame(width: 2.4, height: knobSize * 0.28)
                    .offset(y: -knobSize * 0.18)
                    .rotationEffect(.degrees(-135 + 270 * normalizedValue))
                    .shadow(color: tint.opacity(0.42), radius: 4)
            }
            .frame(width: knobSize, height: knobSize)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let start = dragStartValue ?? value
                        if dragStartValue == nil {
                            dragStartValue = value
                        }
                        let delta = Double(gesture.translation.width - gesture.translation.height)
                        let sensitivity = rangeSpan / 180.0
                        setValue(start + delta * sensitivity)
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                    }
            )
            .help("Drag to adjust \(label)")
            .accessibilityLabel(label)

            HStack(spacing: 1) {
                TextField("", text: $draftValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(tint.opacity(0.96))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .monospacedDigit()
                    .focused($valueFieldFocused)
                    .onSubmit(commitTypedValue)
                    .onChange(of: valueFieldFocused) { _, focused in
                        if focused {
                            draftValue = format.editText(for: value)
                        } else {
                            commitTypedValue()
                        }
                    }
                    .onChange(of: value) { _, newValue in
                        guard !valueFieldFocused else { return }
                        draftValue = format.editText(for: newValue)
                    }
                    .frame(width: valueFieldWidth, height: 18)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(valueFieldFocused ? tint.opacity(0.75) : Color.clear)
                            .frame(height: 1)
                    }
                    .help("Click to type exact \(label)")

                if let unit = format.unitText {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(AppColors.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
    }

    private var safeRange: ClosedRange<Double> {
        guard range.upperBound > range.lowerBound else { return 0...1 }
        return range
    }

    private var rangeSpan: Double {
        max(safeRange.upperBound - safeRange.lowerBound, 0.000001)
    }

    private var normalizedValue: Double {
        let clamped = min(max(value, safeRange.lowerBound), safeRange.upperBound)
        return min(max((clamped - safeRange.lowerBound) / rangeSpan, 0), 1)
    }

    private var valueFieldWidth: CGFloat {
        let characterCount = max(draftValue.count, 1)
        return min(max(CGFloat(characterCount) * 7.2 + 5, 18), 58)
    }

    private func setValue(_ newValue: Double) {
        let clamped = min(max(newValue, safeRange.lowerBound), safeRange.upperBound)
        value = format.roundedValue(clamped)
        draftValue = format.editText(for: value)
        onChange?()
    }

    private func commitTypedValue() {
        let trimmed = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(trimmed), let mapped = format.value(fromDisplayed: parsed) else {
            draftValue = format.editText(for: value)
            return
        }
        setValue(mapped)
    }
}

extension CompactSlider.ValueFormat {
    var unitText: String? {
        switch self {
        case .percent:
            return "%"
        case .db:
            return "dB"
        case .dbValue:
            return "dB"
        case .ms:
            return "ms"
        case .hz:
            return "Hz"
        case .integer:
            return nil
        case .ratio:
            return "x"
        case .semitones:
            return "st"
        case .msValue:
            return "ms"
        }
    }

    func editText(for value: Double) -> String {
        switch self {
        case .percent:
            return String(format: "%.0f", value * 100)
        case .db:
            return String(format: "%+.1f", value * 12.0)
        case .dbValue:
            return String(format: "%+.1f", value)
        case .ms:
            return String(format: "%.0f", value * 1000)
        case .hz:
            return String(format: "%.1f", value)
        case .integer:
            return String(format: "%.0f", value)
        case .ratio:
            return String(format: "%.2f", value)
        case .semitones:
            return String(format: "%+.1f", value)
        case .msValue:
            return String(format: "%.0f", value)
        }
    }

    func value(fromDisplayed displayedValue: Double) -> Double? {
        switch self {
        case .percent:
            return displayedValue / 100.0
        case .db:
            return displayedValue / 12.0
        case .ms:
            return displayedValue / 1000.0
        case .integer:
            return displayedValue.rounded()
        case .dbValue, .hz, .ratio, .semitones, .msValue:
            return displayedValue
        }
    }

    func roundedValue(_ value: Double) -> Double {
        switch self {
        case .integer:
            return value.rounded()
        default:
            return value
        }
    }
}
