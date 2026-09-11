import SwiftUI
import AppKit

// MARK: - Compact Parameters View

struct EffectParametersViewCompact: View {
    let effectType: EffectType
    @Binding var parameters: NodeEffectParameters
    let tint: Color
    let onChange: () -> Void

    var body: some View {
        Group {
            if shouldScroll {
                ScrollView {
                    parameterGrid
                        .padding(.trailing, 6)
                }
                .frame(height: cappedGridHeight)
                .scrollIndicators(.visible)
            } else {
                parameterGrid
            }
        }
    }

    @ViewBuilder
    private var parameterGrid: some View {
        LazyVGrid(columns: knobColumns, alignment: .center, spacing: 10) {
            switch effectType {
            case .enhancer:
                CompactSlider(label: "Intensity", value: $parameters.enhancerAmount, defaultValue: NodeEffectParameters.defaults().enhancerAmount, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .nightDrive:
                CompactSlider(label: "Intensity", value: $parameters.nightDriveIntensity, defaultValue: NodeEffectParameters.defaults().nightDriveIntensity, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Width", value: $parameters.nightDriveWidth, defaultValue: NodeEffectParameters.defaults().nightDriveWidth, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .chromePunch:
                CompactSlider(label: "Punch", value: $parameters.chromePunchPunch, defaultValue: NodeEffectParameters.defaults().chromePunchPunch, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Body", value: $parameters.chromePunchBody, defaultValue: NodeEffectParameters.defaults().chromePunchBody, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .midnightGlow:
                CompactSlider(label: "Glow", value: $parameters.midnightGlowGlow, defaultValue: NodeEffectParameters.defaults().midnightGlowGlow, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Warmth", value: $parameters.midnightGlowWarmth, defaultValue: NodeEffectParameters.defaults().midnightGlowWarmth, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .afterglow:
                CompactSlider(label: "Air", value: $parameters.afterglowAir, defaultValue: NodeEffectParameters.defaults().afterglowAir, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Space", value: $parameters.afterglowSpace, defaultValue: NodeEffectParameters.defaults().afterglowSpace, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .bassBoost:
                CompactSlider(label: "Amount", value: $parameters.bassBoostAmount, defaultValue: NodeEffectParameters.defaults().bassBoostAmount, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .pitchShift:
                EmptyView()

            case .rubberBandPitch:
                CompactSlider(label: "Semitones", value: $parameters.rubberBandPitchSemitones, defaultValue: NodeEffectParameters.defaults().rubberBandPitchSemitones, range: -12...12, format: .semitones, tint: tint, onChange: onChange)

            case .clarity:
                CompactSlider(label: "Amount", value: $parameters.clarityAmount, defaultValue: NodeEffectParameters.defaults().clarityAmount, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .deMud:
                CompactSlider(label: "Strength", value: $parameters.deMudStrength, defaultValue: NodeEffectParameters.defaults().deMudStrength, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .simpleEQ:
                CompactSlider(label: "Bass", value: $parameters.eqBass, defaultValue: NodeEffectParameters.defaults().eqBass, range: -1...1, format: .db, tint: tint, onChange: onChange)
                CompactSlider(label: "Mids", value: $parameters.eqMids, defaultValue: NodeEffectParameters.defaults().eqMids, range: -1...1, format: .db, tint: tint, onChange: onChange)
                CompactSlider(label: "Treble", value: $parameters.eqTreble, defaultValue: NodeEffectParameters.defaults().eqTreble, range: -1...1, format: .db, tint: tint, onChange: onChange)

            case .appleThreeBandEQ:
                CompactSlider(label: "Bass", value: $parameters.eqBass, defaultValue: NodeEffectParameters.defaults().eqBass, range: -1...1, format: .db, tint: tint, onChange: onChange)
                CompactSlider(label: "Mids", value: $parameters.eqMids, defaultValue: NodeEffectParameters.defaults().eqMids, range: -1...1, format: .db, tint: tint, onChange: onChange)
                CompactSlider(label: "Treble", value: $parameters.eqTreble, defaultValue: NodeEffectParameters.defaults().eqTreble, range: -1...1, format: .db, tint: tint, onChange: onChange)

            case .tenBandEQ:
                CompactSlider(label: "31", value: bandBinding(0), defaultValue: NodeEffectParameters.defaults().tenBandGains[0], range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "62", value: bandBinding(1), defaultValue: NodeEffectParameters.defaults().tenBandGains[1], range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "125", value: bandBinding(2), defaultValue: NodeEffectParameters.defaults().tenBandGains[2], range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "250", value: bandBinding(3), defaultValue: NodeEffectParameters.defaults().tenBandGains[3], range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "500", value: bandBinding(4), defaultValue: NodeEffectParameters.defaults().tenBandGains[4], range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "1k", value: bandBinding(5), defaultValue: NodeEffectParameters.defaults().tenBandGains[5], range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "2k", value: bandBinding(6), defaultValue: NodeEffectParameters.defaults().tenBandGains[6], range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "4k", value: bandBinding(7), defaultValue: NodeEffectParameters.defaults().tenBandGains[7], range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "8k", value: bandBinding(8), defaultValue: NodeEffectParameters.defaults().tenBandGains[8], range: -12...12, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "16k", value: bandBinding(9), defaultValue: NodeEffectParameters.defaults().tenBandGains[9], range: -12...12, format: .dbValue, tint: tint, onChange: onChange)

            case .compressor:
                CompactSlider(label: "Threshold", value: $parameters.compressorThresholdDB, defaultValue: NodeEffectParameters.defaults().compressorThresholdDB, range: -60...0, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Ratio", value: $parameters.compressorRatio, defaultValue: NodeEffectParameters.defaults().compressorRatio, range: 1...20, format: .ratio, tint: tint, onChange: onChange)
                CompactSlider(label: "Attack", value: $parameters.compressorAttackMS, defaultValue: NodeEffectParameters.defaults().compressorAttackMS, range: 0.1...200, format: .msValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Release", value: $parameters.compressorReleaseMS, defaultValue: NodeEffectParameters.defaults().compressorReleaseMS, range: 5...2000, format: .msValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Makeup", value: $parameters.compressorMakeupDB, defaultValue: NodeEffectParameters.defaults().compressorMakeupDB, range: -24...24, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.compressorMix, defaultValue: NodeEffectParameters.defaults().compressorMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .reverb:
                CompactSlider(label: "Mix", value: $parameters.reverbMix, defaultValue: NodeEffectParameters.defaults().reverbMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Size", value: $parameters.reverbSize, defaultValue: NodeEffectParameters.defaults().reverbSize, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .stereoWidth:
                CompactSlider(label: "Width", value: $parameters.stereoWidthAmount, defaultValue: NodeEffectParameters.defaults().stereoWidthAmount, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .delay:
                CompactSlider(label: "Time", value: $parameters.delayTime, defaultValue: NodeEffectParameters.defaults().delayTime, range: 0.01...2.0, format: .ms, tint: tint, onChange: onChange)
                CompactSlider(label: "Feedback", value: $parameters.delayFeedback, defaultValue: NodeEffectParameters.defaults().delayFeedback, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.delayMix, defaultValue: NodeEffectParameters.defaults().delayMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .amp:
                CompactSlider(label: "Input", value: $parameters.ampInputGain, defaultValue: NodeEffectParameters.defaults().ampInputGain, range: -24...24, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Drive", value: $parameters.ampDrive, defaultValue: NodeEffectParameters.defaults().ampDrive, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Gain", value: $parameters.ampOutputGain, defaultValue: NodeEffectParameters.defaults().ampOutputGain, range: -24...24, format: .dbValue, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.ampMix, defaultValue: NodeEffectParameters.defaults().ampMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .distortion:
                CompactSlider(label: "Drive", value: $parameters.distortionDrive, defaultValue: NodeEffectParameters.defaults().distortionDrive, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.distortionMix, defaultValue: NodeEffectParameters.defaults().distortionMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .tremolo:
                CompactSlider(label: "Rate", value: $parameters.tremoloRate, defaultValue: NodeEffectParameters.defaults().tremoloRate, range: 0.1...20, format: .hz, tint: tint, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.tremoloDepth, defaultValue: NodeEffectParameters.defaults().tremoloDepth, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .autoPan:
                CompactSlider(label: "Rate", value: $parameters.autoPanRate, defaultValue: NodeEffectParameters.defaults().autoPanRate, range: 0.05...8, format: .hz, tint: tint, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.autoPanDepth, defaultValue: NodeEffectParameters.defaults().autoPanDepth, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .chorus:
                CompactSlider(label: "Rate", value: $parameters.chorusRate, defaultValue: NodeEffectParameters.defaults().chorusRate, range: 0.1...5, format: .hz, tint: tint, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.chorusDepth, defaultValue: NodeEffectParameters.defaults().chorusDepth, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.chorusMix, defaultValue: NodeEffectParameters.defaults().chorusMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .phaser:
                CompactSlider(label: "Rate", value: $parameters.phaserRate, defaultValue: NodeEffectParameters.defaults().phaserRate, range: 0.1...5, format: .hz, tint: tint, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.phaserDepth, defaultValue: NodeEffectParameters.defaults().phaserDepth, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .flanger:
                CompactSlider(label: "Rate", value: $parameters.flangerRate, defaultValue: NodeEffectParameters.defaults().flangerRate, range: 0.1...5, format: .hz, tint: tint, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.flangerDepth, defaultValue: NodeEffectParameters.defaults().flangerDepth, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Feedback", value: $parameters.flangerFeedback, defaultValue: NodeEffectParameters.defaults().flangerFeedback, range: 0...0.95, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.flangerMix, defaultValue: NodeEffectParameters.defaults().flangerMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .bitcrusher:
                CompactSlider(label: "Bit Depth", value: $parameters.bitcrusherBitDepth, defaultValue: NodeEffectParameters.defaults().bitcrusherBitDepth, range: BitcrusherParameterLimits.bitDepth, format: .integer, tint: tint, onChange: onChange)
                CompactSlider(label: "Downsample", value: $parameters.bitcrusherDownsample, defaultValue: NodeEffectParameters.defaults().bitcrusherDownsample, range: BitcrusherParameterLimits.downsample, format: .integer, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.bitcrusherMix, defaultValue: NodeEffectParameters.defaults().bitcrusherMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .tapeSaturation:
                CompactSlider(label: "Drive", value: $parameters.tapeSaturationDrive, defaultValue: NodeEffectParameters.defaults().tapeSaturationDrive, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.tapeSaturationMix, defaultValue: NodeEffectParameters.defaults().tapeSaturationMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .resampling:
                CompactSlider(label: "Rate", value: $parameters.resampleRate, defaultValue: NodeEffectParameters.defaults().resampleRate, range: 0.5...2.0, format: .ratio, tint: tint, onChange: onChange)
                CompactSlider(label: "Smooth", value: $parameters.resampleCrossfade, defaultValue: NodeEffectParameters.defaults().resampleCrossfade, range: 0.05...0.6, format: .percent, tint: tint, onChange: onChange)

            case .plugin:
                EmptyView()
            }
        }
    }

    private var knobColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 88), spacing: 10, alignment: .top),
            GridItem(.flexible(minimum: 88), spacing: 10, alignment: .top)
        ]
    }

    private var shouldScroll: Bool {
        naturalGridHeight > maxGridHeight
    }

    private var cappedGridHeight: CGFloat {
        min(naturalGridHeight, maxGridHeight)
    }

    private var naturalGridHeight: CGFloat {
        let rows = max(1, (parameterCount + 1) / 2)
        return CGFloat(rows) * 104 + CGFloat(max(0, rows - 1)) * 10
    }

    private var maxGridHeight: CGFloat {
        234
    }

    private var parameterCount: Int {
        switch effectType {
        case .enhancer, .bassBoost, .rubberBandPitch, .clarity, .deMud, .stereoWidth:
            return 1
        case .nightDrive, .chromePunch, .midnightGlow, .afterglow, .reverb, .tremolo, .autoPan, .phaser, .tapeSaturation, .resampling:
            return 2
        case .simpleEQ, .appleThreeBandEQ, .delay, .chorus, .bitcrusher:
            return 3
        case .amp, .distortion, .flanger:
            return 4
        case .compressor:
            return 6
        case .tenBandEQ:
            return 10
        case .pitchShift, .plugin:
            return 0
        }
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
    let defaultValue: Double
    let range: ClosedRange<Double>
    let format: ValueFormat
    let tint: Color
    let onChange: (() -> Void)?
    @State private var dragAdjustment: KnobDragAdjustment?
    @State private var isResetGesture = false
    @FocusState private var knobFocused: Bool
    @State private var draftValue: String
    @FocusState private var valueFieldFocused: Bool

    private let knobSize: CGFloat = 56

    init(
        label: String,
        value: Binding<Double>,
        defaultValue: Double,
        range: ClosedRange<Double>,
        format: ValueFormat,
        tint: Color,
        onChange: (() -> Void)? = nil
    ) {
        self.label = label
        self._value = value
        self.defaultValue = defaultValue
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
        VStack(spacing: 7) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: 15, alignment: .center)

            ZStack {
                Circle()
                    .fill(AppColors.controlPurpleRaised.opacity(0.88))
                    .overlay(
                        Circle()
                            .stroke(AppColors.controlStrokeSoft.opacity(0.82), lineWidth: 1)
                    )
                    .shadow(color: tint.opacity(0.2), radius: 7)

                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(index == 3 ? tint.opacity(0.46) : AppColors.textMuted.opacity(0.28))
                        .frame(width: 1.3, height: index == 3 ? 5.5 : 4)
                        .offset(y: -knobSize * 0.42)
                        .rotationEffect(.degrees(-120 + Double(index) * 40))
                }

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
            .overlay {
                Circle()
                    .stroke(knobFocused ? tint.opacity(0.75) : .clear, lineWidth: 1.5)
                    .padding(-4)
                    .allowsHitTesting(false)
            }
            .focusable()
            .focused($knobFocused)
            .focusEffectDisabled()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragAdjustment == nil {
                            if valueFieldFocused { commitTypedValue() }
                            knobFocused = true
                            dragAdjustment = KnobDragAdjustment(value: value)
                            isResetGesture = NSEvent.modifierFlags.contains(.option)
                            if isResetGesture { resetToDefault() }
                        }
                        guard !isResetGesture else { return }
                        let translation = Double(gesture.translation.width - gesture.translation.height)
                        guard var adjustment = dragAdjustment else { return }
                        let adjusted = adjustment.update(translation: translation, range: safeRange,
                            fine: NSEvent.modifierFlags.contains(.shift))
                        dragAdjustment = adjustment
                        setValue(adjusted)
                    }
                    .onEnded { _ in
                        dragAdjustment = nil
                        isResetGesture = false
                    }
            )
            .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow], phases: [.down, .repeat]) { press in
                guard press.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
                let direction = (press.key == .upArrow || press.key == .rightArrow) ? 1.0 : -1.0
                setValue(value + direction * format.adjustmentStep(fine: press.modifiers.contains(.shift)))
                return .handled
            }
            .contextMenu {
                Button("Reset to Default") { resetToDefault() }
            }
            .help("Drag to adjust \(label). Hold Shift for fine control. Option-click to reset. Arrow keys adjust when focused.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(format.displayText(for: value))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: setValue(value + format.adjustmentStep(fine: false))
                case .decrement: setValue(value - format.adjustmentStep(fine: false))
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Reset to Default") { resetToDefault() }

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
                    .frame(width: valueFieldWidth, height: 20)
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
                        .truncationMode(.tail)
                }
            }
            .frame(height: 20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .top)
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
        guard let adjusted = format.clampedValue(newValue, range: safeRange) else { return }
        draftValue = format.editText(for: adjusted)
        guard adjusted != value else { return }
        value = adjusted
        onChange?()
    }

    private func resetToDefault() {
        setValue(defaultValue)
    }

    private func commitTypedValue() {
        let trimmed = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(trimmed), parsed.isFinite,
              let mapped = format.value(fromDisplayed: parsed) else {
            draftValue = format.editText(for: value)
            return
        }
        setValue(mapped)
    }
}

extension CompactSlider.ValueFormat {
    func clampedValue(_ value: Double, range: ClosedRange<Double>) -> Double? {
        guard value.isFinite else { return nil }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return min(max(roundedValue(clamped), range.lowerBound), range.upperBound)
    }

    func adjustmentStep(fine: Bool) -> Double {
        let step: Double
        switch self {
        case .percent: step = 0.01
        case .db: step = 0.1 / 12
        case .dbValue, .hz: step = 0.1
        case .ms: step = 0.001
        case .msValue, .semitones: step = 1
        case .ratio: step = 0.01
        case .integer: return 1
        }
        return fine ? step / 10 : step
    }

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
            return String(format: "%.1f", value * 100)
        case .db:
            return String(format: "%+.2f", value * 12.0)
        case .dbValue:
            return String(format: "%+.2f", value)
        case .ms:
            return String(format: "%.1f", value * 1000)
        case .hz:
            return String(format: "%.2f", value)
        case .integer:
            return String(format: "%.0f", value)
        case .ratio:
            return String(format: "%.3f", value)
        case .semitones:
            return String(format: "%+.1f", value)
        case .msValue:
            return String(format: "%.1f", value)
        }
    }

    func displayText(for value: Double) -> String {
        if let unitText {
            return "\(editText(for: value)) \(unitText)"
        }
        return editText(for: value)
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

/// Accumulate unrounded deltas so fine drags still advance integer controls.
/// Modifier changes affect only subsequent motion, never the whole drag.
struct KnobDragAdjustment {
    var value: Double
    private var previousTranslation: Double = 0

    init(value: Double) { self.value = value }

    mutating func update(translation: Double, range: ClosedRange<Double>, fine: Bool) -> Double {
        let delta = translation - previousTranslation
        previousTranslation = translation
        let sensitivity = (range.upperBound - range.lowerBound) / (fine ? 1800 : 180)
        value = min(max(value + delta * sensitivity, range.lowerBound), range.upperBound)
        return value
    }
}
