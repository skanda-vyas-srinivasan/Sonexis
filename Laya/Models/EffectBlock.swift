import Foundation

// MARK: - Effect Block

struct EffectBlock: Identifiable, Codable {
    let id: UUID
    let type: EffectType
    var parameters: [String: Float]
    var isEnabled: Bool
    var order: Int

    init(type: EffectType, order: Int = 0) {
        self.id = UUID()
        self.type = type
        self.parameters = Self.defaultParameters(for: type)
        self.isEnabled = true
        self.order = order
    }

    static func defaultParameters(for type: EffectType) -> [String: Float] {
        switch type {
        case .bassBoost:
            return ["gain": 6.0] // +6dB default
        case .clarity:
            return ["amount": 50.0, "brightness": 50.0] // 0-100 scale
        case .reverb:
            return ["mix": 30.0, "size": 50.0] // 0-100 scale
        case .compressor:
            return ["strength": 40.0] // 0-100 scale
        case .stereoWidth:
            return ["width": 30.0] // 0-100 scale
        case .pitchShift:
            return ["pitch": 0.0, "preserveTiming": 1.0] // -12 to +12 semitones
        case .rubberBandPitch:
            return ["semitones": 0.0]
        case .simpleEQ:
            return ["bass": 0.0, "mids": 0.0, "treble": 0.0] // -12 to +12 dB
        case .tenBandEQ:
            return [
                "31": 0.0, "62": 0.0, "125": 0.0, "250": 0.0, "500": 0.0,
                "1k": 0.0, "2k": 0.0, "4k": 0.0, "8k": 0.0, "16k": 0.0
            ]
        case .deMud:
            return ["strength": 50.0] // 0-100 scale
        case .delay:
            return ["time": 250.0, "feedback": 40.0, "mix": 30.0] // time in ms, feedback/mix 0-100
        case .distortion:
            return ["drive": 50.0, "mix": 50.0] // 0-100 scale
        case .tremolo:
            return ["rate": 5.0, "depth": 50.0] // rate in Hz, depth 0-100
        case .chorus:
            return ["rate": 0.8, "depth": 40.0, "mix": 35.0]
        case .phaser:
            return ["rate": 0.6, "depth": 50.0]
        case .flanger:
            return ["rate": 0.6, "depth": 40.0, "feedback": 25.0, "mix": 40.0]
        case .bitcrusher:
            return ["bitDepth": 8.0, "downsample": 4.0, "mix": 60.0]
        case .tapeSaturation:
            return ["drive": 35.0, "mix": 50.0]
        case .resampling:
            return ["rate": 1.0]
        }
    }
}

