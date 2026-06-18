import Foundation

struct PitchShiftConfiguration {
    var enabled: Bool
    var semitones: Float

    static let disabled = PitchShiftConfiguration(enabled: false, semitones: 0.0)
    static let debugPitchUp = PitchShiftConfiguration(enabled: true, semitones: 7.0)
}

struct DSPConfiguration {
    var processingGain: Float
    var pitchShift: PitchShiftConfiguration
    var startupRampDuration: TimeInterval
    var shutdownRampDuration: TimeInterval
    var routeChangeRampDuration: TimeInterval

    static let productBaseline = DSPConfiguration(
        processingGain: 1.0,
        pitchShift: .disabled,
        startupRampDuration: 0.40,
        shutdownRampDuration: 0.25,
        routeChangeRampDuration: 0.15
    )

    static let debugPitchUp = DSPConfiguration(
        processingGain: 1.0,
        pitchShift: .debugPitchUp,
        startupRampDuration: 0.40,
        shutdownRampDuration: 0.25,
        routeChangeRampDuration: 0.15
    )
}
