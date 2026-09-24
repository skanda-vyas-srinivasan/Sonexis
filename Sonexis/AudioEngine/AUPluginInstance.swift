import AppKit
import AVFoundation
import AudioToolbox
import AudioToolbox.AUCocoaUIView
import AudioUnit
import CoreAudioKit
import Foundation

/// Main/lifecycle-side owner. It prepares replacement render states on a serial
/// queue and publishes them for the next processing snapshot. It is never called
/// by live rendering.
final class AUPluginInstance: PluginInstance {
    let reference: PluginReference
    var onReady: (() -> Void)?
    private let lifecycle: PluginRenderLifecycle
    private let retirementQueue: DispatchQueue

    init(reference: PluginReference) {
        self.reference = reference
        let retirementQueue = DispatchQueue(
            label: "Sonexis.AUPluginInstance.retirement",
            qos: .utility
        )
        self.retirementQueue = retirementQueue
        self.lifecycle = PluginRenderLifecycle(
            label: "Sonexis.AUPluginInstance.lifecycle",
            initialStateData: reference.stateData
        ) { format, stateData, completion in
            AUPreparedRenderState.prepare(
                reference: reference,
                format: format,
                stateData: stateData
            ) { result in
                completion(result.map {
                    DeferredReleasePluginRenderState(
                        state: $0,
                        retirementQueue: retirementQueue
                    ) as PluginRenderState
                })
            }
        }
        lifecycle.onPublication = { [weak self] in
            DispatchQueue.main.async { self?.onReady?() }
        }
    }

    var displayName: String { reference.displayName }
    var vendorName: String { reference.vendor }
    var renderState: PluginRenderState? { lifecycle.renderState }
    var isReady: Bool { renderState != nil }
    var failureDescription: String? { lifecycle.failureDescription }

    func prepare(format: PluginRenderFormat) {
        lifecycle.prepare(format: format)
    }

    func parameters() -> [PluginParameter] {
        preparedState?.parameters() ?? []
    }

    func setParameter(id: String, value: Double) {
        // AUParameter is the Audio Unit API designed for control changes while
        // rendering. No Sonexis lifecycle or publication lock is held here.
        preparedState?.setParameter(id: id, value: value)
    }

    func stateData() -> Data? {
        // State reads may be slow inside a third-party unit, but they never hold
        // a Sonexis lock needed by the processing worker.
        preparedState?.stateData()
    }

    func loadState(_ data: Data) {
        lifecycle.loadState(data)
    }

    func editorView() -> NSView? { nil }

    func requestEditor(completion: @escaping (NSView?, NSViewController?) -> Void) {
        guard let state = preparedState else {
            completion(nil, nil)
            return
        }
        state.requestEditor(completion: completion)
    }

    private var preparedState: AUPreparedRenderState? {
        let state = renderState
        if let deferred = state as? DeferredReleasePluginRenderState {
            return deferred.wrappedState as? AUPreparedRenderState
        }
        return state as? AUPreparedRenderState
    }
}

enum AUPreparationError: LocalizedError {
    case invalidIdentity
    case invalidFormat
    case instantiation(String)
    case configuration(String)

    var errorDescription: String? {
        switch self {
        case .invalidIdentity: return "Audio Unit identity is incomplete."
        case .invalidFormat: return "Audio Unit render format is invalid."
        case .instantiation(let message): return "Audio Unit instantiation failed: \(message)"
        case .configuration(let message): return "Audio Unit configuration failed: \(message)"
        }
    }
}

/// Fully configured render generation. After construction, render resources and
/// format are immutable. Processing is the sole owner of scratch buffers and
/// render timing; lifecycle replacement creates another instance instead.
final class AUPreparedRenderState: PluginRenderState {
    let format: PluginRenderFormat
    private let reference: PluginReference
    private let audioUnit: AUAudioUnit
    private let renderBlock: AURenderBlock
    private let renderChannelCount: Int
    private var inputScratch: [[Float]]
    private var sampleTime: Double = 0
    private let monoBufferList: UnsafeMutableAudioBufferListPointer
    private let stereoBufferList: UnsafeMutableAudioBufferListPointer
    private var cachedParameters: [PluginParameter] = []
    private var parameterMap: [String: AUParameter] = [:]
    private var cachedEditorController: NSViewController?

