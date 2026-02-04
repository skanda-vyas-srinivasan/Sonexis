import AppKit
import AVFoundation
import AVFAudio
import AudioToolbox
import AudioUnit
import CoreAudioKit
import Foundation

protocol PluginInstance: AnyObject {
    var reference: PluginReference { get }
    var isReady: Bool { get }
    var displayName: String { get }
    var vendorName: String { get }

    func ensureFormat(sampleRate: Double, channelCount: Int)
    func process(buffer: inout [[Float]], frameLength: Int, sampleRate: Double, channelCount: Int)
    func editorView() -> NSView?
    func parameters() -> [PluginParameter]
    func setParameter(id: String, value: Double)
    func stateData() -> Data?
    func loadState(_ data: Data)
}

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
    private let debugParamLogs = true
    private var monoBufferList: UnsafeMutableAudioBufferListPointer?
    private var stereoBufferList: UnsafeMutableAudioBufferListPointer?

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

    var displayName: String { reference.name }
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
            var output0 = buffer[0]
            status = output0.withUnsafeMutableBufferPointer { outPtr in
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
            buffer[0] = output0
            if channelCount == 2 {
                buffer[1] = output0
            }
        } else {
            var output0 = buffer[0]
            var output1 = buffer[1]
            status = output0.withUnsafeMutableBufferPointer { outPtr0 in
                guard let base0 = outPtr0.baseAddress else { return noErr }
                return output1.withUnsafeMutableBufferPointer { outPtr1 in
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
            buffer[0] = output0
            buffer[1] = output1
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
        if debugRenderCounter % 120 == 0 {
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

    func requestEditorView(completion: @escaping (NSView?) -> Void) {
        guard isReady, let audioUnit else {
            completion(nil)
            return
        }
        guard audioUnit.providesUserInterface else {
            completion(nil)
            return
        }
        let isAppleAU = reference.componentManufacturer == 1634758764
        let timeout: TimeInterval = isAppleAU ? 0.8 : 3.0
        var didComplete = false
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if !didComplete {
                didComplete = true
                completion(nil)
            }
        }
        audioUnit.requestViewController(completionHandler: { controller in
            DispatchQueue.main.async {
                guard !didComplete else { return }
                didComplete = true
                completion(controller?.view)
            }
        })
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

        AUAudioUnit.instantiate(with: description, options: []) { [weak self] unit, _ in
            guard let self else { return }
            guard let unit else { return }
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
        if inputScratch.count != channelCount || inputScratch.first?.count != frameLength {
            inputScratch = [[Float]](repeating: [Float](repeating: 0, count: frameLength), count: channelCount)
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
}

final class VST3PluginInstance: PluginInstance {
    let reference: PluginReference
    var isReady: Bool = false

    init(reference: PluginReference) {
        self.reference = reference
    }

    var displayName: String { reference.name }
    var vendorName: String { reference.vendor }

    func ensureFormat(sampleRate: Double, channelCount: Int) {
        // VST3 hosting requires the Steinberg SDK and is not wired yet.
    }

    func process(buffer: inout [[Float]], frameLength: Int, sampleRate: Double, channelCount: Int) {
        // No-op: VST3 hosting not configured.
    }

    func editorView() -> NSView? {
        nil
    }

    func parameters() -> [PluginParameter] {
        []
    }

    func setParameter(id: String, value: Double) {
        // No-op.
    }

    func stateData() -> Data? {
        nil
    }

    func loadState(_ data: Data) {
        // No-op.
    }
}

final class PluginHost {
    private var instances: [UUID: PluginInstance] = [:]
    private var references: [UUID: PluginReference] = [:]
    private let lock = NSLock()
    var onPluginReady: ((UUID) -> Void)?

    func sync(nodes: [BeginnerNode]) {
        lock.lock()
        defer { lock.unlock() }
        let pluginNodes = nodes.filter { $0.type == .plugin && $0.plugin != nil }
        let nodeIds = Set(pluginNodes.map { $0.id })
        instances = instances.filter { nodeIds.contains($0.key) }
        references = references.filter { nodeIds.contains($0.key) }

        for node in pluginNodes {
            guard let reference = node.plugin else { continue }
            if let existingRef = references[node.id], existingRef == reference {
                continue
            }
            references[node.id] = reference
            let instance = makeInstance(for: reference)
            if let auInstance = instance as? AUPluginInstance {
                auInstance.onReady = { [weak self] in
                    self?.onPluginReady?(node.id)
                }
            }
            instances[node.id] = instance
        }
    }

    func instance(for nodeId: UUID) -> PluginInstance? {
        lock.lock()
        defer { lock.unlock() }
        return instances[nodeId]
    }

    func isReady(nodeId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return instances[nodeId]?.isReady ?? false
    }

    func stateData(for nodeId: UUID) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return instances[nodeId]?.stateData()
    }

    func openEditor(for nodeId: UUID, fallbackView: NSView) {
        lock.lock()
        let instance = instances[nodeId]
        lock.unlock()
        guard let instance else { return }
        if let auInstance = instance as? AUPluginInstance {
            auInstance.requestEditorView { view in
                let editorView = view ?? fallbackView
                PluginEditorWindowController.shared.openWindow(for: nodeId, title: instance.displayName, contentView: editorView)
            }
            return
        }

        let editorView = instance.editorView() ?? fallbackView
        PluginEditorWindowController.shared.openWindow(for: nodeId, title: instance.displayName, contentView: editorView)
    }

    private func makeInstance(for reference: PluginReference) -> PluginInstance {
        switch reference.format {
        case .au:
            return AUPluginInstance(reference: reference)
        case .vst3:
            return VST3PluginInstance(reference: reference)
        }
    }
}

final class PluginEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = PluginEditorWindowController()
    private var windows: [UUID: NSWindowController] = [:]

    func openWindow(for nodeId: UUID, title: String, contentView: NSView) {
        if let controller = windows[nodeId], let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(nodeId.uuidString)
        window.delegate = self
        window.center()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        if contentView.superview != nil {
            contentView.removeFromSuperview()
        }
        container.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        window.contentView = container

        let controller = NSWindowController(window: window)
        windows[nodeId] = controller
        controller.showWindow(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

extension AudioEngine {
    func openPluginEditor(for nodeId: UUID, fallbackView: NSView) {
        pluginHost.openEditor(for: nodeId, fallbackView: fallbackView)
    }

    func pluginParameters(for nodeId: UUID) -> [PluginParameter] {
        pluginHost.instance(for: nodeId)?.parameters() ?? []
    }

    func setPluginParameter(for nodeId: UUID, parameterId: String, value: Double) {
        pluginHost.instance(for: nodeId)?.setParameter(id: parameterId, value: value)
    }

    func pluginStateData(for nodeId: UUID) -> Data? {
        pluginHost.stateData(for: nodeId)
    }

    func isPluginReady(_ nodeId: UUID) -> Bool {
        pluginHost.isReady(nodeId: nodeId)
    }
}
