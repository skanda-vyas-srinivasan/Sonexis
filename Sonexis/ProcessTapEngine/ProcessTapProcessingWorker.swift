import Foundation

protocol ProcessTapAudioProcessor: AnyObject {
    func processTapFormatDidChange(
        maxFrameCount: Int,
        channelCount: Int,
        sampleRate: Double
    )

    func processSystemAudio(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Double
    )

    func processTapAudioGapDetected(
        fillFrames: UInt32,
        droppedFrames: UInt64,
        underflowFrames: UInt64
    )
}

final class ProcessTapProcessingWorker {
    private let inputRingBuffer: RealtimeRingBuffer
    private let outputRingBuffer: RealtimeRingBuffer
    private weak var processor: ProcessTapAudioProcessor?
    private let sampleRate: Double
    private let channels: UInt32
    private let maxFramesPerChunk: UInt32
    private let maxChunksPerWake: Int
    private let queue = DispatchQueue(label: "Sonexis.ProcessTapProcessingWorker", qos: .userInteractive)
    private let queueSpecificKey = DispatchSpecificKey<Bool>()

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
        maxFramesPerChunk: UInt32 = 1_024,
        maxChunksPerWake: Int = 32
    ) {
        self.inputRingBuffer = inputRingBuffer
        self.outputRingBuffer = outputRingBuffer
        self.processor = processor
        self.sampleRate = sampleRate
        self.channels = channels
        self.maxFramesPerChunk = maxFramesPerChunk
        self.maxChunksPerWake = max(1, maxChunksPerWake)
        self.inputScratch = [Float](repeating: 0, count: Int(maxFramesPerChunk * channels))
        self.outputScratch = [Float](repeating: 0, count: Int(maxFramesPerChunk * channels))
        queue.setSpecific(key: queueSpecificKey, value: true)
        processor?.processTapFormatDidChange(
            maxFrameCount: Int(maxFramesPerChunk),
            channelCount: Int(channels),
            sampleRate: sampleRate
        )
    }

    func start() {
        if DispatchQueue.getSpecific(key: queueSpecificKey) == true {
            startOnWorkerQueue()
        } else {
            queue.sync {
                startOnWorkerQueue()
            }
        }
    }

    func stop(log: Bool) {
        let stoppedTimer: Bool
        if DispatchQueue.getSpecific(key: queueSpecificKey) == true {
            stoppedTimer = stopOnWorkerQueue()
        } else {
            stoppedTimer = queue.sync {
                stopOnWorkerQueue()
            }
        }

        if stoppedTimer {
            if log { print("Cleanup: stopped Process Tap DSP processing worker.") }
        } else if log {
            print("Cleanup: no Process Tap DSP processing worker to stop.")
        }
    }

    private func startOnWorkerQueue() {
        guard timer == nil else { return }
        isRunning = true

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .microseconds(250))
        timer.setEventHandler { [weak self] in
            self?.processAvailableInput()
        }
        self.timer = timer
        timer.resume()
    }

    private func stopOnWorkerQueue() -> Bool {
        isRunning = false
        guard let timer else {
            return false
        }
        timer.setEventHandler {}
        timer.cancel()
        self.timer = nil
        return true
    }

    private func processAvailableInput() {
        guard isRunning else { return }

        var chunksProcessed = 0
        while chunksProcessed < maxChunksPerWake {
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