    private init(
        reference: PluginReference,
        format: PluginRenderFormat,
        audioUnit: AUAudioUnit,
        renderChannelCount: Int
    ) {
        self.reference = reference
        self.format = format
        self.audioUnit = audioUnit
        self.renderBlock = audioUnit.renderBlock
        self.renderChannelCount = renderChannelCount
        self.inputScratch = [[Float]](
            repeating: [Float](repeating: 0, count: format.maximumFrameCount),
            count: renderChannelCount
        )
        self.monoBufferList = AudioBufferList.allocate(maximumBuffers: 1)
        self.stereoBufferList = AudioBufferList.allocate(maximumBuffers: 2)
    }

    deinit {
        monoBufferList.unsafeMutablePointer.deallocate()
        stereoBufferList.unsafeMutablePointer.deallocate()
    }

    static func prepare(
        reference: PluginReference,
        format: PluginRenderFormat,
        stateData: Data?,
        completion: @escaping (Result<AUPreparedRenderState, Error>) -> Void
    ) {
        guard format.sampleRate > 0,
              (1...2).contains(format.channelCount),
              format.maximumFrameCount > 0 else {
            completion(.failure(AUPreparationError.invalidFormat))
            return
        }
        guard let componentType = reference.componentType,
              let componentSubType = reference.componentSubType,
              let componentManufacturer = reference.componentManufacturer else {
            completion(.failure(AUPreparationError.invalidIdentity))
            return
        }

        let description = AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        AUAudioUnit.instantiate(with: description, options: []) { unit, error in
            guard let unit else {
                completion(.failure(AUPreparationError.instantiation(error?.localizedDescription ?? "unknown error")))
                return
            }
            do {
                if let stateData,
                   let state = try PropertyListSerialization.propertyList(
                    from: stateData,
                    options: [],
                    format: nil
                   ) as? [String: Any] {
                    unit.fullState = state
                }
                let renderChannels = try configure(unit: unit, format: format)
                let state = AUPreparedRenderState(
                    reference: reference,
                    format: format,
                    audioUnit: unit,
                    renderChannelCount: renderChannels
                )
                try state.warmUp()
                completion(.success(state))
            } catch {
                completion(.failure(AUPreparationError.configuration(error.localizedDescription)))
            }
        }
    }

