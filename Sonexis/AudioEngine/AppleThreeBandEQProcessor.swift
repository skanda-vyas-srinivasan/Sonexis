import AVFoundation
import AudioUnit
import Foundation

final class AppleThreeBandEQProcessor {
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private var renderBlock: AURenderBlock?
    private var currentSampleRate: Double = 0
    private var currentChannelCount: Int = 0
    private var inputScratch: [[Float]] = []
    private var monoBufferList: UnsafeMutableAudioBufferListPointer?
    private var stereoBufferList: UnsafeMutableAudioBufferListPointer?
    private var sampleTime: Double = 0
    private var loggedRenderFailure = false

    init() {
        configureBands(bassGainDB: 0, midGainDB: 0, trebleGainDB: 0)
        renderBlock = eq.auAudioUnit.renderBlock
    }

    deinit {
        if eq.auAudioUnit.renderResourcesAllocated {
            eq.auAudioUnit.deallocateRenderResources()
        }
        monoBufferList?.unsafeMutablePointer.deallocate()
        stereoBufferList?.unsafeMutablePointer.deallocate()
    }

    func reset() {
        eq.auAudioUnit.reset()
        sampleTime = 0
    }

    func process(
        buffer: inout [[Float]],
        frameLength: Int,
        sampleRate: Double,
        channelCount: Int,
        bassGainDB: Double,
        midGainDB: Double,
        trebleGainDB: Double
    ) -> Bool {
        guard frameLength > 0, channelCount > 0, channelCount <= 2 else { return false }
        configureIfNeeded(sampleRate: sampleRate, channelCount: channelCount)
        guard currentSampleRate == sampleRate,
              currentChannelCount == channelCount,
              let renderBlock else {
            return false
        }

        configureBands(
            bassGainDB: bassGainDB,
            midGainDB: midGainDB,
            trebleGainDB: trebleGainDB
        )
        ensureInputScratch(frameLength: frameLength, channelCount: channelCount)
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                inputScratch[channel][frame] = buffer[channel][frame]
            }
        }

        var actionFlags = AudioUnitRenderActionFlags()
        var timeStamp = AudioTimeStamp()
        timeStamp.mFlags = .sampleTimeValid
        timeStamp.mSampleTime = sampleTime
        sampleTime += Double(frameLength)

        let pullInput: AURenderPullInputBlock = { [weak self] _, _, _, _, ioData in
            guard let self else { return noErr }
            self.copyInputTo(ioData, frameLength: frameLength, channelCount: channelCount)
            return noErr
        }

        let status: OSStatus
        if channelCount == 1 {
            var output0 = buffer[0]
            status = output0.withUnsafeMutableBufferPointer { outPtr in
                guard let base = outPtr.baseAddress else { return noErr }
                let bufferList = getMonoBufferList()
                bufferList[0] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frameLength * MemoryLayout<Float>.size),
                    mData: base
                )
                return renderBlock(&actionFlags, &timeStamp, AUAudioFrameCount(frameLength), 0, bufferList.unsafeMutablePointer, pullInput)
            }
            buffer[0] = output0
        } else {
            var output0 = buffer[0]
            var output1 = buffer[1]
            status = output0.withUnsafeMutableBufferPointer { outPtr0 in
                guard let base0 = outPtr0.baseAddress else { return noErr }
                return output1.withUnsafeMutableBufferPointer { outPtr1 in
                    guard let base1 = outPtr1.baseAddress else { return noErr }
                    let bufferList = getStereoBufferList()
                    bufferList[0] = AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: UInt32(frameLength * MemoryLayout<Float>.size),
                        mData: base0
                    )
                    bufferList[1] = AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: UInt32(frameLength * MemoryLayout<Float>.size),
                        mData: base1
                    )
                    return renderBlock(&actionFlags, &timeStamp, AUAudioFrameCount(frameLength), 0, bufferList.unsafeMutablePointer, pullInput)
                }
            }
            buffer[0] = output0
            buffer[1] = output1
        }

        guard status == noErr else {
            if !loggedRenderFailure {
                loggedRenderFailure = true
                print("Apple 3-Band EQ render failed status=\(status)")
            }
            return false
        }
        loggedRenderFailure = false
        return true
    }

    private func configureBands(bassGainDB: Double, midGainDB: Double, trebleGainDB: Double) {
        let bands = eq.bands
        guard bands.count >= 3 else { return }

        bands[0].filterType = .lowShelf
        bands[0].frequency = 80
        bands[0].bandwidth = 0.7
        bands[0].gain = Float(min(max(bassGainDB, -12), 12))
        bands[0].bypass = false

        bands[1].filterType = .parametric
        bands[1].frequency = 1000
        bands[1].bandwidth = 1.0
        bands[1].gain = Float(min(max(midGainDB, -12), 12))
        bands[1].bypass = false

        bands[2].filterType = .highShelf
        bands[2].frequency = 8000
        bands[2].bandwidth = 0.7
        bands[2].gain = Float(min(max(trebleGainDB, -12), 12))
        bands[2].bypass = false
    }

    private func configureIfNeeded(sampleRate: Double, channelCount: Int) {
        guard currentSampleRate != sampleRate || currentChannelCount != channelCount else { return }
        let audioUnit = eq.auAudioUnit
        do {
            if audioUnit.renderResourcesAllocated {
                audioUnit.deallocateRenderResources()
            }
            audioUnit.maximumFramesToRender = 8192
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
            ) else { return }
            if audioUnit.inputBusses.count > 0 {
                try audioUnit.inputBusses[0].setFormat(format)
                audioUnit.inputBusses[0].isEnabled = true
            }
            if audioUnit.outputBusses.count > 0 {
                try audioUnit.outputBusses[0].setFormat(format)
                audioUnit.outputBusses[0].isEnabled = true
            }
            audioUnit.shouldBypassEffect = false
            try audioUnit.allocateRenderResources()
            audioUnit.reset()
            currentSampleRate = sampleRate
            currentChannelCount = channelCount
            sampleTime = 0
            renderBlock = audioUnit.renderBlock
        } catch {
            currentSampleRate = 0
            currentChannelCount = 0
            print("Apple 3-Band EQ configure failed: \(error.localizedDescription)")
        }
    }

    private func getMonoBufferList() -> UnsafeMutableAudioBufferListPointer {
        if let monoBufferList {
            return monoBufferList
        }
        let created = AudioBufferList.allocate(maximumBuffers: 1)
        monoBufferList = created
        return created
    }

    private func getStereoBufferList() -> UnsafeMutableAudioBufferListPointer {
        if let stereoBufferList {
            return stereoBufferList
        }
        let created = AudioBufferList.allocate(maximumBuffers: 2)
        stereoBufferList = created
        return created
    }

    private func ensureInputScratch(frameLength: Int, channelCount: Int) {
        if inputScratch.count != channelCount {
            inputScratch = [[Float]](repeating: [Float](repeating: 0, count: frameLength), count: channelCount)
            return
        }
        let currentLength = inputScratch.first?.count ?? 0
        guard currentLength < frameLength else { return }
        let extra = frameLength - currentLength
        for index in 0..<channelCount {
            inputScratch[index].append(contentsOf: repeatElement(0, count: extra))
        }
    }

    private func copyInputTo(_ ioData: UnsafeMutablePointer<AudioBufferList>, frameLength: Int, channelCount: Int) {
        let bufferList = UnsafeMutableAudioBufferListPointer(ioData)
        for channel in 0..<min(channelCount, bufferList.count) {
            guard let dst = bufferList[channel].mData else { continue }
            let dstPtr = dst.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameLength {
                dstPtr[frame] = inputScratch[channel][frame]
            }
        }
    }
}
