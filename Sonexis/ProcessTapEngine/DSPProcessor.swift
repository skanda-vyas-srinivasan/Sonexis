import Foundation

final class DSPProcessor {
    let configuration: DSPConfiguration
    let unityGain: Float = 1.0

    init(configuration: DSPConfiguration) {
        self.configuration = configuration
    }

    var processingGain: Float {
        configuration.processingGain
    }

    var pitchShiftEnabled: Bool {
        configuration.pitchShift.enabled
    }

    var pitchShiftSemitones: Float {
        configuration.pitchShift.semitones
    }

    var startupRampDuration: TimeInterval {
        configuration.startupRampDuration
    }

    var shutdownRampDuration: TimeInterval {
        configuration.shutdownRampDuration
    }

    var routeChangeRampDuration: TimeInterval {
        configuration.routeChangeRampDuration
    }

    var processingDescription: String {
        if pitchShiftEnabled {
            return "debug pitch-up DSP"
        }

        return "unity passthrough DSP"
    }

    func configureInitialGain(on ringBuffer: RealtimeRingBuffer) {
        ringBuffer.setGainImmediate(unityGain)
    }

    func configurePitchShift(on ringBuffer: RealtimeRingBuffer) {
        ringBuffer.configurePitchShift(
            enabled: pitchShiftEnabled,
            semitones: pitchShiftSemitones
        )
    }

    func requestProcessingGainRamp(
        on ringBuffer: RealtimeRingBuffer,
        sampleRate: Double
    ) {
        ringBuffer.requestGainRamp(
            targetGain: processingGain,
            rampFrames: rampFrameCount(sampleRate: sampleRate, duration: startupRampDuration)
        )
    }

    func requestUnityGainRamp(
        on ringBuffer: RealtimeRingBuffer,
        sampleRate: Double,
        duration: TimeInterval
    ) {
        ringBuffer.requestGainRamp(
            targetGain: unityGain,
            rampFrames: rampFrameCount(sampleRate: sampleRate, duration: duration)
        )
    }

    private func rampFrameCount(sampleRate: Double, duration: TimeInterval) -> UInt32 {
        max(UInt32((sampleRate * duration).rounded(.up)), 1)
    }
}