    private static func configure(unit: AUAudioUnit, format: PluginRenderFormat) throws -> Int {
        var desiredChannels = format.channelCount
        if unit.outputBusses.count > 0 {
            let supported = unit.outputBusses[0].supportedChannelCounts ?? []
            let requested = NSNumber(value: format.channelCount)
            if !supported.isEmpty && !supported.contains(requested) {
                if supported.contains(NSNumber(value: 1)) {
                    desiredChannels = 1
                } else if let first = supported.first {
                    desiredChannels = first.intValue
                }
            }
        }
        guard (1...2).contains(desiredChannels),
              let negotiatedFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: format.sampleRate,
                channels: AVAudioChannelCount(desiredChannels),
                interleaved: false
              ) else {
            throw AUPreparationError.invalidFormat
        }
        unit.maximumFramesToRender = AUAudioFrameCount(max(format.maximumFrameCount, 4_096))
        if unit.inputBusses.count > 0 {
            try unit.inputBusses[0].setFormat(negotiatedFormat)
            unit.inputBusses[0].isEnabled = true
        }
        if unit.outputBusses.count > 0 {
            try unit.outputBusses[0].setFormat(negotiatedFormat)
            unit.outputBusses[0].isEnabled = true
        }
        unit.shouldBypassEffect = false
        try unit.allocateRenderResources()
        unit.reset()
        return desiredChannels
    }

    @discardableResult
    func process(
        buffer: inout [[Float]],
        frameLength: Int,
        sampleRate: Double,
        channelCount: Int
    ) -> Bool {
        guard sampleRate == format.sampleRate,
              channelCount == format.channelCount,
              frameLength > 0,
              frameLength <= format.maximumFrameCount,
              buffer.count >= channelCount else { return false }

        if renderChannelCount == 1 {
            for frame in 0..<frameLength {
                inputScratch[0][frame] = channelCount == 2
                    ? 0.5 * (buffer[0][frame] + buffer[1][frame])
                    : buffer[0][frame]
            }
        } else {
            for channel in 0..<renderChannelCount {
                for frame in 0..<frameLength {
                    inputScratch[channel][frame] = buffer[channel][frame]
                }
            }
        }

        var actionFlags = AudioUnitRenderActionFlags()
        var timeStamp = AudioTimeStamp()
        timeStamp.mFlags = .sampleTimeValid
        timeStamp.mSampleTime = sampleTime
        sampleTime += Double(frameLength)
        let pullInput: AURenderPullInputBlock = { [self] _, _, _, _, ioData in
            copyInput(to: ioData, frameLength: frameLength)
            return noErr
        }

        let status: OSStatus
        if renderChannelCount == 1 {
            status = buffer[0].withUnsafeMutableBufferPointer { output in
                guard let base = output.baseAddress else { return kAudio_ParamError }
                monoBufferList[0] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frameLength * MemoryLayout<Float>.size),
                    mData: base
                )
                return renderBlock(
                    &actionFlags, &timeStamp, AUAudioFrameCount(frameLength), 0,
                    monoBufferList.unsafeMutablePointer, pullInput
                )
            }
            if status == noErr, channelCount == 2 {
                for frame in 0..<frameLength { buffer[1][frame] = buffer[0][frame] }
            }
        } else {
            status = buffer.withUnsafeMutableBufferPointer { channels in
                channels[0].withUnsafeMutableBufferPointer { left in
                    channels[1].withUnsafeMutableBufferPointer { right in
                        guard let leftBase = left.baseAddress, let rightBase = right.baseAddress else {
                            return kAudio_ParamError
                        }
                        stereoBufferList[0] = AudioBuffer(
                            mNumberChannels: 1,
                            mDataByteSize: UInt32(frameLength * MemoryLayout<Float>.size),
                            mData: leftBase
                        )
                        stereoBufferList[1] = AudioBuffer(
                            mNumberChannels: 1,
                            mDataByteSize: UInt32(frameLength * MemoryLayout<Float>.size),
                            mData: rightBase
                        )
                        return renderBlock(
                            &actionFlags, &timeStamp, AUAudioFrameCount(frameLength), 0,
                            stereoBufferList.unsafeMutablePointer, pullInput
                        )
                    }
                }
            }
        }
        return status == noErr
    }

    private func copyInput(to ioData: UnsafeMutablePointer<AudioBufferList>, frameLength: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        for channel in 0..<min(renderChannelCount, buffers.count) {
            guard let destination = buffers[channel].mData else { continue }
            let samples = destination.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameLength { samples[frame] = inputScratch[channel][frame] }
        }
    }

    private func warmUp() throws {
        let frameLength = min(512, format.maximumFrameCount)
        var silent = [[Float]](
            repeating: [Float](repeating: 0, count: frameLength),
            count: format.channelCount
        )
        for _ in 0..<10 {
            guard process(
                buffer: &silent,
                frameLength: frameLength,
                sampleRate: format.sampleRate,
                channelCount: format.channelCount
            ) else {
                throw AUPreparationError.configuration("warm-up render failed")
            }
        }
        sampleTime = 0
    }

    func parameters() -> [PluginParameter] {
        guard let tree = audioUnit.parameterTree else { return [] }
        if cachedParameters.isEmpty {
            cachedParameters = tree.allParameters.map { parameter in
                let id = String(parameter.address)
                parameterMap[id] = parameter
                return PluginParameter(
                    id: id,
                    name: parameter.displayName,
                    value: Double(parameter.value),
                    minValue: Double(parameter.minValue),
                    maxValue: Double(parameter.maxValue),
                    unitName: parameter.unitName,
                    groupName: nil,
                    isReadOnly: !parameter.flags.contains(.flag_IsWritable)
                )
            }
        }
        return cachedParameters.map { descriptor in
            var descriptor = descriptor
            if let parameter = parameterMap[descriptor.id] {
                descriptor.value = Double(parameter.value)
            }
            return descriptor
        }
    }

    func setParameter(id: String, value: Double) {
        if parameterMap.isEmpty { _ = parameters() }
        parameterMap[id]?.value = AUValue(value)
    }

    func stateData() -> Data? {
        guard let fullState = audioUnit.fullState else { return nil }
        return try? PropertyListSerialization.data(
            fromPropertyList: fullState,
            format: .binary,
            options: 0
        )
    }

    func requestEditor(completion: @escaping (NSView?, NSViewController?) -> Void) {
        if let cachedEditorController {
            DispatchQueue.main.async {
                let view = cachedEditorController.view
                view.removeFromSuperview()
                completion(view, cachedEditorController)
            }
            return
        }
        audioUnit.requestViewController { [weak self] controller in
            DispatchQueue.main.async {
                guard let self else { return }
                if let controller {
                    self.cachedEditorController = controller
                    completion(controller.view, controller)
                    return
                }
                let generic = AUGenericViewController()
                generic.auAudioUnit = self.audioUnit
                self.cachedEditorController = generic
                completion(generic.view, generic)
            }
        }
    }
}
