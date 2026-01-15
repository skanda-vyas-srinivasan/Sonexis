import Foundation

// MARK: - Effect Type

enum EffectType: String, Codable, CaseIterable {
    case bassBoost = "Bass Boost"
    case clarity = "Clarity"
    case reverb = "Reverb"
    case compressor = "Soft Compression"
    case stereoWidth = "Stereo Widening"
    case pitchShift = "Pitch Effect"
    case rubberBandPitch = "Pitch (Rubber Band)"
    case simpleEQ = "Simple EQ"
    case tenBandEQ = "10-Band EQ"
    case deMud = "De-Mud"
    case delay = "Delay"
    case distortion = "Distortion"
    case tremolo = "Tremolo"
    case chorus = "Chorus"
    case phaser = "Phaser"
    case flanger = "Flanger"
    case bitcrusher = "Bitcrusher"
    case tapeSaturation = "Tape Saturation"
    case resampling = "Resampling"

    var description: String {
        switch self {
        case .bassBoost:
            return "Makes low frequencies more powerful"
        case .clarity:
            return "Makes voices and instruments clearer"
        case .reverb:
            return "Adds space and depth"
        case .compressor:
            return "Evens out quiet and loud parts"
        case .stereoWidth:
            return "Makes sound feel wider and more spacious"
        case .pitchShift:
            return "Changes the pitch up or down"
        case .rubberBandPitch:
            return "High-quality pitch shift"
        case .simpleEQ:
            return "Adjust bass, middle, and treble"
        case .tenBandEQ:
            return "Fine-tune 10 frequency bands"
        case .deMud:
            return "Removes muddiness and boxiness"
        case .delay:
            return "Repeating echoes and rhythmic delays"
        case .distortion:
            return "Adds warmth, grit, and harmonic saturation"
        case .tremolo:
            return "Pulsing volume modulation"
        case .chorus:
            return "Thickens sound with lush modulation"
        case .phaser:
            return "Swirling, sweeping movement"
        case .flanger:
            return "Jet-like sweeping comb filter"
        case .bitcrusher:
            return "Retro digital grit and crunch"
        case .tapeSaturation:
            return "Warm, smooth analog saturation"
        case .resampling:
            return "Pitch and speed shift by resampling"
        }
    }

    var icon: String {
        switch self {
        case .bassBoost:
            return "speaker.wave.3"
        case .clarity:
            return "sparkles"
        case .reverb:
            return "building.columns"
        case .compressor:
            return "waveform.path.ecg"
        case .stereoWidth:
            return "arrow.left.and.right"
        case .pitchShift:
            return "hare"
        case .rubberBandPitch:
            return "music.note.list"
        case .simpleEQ:
            return "slider.horizontal.3"
        case .tenBandEQ:
            return "slider.horizontal.2.square"
        case .deMud:
            return "bandage"
        case .delay:
            return "arrow.3.trianglepath"
        case .distortion:
            return "waveform.path.badge.plus"
        case .tremolo:
            return "waveform"
        case .chorus:
            return "waveform.circle"
        case .phaser:
            return "circle.dotted.and.circle"
        case .flanger:
            return "waveform.path"
        case .bitcrusher:
            return "square.grid.3x3"
        case .tapeSaturation:
            return "record.circle"
        case .resampling:
            return "arrow.triangle.2.circlepath"
        }
    }
}

