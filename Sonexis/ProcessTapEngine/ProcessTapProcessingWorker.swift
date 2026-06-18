import Foundation

protocol ProcessTapAudioProcessor: AnyObject {
    func processSystemAudio(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Double
    )
}

final class ProcessTapProcessingWorker {
    private let inputRingBuffer: RealtimeRingBuffer
    private let outputRingBuffer: RealtimeRingBuffer
    private weak var processor: ProcessTapAudioProcessor?
    private let sampleRate: Double
    private let channels: UInt32
    private let maxFramesPerChunk: UInt32
    private let queue = DispatchQueue(label: "Sonexis.ProcessTapProcessingWorker", qos: .userInitiated)

    private var timer: DispatchSourceTimer?
    private var inputScratch: [Float]
    private var outputScratch: [Float]
    private var isRunning = false

    init(
        inputRingBuffer: RealtimeRingBuffer,
        outputRingBuffer: RealtimeRingBuffer,
        processor: ProcessTapAudioProcessor?,
        sampleRate: Double,
        channels: UInt32,
        maxFramesPerChunk: UInt32 = 512
    ) {
        self.inputRingBuffer = inputRingBuffer
        self.outputRingBuffer = outputRingBuffer
        self.processor = processor
        self.sampleRate = sampleRate
        self.channels = channels
        self.maxFramesPerChunk = maxFramesPerChunk
        self.inputScratch = [Float](repeating: 0, count: Int(maxFramesPerChunk * channels))
        self.outputScratch = [Float](repeating: 0, count: Int(maxFramesPerChunk * channels))
    }

    func start() {
        guard timer == nil else { return }
        isRunning = true

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.processAvailableInput()
        }
        self.timer = timer
        timer.resume()
    }

    func stop(log: Bool) {
        isRunning = false
        if timer != nil {
            timer?.cancel()
            timer = nil
            if log { print("Cleanup: stopped Process Tap DSP processing worker.") }
        } else if log {
            print("Cleanup: no Process Tap DSP processing worker to stop.")
        }
    }

    private func processAvailableInput() {
        guard isRunning else { return }

        var chunksProcessed = 0
        while chunksProcessed < 8 {
            let availableFrames = inputRingBuffer.fillFrames
            if availableFrames == 0 {
                break
            }

            let framesToProcess = min(availableFrames, maxFramesPerChunk)

            let framesRead = inputScratch.withUnsafeMutableBufferPointer { inputBuffer in
                guard let inputBase = inputBuffer.baseAddress else { return UInt32(0) }
                return inputRingBuffer.readInterleaved(inputBase, frames: framesToProcess)
            }

            if framesRead == 0 {
                break
            }

            let actualSamples = Int(framesRead * channels)
            inputScratch.withUnsafeBufferPointer { inputBuffer in
                outputScratch.withUnsafeMutableBufferPointer { outputBuffer in
                    guard let inputBase = inputBuffer.baseAddress,
                          let outputBase = outputBuffer.baseAddress else {
                        return
                    }

                    if let processor {
                        processor.processSystemAudio(
                            input: inputBase,
                            output: outputBase,
                            frameCount: Int(framesRead),
                            channelCount: Int(channels),
                            sampleRate: sampleRate
                        )
                    } else {
                        outputBase.update(from: inputBase, count: actualSamples)
                    }
                }
            }

            outputScratch.withUnsafeBufferPointer { outputBuffer in
                guard let outputBase = outputBuffer.baseAddress else { return }
                _ = outputRingBuffer.writeInterleaved(outputBase, frames: framesRead)
            }

            chunksProcessed += 1
        }
    }
}
