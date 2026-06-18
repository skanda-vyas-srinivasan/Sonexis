import CoreAudio
import Foundation

final class RealtimeRingBuffer {
    private var pointer: OpaquePointer?

    let capacityFrames: UInt32
    let channels: UInt32

    init(capacityFrames: UInt32, channels: UInt32) throws {
        guard let pointer = SonexisAudioRingBufferCreate(capacityFrames, channels) else {
            throw PrototypeError(message: "Could not allocate realtime audio ring buffer")
        }

        self.pointer = pointer
        self.capacityFrames = capacityFrames
        self.channels = channels
    }

    deinit {
        destroy()
    }

    func write(inputData: UnsafePointer<AudioBufferList>) -> UInt32 {
        guard let pointer else { return 0 }
        return SonexisAudioRingBufferWriteFromAudioBufferList(pointer, inputData)
    }

    func read(outputData: UnsafeMutablePointer<AudioBufferList>) -> UInt32 {
        guard let pointer else { return 0 }
        return SonexisAudioRingBufferReadToAudioBufferList(pointer, outputData)
    }

    func setGainImmediate(_ gain: Float) {
        guard let pointer else { return }
        SonexisAudioRingBufferSetGainImmediate(pointer, gain)
    }

    func requestGainRamp(targetGain: Float, rampFrames: UInt32) {
        guard let pointer else { return }
        SonexisAudioRingBufferRequestGainRamp(pointer, targetGain, rampFrames)
    }

    func setReadEnabled(_ enabled: Bool) {
        guard let pointer else { return }
        SonexisAudioRingBufferSetReadEnabled(pointer, enabled)
    }

    func configurePitchShift(enabled: Bool, semitones: Float) {
        guard let pointer else { return }
        SonexisAudioRingBufferConfigurePitchShift(
            pointer,
            enabled,
            semitones
        )
    }

    var fillFrames: UInt32 {
        guard let pointer else { return 0 }
        return SonexisAudioRingBufferGetFillFrames(pointer)
    }

    var droppedFrames: UInt64 {
        guard let pointer else { return 0 }
        return SonexisAudioRingBufferGetDroppedFrames(pointer)
    }

    var underflowFrames: UInt64 {
        guard let pointer else { return 0 }
        return SonexisAudioRingBufferGetUnderflowFrames(pointer)
    }

    var writtenFrames: UInt64 {
        guard let pointer else { return 0 }
        return SonexisAudioRingBufferGetWrittenFrames(pointer)
    }

    var readFrames: UInt64 {
        guard let pointer else { return 0 }
        return SonexisAudioRingBufferGetReadFrames(pointer)
    }

    var lastInputPeakPPM: UInt32 {
        guard let pointer else { return 0 }
        return SonexisAudioRingBufferGetLastInputPeakPPM(pointer)
    }

    var currentGainPPM: UInt32 {
        guard let pointer else { return 0 }
        return SonexisAudioRingBufferGetCurrentGainPPM(pointer)
    }

    func destroy() {
        guard let pointer else { return }
        SonexisAudioRingBufferDestroy(pointer)
        self.pointer = nil
    }
}
