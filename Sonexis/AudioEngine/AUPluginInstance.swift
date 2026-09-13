import AppKit
import AVFoundation
import AVFAudio
import AudioToolbox
import AudioToolbox.AUCocoaUIView
import AudioUnit
import CoreAudioKit
import AudioToolbox
import Foundation

final class AUPluginInstance: PluginInstance {
    let reference: PluginReference
    private(set) var isReady: Bool = false
    var onReady: (() -> Void)?
    private var audioUnit: AUAudioUnit?
    private var renderBlock: AURenderBlock?
    private var currentSampleRate: Double = 0
    private var currentChannelCount: Int = 0
    private var renderChannelCount: Int = 0
    private var pendingConfigure = false
    private var pendingSampleRate: Double = 0
    private var pendingChannelCount: Int = 0
    private var inputScratch: [[Float]] = []
    private var cachedParameters: [PluginParameter] = []
    private var parameterMap: [String: AUParameter] = [:]
    private var sampleTime: Double = 0
    private var loggedRenderFailure = false
    private var debugRenderCounter = 0
    private var debugInputPulled = false
    private let debugParamLogs = false
    private let debugRenderLogs = false
    private var monoBufferList: UnsafeMutableAudioBufferListPointer?
    private var stereoBufferList: UnsafeMutableAudioBufferListPointer?
    private var didWarmUp = false
    private var cachedEditorController: NSViewController?
    private let debugEditorLogs = false

    deinit {
        monoBufferList?.unsafeMutablePointer.deallocate()
        stereoBufferList?.unsafeMutablePointer.deallocate()
    }

