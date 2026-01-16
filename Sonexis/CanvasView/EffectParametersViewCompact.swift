import SwiftUI

// MARK: - Compact Parameters View

struct EffectParametersViewCompact: View {
    let effectType: EffectType
    @Binding var parameters: NodeEffectParameters
    let tint: Color
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            switch effectType {
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

            case .tenBandEQ:
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 8) {
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
                }

            case .compressor:
                CompactSlider(label: "Strength", value: $parameters.compressorStrength, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .reverb:
                CompactSlider(label: "Mix", value: $parameters.reverbMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Size", value: $parameters.reverbSize, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .stereoWidth:
                CompactSlider(label: "Width", value: $parameters.stereoWidthAmount, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .delay:
                CompactSlider(label: "Time", value: $parameters.delayTime, range: 0.01...2.0, format: .ms, tint: tint, onChange: onChange)
                CompactSlider(label: "Feedback", value: $parameters.delayFeedback, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.delayMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .distortion:
                CompactSlider(label: "Drive", value: $parameters.distortionDrive, range: 0...1, format: .percent, tint: tint, onChange: onChange)
                CompactSlider(label: "Mix", value: $parameters.distortionMix, range: 0...1, format: .percent, tint: tint, onChange: onChange)

            case .tremolo:
                CompactSlider(label: "Rate", value: $parameters.tremoloRate, range: 0.1...20, format: .hz, tint: tint, onChange: onChange)
                CompactSlider(label: "Depth", value: $parameters.tremoloDepth, range: 0...1, format: .percent, tint: tint, onChange: onChange)

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
            }
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
    let range: ClosedRange<Double>
    let format: ValueFormat
    let tint: Color
    let onChange: (() -> Void)?

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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(tint.opacity(0.75))
                Spacer()
                Text(formattedValue)
                    .font(.caption)
                    .foregroundColor(tint)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range)
                .tint(tint)
                .controlSize(.small)
                .onChange(of: value) { _ in
                    onChange?()
                }
        }
    }

    private var formattedValue: String {
        switch format {
        case .percent:
            return "\(Int(value * 100))%"
        case .db:
            let db = value * 12.0
            return String(format: "%+.1f dB", db)
        case .dbValue:
            return String(format: "%+.1f dB", value)
        case .ms:
            return String(format: "%.0f ms", value * 1000)
        case .hz:
            return String(format: "%.1f Hz", value)
        case .integer:
            return String(format: "%.0f", value)
        case .ratio:
            return String(format: "%.2fx", value)
        case .semitones:
            return String(format: "%+.1f st", value)
        }
    }
}