    init(reference: PluginReference) {
        self.reference = reference
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.instantiateAudioUnit()
        }
    }

    var displayName: String { reference.displayName }
    var vendorName: String { reference.vendor }

    func ensureFormat(sampleRate: Double, channelCount: Int) {
        guard isReady else { return }
        if currentSampleRate != sampleRate || currentChannelCount != channelCount {
            requestConfigure(sampleRate: sampleRate, channelCount: channelCount)
        }
    }

    func process(buffer: inout [[Float]], frameLength: Int, sampleRate: Double, channelCount: Int) {
        guard isReady, let renderBlock, channelCount <= 2 else { return }
        ensureFormat(sampleRate: sampleRate, channelCount: channelCount)
        guard !pendingConfigure, currentChannelCount == channelCount else { return }

        var actionFlags = AudioUnitRenderActionFlags()
        var timeStamp = AudioTimeStamp()
        timeStamp.mFlags = .sampleTimeValid
        timeStamp.mSampleTime = sampleTime
        sampleTime += Double(frameLength)

        debugInputPulled = false

        let status: OSStatus
        let targetChannels = renderChannelCount > 0 ? renderChannelCount : channelCount
        ensureInputScratch(frameLength: frameLength, channelCount: targetChannels)
        if targetChannels == 1 {
            if channelCount == 2 {
                for frame in 0..<frameLength {
                    inputScratch[0][frame] = 0.5 * (buffer[0][frame] + buffer[1][frame])
                }
            } else {
                for frame in 0..<frameLength {
                    inputScratch[0][frame] = buffer[0][frame]
                }
            }
        } else {
            for channel in 0..<targetChannels {
                for frame in 0..<frameLength {
                    inputScratch[channel][frame] = buffer[channel][frame]
                }
            }
        }

        let pullInput: AURenderPullInputBlock = { [weak self] _, _, _, _, ioData in
            guard let self else { return noErr }
            self.copyInterleavedInputTo(ioData, frameLength: frameLength, channelCount: targetChannels)
            self.debugInputPulled = true
            return noErr
        }

        if targetChannels == 1 {
            status = buffer[0].withUnsafeMutableBufferPointer { outPtr in
                guard let baseAddress = outPtr.baseAddress else { return noErr }
                for frame in 0..<frameLength {
                    baseAddress[frame] = inputScratch[0][frame]
                }
                let bufferList = getMonoBufferList()
                bufferList[0] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frameLength * MemoryLayout<Float>.size),
                    mData: baseAddress
                )
                return renderBlock(&actionFlags, &timeStamp, AUAudioFrameCount(frameLength), 0, bufferList.unsafeMutablePointer, pullInput)
            }
            if channelCount == 2 {
                for frame in 0..<frameLength {
                    buffer[1][frame] = buffer[0][frame]
                }
            }
        } else {
            status = buffer.withUnsafeMutableBufferPointer { channelBuffers in
                channelBuffers[0].withUnsafeMutableBufferPointer { outPtr0 in
                    guard let base0 = outPtr0.baseAddress else { return noErr }
                    return channelBuffers[1].withUnsafeMutableBufferPointer { outPtr1 in
                        guard let base1 = outPtr1.baseAddress else { return noErr }
                        for frame in 0..<frameLength {
                            base0[frame] = inputScratch[0][frame]
                            base1[frame] = inputScratch[1][frame]
                        }
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
            }
        }

        if status != noErr {
            // On failure, keep dry buffer.
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    buffer[channel][frame] = inputScratch[channel][frame]
                }
            }
            if !loggedRenderFailure {
                loggedRenderFailure = true
                print("AU Render failed for \(reference.name) status=\(status)")
            }
        } else if loggedRenderFailure {
            loggedRenderFailure = false
        }

        debugRenderCounter += 1
        if debugRenderLogs, debugRenderCounter % 120 == 0 {
            let inputRMS = computeRMS(inputScratch, frameLength: frameLength, channelCount: targetChannels)
            let outputRMS = computeRMS(buffer, frameLength: frameLength, channelCount: channelCount)
            let diffRMS = computeDiffRMS(
                input: inputScratch,
                output: buffer,
                frameLength: frameLength,
                channelCount: min(channelCount, targetChannels)
            )
            print("AU Render ok \(reference.name) frames=\(frameLength) inCh=\(channelCount) auCh=\(targetChannels) pulled=\(debugInputPulled) inRMS=\(inputRMS) outRMS=\(outputRMS) diffRMS=\(diffRMS)")
        }
    }

    private func computeRMS(_ audio: [[Float]], frameLength: Int, channelCount: Int) -> Float {
        guard frameLength > 0, channelCount > 0 else { return 0 }
        var sum: Float = 0
        for channel in 0..<min(channelCount, audio.count) {
            var channelSum: Float = 0
            let data = audio[channel]
            for frame in 0..<min(frameLength, data.count) {
                let sample = data[frame]
                channelSum += sample * sample
            }
            sum += channelSum / Float(frameLength)
        }
        return sqrt(sum / Float(channelCount))
    }

    private func computeDiffRMS(
        input: [[Float]],
        output: [[Float]],
        frameLength: Int,
        channelCount: Int
    ) -> Float {
        guard frameLength > 0, channelCount > 0 else { return 0 }
        var sum: Float = 0
        for channel in 0..<min(channelCount, min(input.count, output.count)) {
            var channelSum: Float = 0
            let inputData = input[channel]
            let outputData = output[channel]
            for frame in 0..<min(frameLength, min(inputData.count, outputData.count)) {
                let diff = outputData[frame] - inputData[frame]
                channelSum += diff * diff
            }
            sum += channelSum / Float(frameLength)
        }
        return sqrt(sum / Float(channelCount))
    }

    func editorView() -> NSView? {
        return nil
    }

    func requestEditor(completion: @escaping (NSView?, NSViewController?) -> Void) {
        guard isReady, let audioUnit else {
            completion(nil, nil)
            return
        }
        if let cachedEditorController {
            let cachedView = cachedEditorController.view
            DispatchQueue.main.async {
                if cachedView.superview != nil {
                    cachedView.removeFromSuperview()
                }
                if self.debugEditorLogs {
                    print("AU UI reuse cached controller for \(self.reference.name)")
                }
                completion(cachedView, cachedEditorController)
            }
            return
        }
        // NOTE: Some Apple AUs (e.g., AUNewPitch) report providesUserInterface=false but still return a UI.
        // If this causes issues, revert to the strict providesUserInterface guard below.
        // guard audioUnit.providesUserInterface else {
        //     print("AU UI unavailable for \(reference.name): providesUserInterface=false")
        //     completion(nil)
        //     return
        // }
        let isAppleAU = reference.componentManufacturer == 1634758764
        let timeout: TimeInterval = isAppleAU ? 0.8 : 3.0
        var didComplete = false
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if !didComplete {
                didComplete = true
                print("AU UI timed out for \(self.reference.name) after \(timeout)s")
                completion(nil, nil)
            }
        }
        audioUnit.requestViewController(completionHandler: { controller in
            DispatchQueue.main.async {
                guard !didComplete else { return }
                didComplete = true
                if controller == nil {
                    print("AU UI request returned nil for \(self.reference.name)")
                }
                if let controller {
                    self.cachedEditorController = controller
                    let view = controller.view
                    if view.subviews.isEmpty {
                        if self.debugEditorLogs {
                            print("AU UI empty view for \(self.reference.name), trying Cocoa UI")
                        }
                        if let cocoaView = self.makeCocoaView() {
                            completion(cocoaView, nil)
                            return
                        }
                        if let genericController = self.makeGenericController() {
                            self.cachedEditorController = genericController
                            completion(genericController.view, genericController)
                            return
                        }
                    }
                    completion(view, controller)
                    return
                }
                if self.debugEditorLogs {
                    print("AU UI nil controller for \(self.reference.name), trying Cocoa UI")
                }
                if let cocoaView = self.makeCocoaView() {
                    completion(cocoaView, nil)
                    return
                }
                if self.debugEditorLogs {
                    print("AU UI Cocoa UI missing for \(self.reference.name), trying generic controller")
                }
                if let genericController = self.makeGenericController() {
                    self.cachedEditorController = genericController
                    completion(genericController.view, genericController)
                } else {
                    if self.debugEditorLogs {
                        print("AU UI failed for \(self.reference.name): no Cocoa or generic view")
                    }
                    completion(nil, nil)
                }
            }
        })
    }

    private func makeCocoaView() -> NSView? {
        guard let audioUnit else { return nil }
        guard let v2Bridge = audioUnit as? AUAudioUnitV2Bridge else {
            if debugEditorLogs {
                print("AU Cocoa UI missing AUAudioUnitV2Bridge for \(reference.name)")
            }
            return nil
        }
        let audioUnitRef = v2Bridge.audioUnit
        let cocoaInfoPtr = UnsafeMutablePointer<AudioUnitCocoaViewInfo>.allocate(capacity: 1)
        defer { cocoaInfoPtr.deallocate() }
        var dataSize = UInt32(MemoryLayout<AudioUnitCocoaViewInfo>.size)
        let status = AudioUnitGetProperty(
            audioUnitRef,
            kAudioUnitProperty_CocoaUI,
            kAudioUnitScope_Global,
            0,
            cocoaInfoPtr,
            &dataSize
        )
        guard status == noErr else {
            if debugEditorLogs {
                print("AU Cocoa UI property failed for \(reference.name) status=\(status)")
            }
            return nil
        }
        let cocoaInfo = cocoaInfoPtr.pointee
        let bundleURL = cocoaInfo.mCocoaAUViewBundleLocation.takeUnretainedValue() as URL
        let className = cocoaInfo.mCocoaAUViewClass.takeUnretainedValue() as String
        guard let bundle = Bundle(url: bundleURL) else {
            if debugEditorLogs {
                print("AU Cocoa UI failed to load bundle for \(reference.name) at \(bundleURL.path)")
            }
            return nil
        }
        if !bundle.isLoaded {
            bundle.load()
        }
        if debugEditorLogs {
            print("AU Cocoa UI bundle=\(bundleURL.path) class=\(className)")
        }
        guard let viewClass = bundle.classNamed(className) as? NSObject.Type else {
            if debugEditorLogs {
                print("AU Cocoa UI failed to find class \(className) for \(reference.name)")
            }
            return nil
        }
        let factory = viewClass.init()
        if let cocoaFactory = factory as? AUCocoaUIBase {
            let preferredSize = NSSize(width: 720, height: 520)
            let view = cocoaFactory.uiView(forAudioUnit: audioUnitRef, with: preferredSize)
            if debugEditorLogs, view == nil {
                print("AU Cocoa UI factory returned nil view for \(reference.name)")
            }
            return view
        }
        if let viewController = factory as? NSViewController {
            return viewController.view
        }
        if let view = factory as? NSView {
            return view
        }
        if debugEditorLogs {
            print("AU Cocoa UI factory unsupported type for \(reference.name)")
        }
        return nil
    }

    private func makeGenericController() -> NSViewController? {
        guard let audioUnit else { return nil }
        if #available(macOS 13.0, *) {
            let controller = AUGenericViewController()
            controller.auAudioUnit = audioUnit
            return controller
        }
        return nil
    }

    func parameters() -> [PluginParameter] {
        guard isReady, let tree = audioUnit?.parameterTree else { return [] }
        if cachedParameters.isEmpty {
            let params = tree.allParameters
            cachedParameters = params.map { param in
                let id = String(param.address)
                parameterMap[id] = param
                return PluginParameter(
                    id: id,
                    name: param.displayName,
                    value: Double(param.value),
                    minValue: Double(param.minValue),
                    maxValue: Double(param.maxValue),
                    unitName: param.unitName,
                    groupName: nil,
                    isReadOnly: !param.flags.contains(.flag_IsWritable)
                )
            }
        } else {
            cachedParameters = cachedParameters.map { param in
                var updated = param
                if let auParam = parameterMap[param.id] {
                    updated.value = Double(auParam.value)
                }
                return updated
            }
        }
        return cachedParameters
    }

    func setParameter(id: String, value: Double) {
        guard let parameter = parameterMap[id] else { return }
        parameter.value = AUValue(value)
        if debugParamLogs {
            print("AU Param set \(reference.name) \(parameter.displayName) addr=\(parameter.address) value=\(value)")
        }
    }

    func stateData() -> Data? {
        guard isReady, let audioUnit else { return nil }
        guard let fullState = audioUnit.fullState else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: fullState, format: .binary, options: 0)
    }

    func loadState(_ data: Data) {
        guard isReady, let audioUnit else { return }
        guard let state = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return }
        audioUnit.fullState = state
    }

    private func instantiateAudioUnit() {
        guard let componentType = reference.componentType,
              let componentSubType = reference.componentSubType,
              let componentManufacturer = reference.componentManufacturer else {
            return
        }

        let description = AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        AUAudioUnit.instantiate(with: description, options: []) { [weak self] unit, error in
            guard let self else { return }
            guard let unit else {
                if let error {
                    print("AU Instantiate failed for \(self.reference.name): \(error.localizedDescription)")
                } else {
                    print("AU Instantiate failed for \(self.reference.name): unknown error")
                }
                return
            }
            self.audioUnit = unit
            self.renderBlock = unit.renderBlock
            self.isReady = true
            if let state = self.reference.stateData {
                self.loadState(state)
            }
            DispatchQueue.main.async {
                self.onReady?()
            }
        }
    }

    private func configureAudioUnit(sampleRate: Double, channelCount: Int) {
        guard let audioUnit else { return }
        do {
            if audioUnit.renderResourcesAllocated {
                audioUnit.deallocateRenderResources()
            }
            var desiredChannels = channelCount
            if audioUnit.outputBusses.count > 0 {
                let supported = audioUnit.outputBusses[0].supportedChannelCounts ?? []
                let target = NSNumber(value: channelCount)
                if !supported.isEmpty && !supported.contains(target) {
                    if supported.contains(NSNumber(value: 1)) {
                        desiredChannels = 1
                    } else if let first = supported.first {
                        desiredChannels = first.intValue
                    }
                }
            }
            renderChannelCount = desiredChannels
            audioUnit.maximumFramesToRender = 8192
            guard let negotiatedFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(desiredChannels),
                interleaved: false
            ) else { return }
            if audioUnit.inputBusses.count > 0 {
                try audioUnit.inputBusses[0].setFormat(negotiatedFormat)
                audioUnit.inputBusses[0].isEnabled = true
            }
            if audioUnit.outputBusses.count > 0 {
                try audioUnit.outputBusses[0].setFormat(negotiatedFormat)
                audioUnit.outputBusses[0].isEnabled = true
            }
            audioUnit.maximumFramesToRender = max(audioUnit.maximumFramesToRender, UInt32(4096))
            audioUnit.shouldBypassEffect = false
            try audioUnit.allocateRenderResources()
            audioUnit.reset()
            currentSampleRate = sampleRate
            currentChannelCount = channelCount
            cachedParameters = []
            parameterMap = [:]
            didWarmUp = false
            warmUpIfNeeded(sampleRate: sampleRate, channelCount: renderChannelCount > 0 ? renderChannelCount : channelCount)
        } catch {
            // Ignore configuration failures.
            print("AU Configure failed for \(reference.name): \(error.localizedDescription)")
        }
    }

    private func requestConfigure(sampleRate: Double, channelCount: Int) {
        pendingSampleRate = sampleRate
        pendingChannelCount = channelCount
        guard !pendingConfigure else { return }
        pendingConfigure = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.configureAudioUnit(sampleRate: self.pendingSampleRate, channelCount: self.pendingChannelCount)
            self.pendingConfigure = false
        }
    }

    private func getMonoBufferList() -> UnsafeMutableAudioBufferListPointer {
        if let existing = monoBufferList {
            return existing
        }
        let created = AudioBufferList.allocate(maximumBuffers: 1)
        monoBufferList = created
        return created
    }

    private func getStereoBufferList() -> UnsafeMutableAudioBufferListPointer {
        if let existing = stereoBufferList {
            return existing
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

    private func copyInterleavedInputTo(_ ioData: UnsafeMutablePointer<AudioBufferList>, frameLength: Int, channelCount: Int) {
        let bufferList = UnsafeMutableAudioBufferListPointer(ioData)
        for channel in 0..<min(channelCount, bufferList.count) {
            guard let dst = bufferList[channel].mData else { continue }
            let dstPtr = dst.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameLength {
                dstPtr[frame] = inputScratch[channel][frame]
            }
        }
    }

    private func warmUpIfNeeded(sampleRate: Double, channelCount: Int) {
        guard !didWarmUp, let renderBlock, let audioUnit else { return }
        didWarmUp = true
        let maxFrames = Int(audioUnit.maximumFramesToRender)
        let frameLength = min(512, max(1, maxFrames))
        let channels = max(1, min(2, channelCount))

        DispatchQueue.global(qos: .userInitiated).async {
            let bufferList = AudioBufferList.allocate(maximumBuffers: channels)
            defer { bufferList.unsafeMutablePointer.deallocate() }

            var channelBuffers: [[Float]] = []
            channelBuffers.reserveCapacity(channels)
            for _ in 0..<channels {
                channelBuffers.append([Float](repeating: 0, count: frameLength))
            }

            for channel in 0..<channels {
                channelBuffers[channel].withUnsafeMutableBufferPointer { ptr in
                    guard let base = ptr.baseAddress else { return }
                    bufferList[channel] = AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: UInt32(frameLength * MemoryLayout<Float>.size),
                        mData: base
                    )
                }
            }

            let pullInput: AURenderPullInputBlock = { _, _, _, _, ioData in
                let ioList = UnsafeMutableAudioBufferListPointer(ioData)
                for buffer in ioList {
                    if let data = buffer.mData {
                        memset(data, 0, Int(buffer.mDataByteSize))
                    }
                }
                return noErr
            }

            var actionFlags = AudioUnitRenderActionFlags()
            var timeStamp = AudioTimeStamp()
            timeStamp.mFlags = .sampleTimeValid
            timeStamp.mSampleTime = 0

            for _ in 0..<10 {
                _ = renderBlock(&actionFlags, &timeStamp, AUAudioFrameCount(frameLength), 0, bufferList.unsafeMutablePointer, pullInput)
                timeStamp.mSampleTime += Double(frameLength)
            }
        }
    }
}
