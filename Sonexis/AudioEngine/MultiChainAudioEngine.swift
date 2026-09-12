import AVFoundation
import Combine
import CoreAudio
import Foundation

struct AudioChainDefinition: Codable, Identifiable {
    let id: UUID
    var target: AudioCaptureTarget? // nil is the default for unassigned apps
    var graph: GraphSnapshot
    var effectsEnabled: Bool
    var presetID: UUID?
    var inputTrimDB: Double = ProcessTapRuntimeSettings.defaults.inputTrimDB
    var outputMakeupDB: Double = ProcessTapRuntimeSettings.defaults.outputMakeupDB
    var outputCeilingEnabled: Bool = ProcessTapRuntimeSettings.defaults.outputCeilingEnabled
}

struct AudioChainRoutingPlan: Equatable {
    let selections: [UUID: ProcessTapSelection]

    init(chains: [AudioChainDefinition], resolve: (AudioCaptureTarget) throws -> Set<AudioObjectID>) throws {
        guard chains.filter({ $0.target == nil }).count == 1,
              Set(chains.map(\.id)).count == chains.count else {
            throw PrototypeError(message: "Chains need unique IDs and exactly one default chain")
        }
        var targets = Set<String>()
        var assigned = Set<AudioObjectID>()
        var selections: [UUID: ProcessTapSelection] = [:]
        for chain in chains where chain.target != nil {
            let target = chain.target!
            guard targets.insert(target.bundleID).inserted else {
                throw PrototypeError(message: "An app can only have one chain")
            }
            let ids = try resolve(target).subtracting([kAudioObjectUnknown])
            guard assigned.isDisjoint(with: ids) else {
                throw PrototypeError(message: "An audio process matched more than one app chain")
            }
            assigned.formUnion(ids)
            selections[chain.id] = .only(ids)
        }
        selections[chains.first(where: { $0.target == nil })!.id] = .allAudio(excluding: assigned)
        self.selections = selections
    }
}

protocol AudioChainPipeline: AnyObject {
    func start() throws
    func stopImmediately(reason: String)
}
extension ProcessTapDSPEngine: AudioChainPipeline {}

/// Cancellation is advisory: HAL calls cannot be interrupted safely. The same
/// serial owner must finish that call and release its resources before retrying.
private final class AudioLifecycleRequest {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

/// Accessed only on the audio lifecycle queue, including timers/listeners in its
/// Process Tap pipelines. Retains processors until their IO callbacks are gone.
private final class AudioPipelineSession {
    var pipelines: [AudioChainPipeline] = []
    var processors: [AudioEngine] = []
    var plan: AudioChainRoutingPlan?

    func stop() {
        for pipeline in pipelines { pipeline.stopImmediately(reason: "multi-chain routing transition") }
        pipelines.removeAll()
        processors.removeAll()
        plan = nil
    }
}

/// Owns one chain's recording ring and reports an incompatible live format only
/// once. Audio callbacks remain limited to validation plus the lock-free write.
private final class CombinedRecordingInput {
    let ring: RealtimeRingBuffer
    let expectedChannels: Int
    let expectedSampleRate: Double
    private let issueLock = NSLock()
    private var didReportFormatIssue = false

    init(ring: RealtimeRingBuffer, channels: Int, sampleRate: Double) {
        self.ring = ring
        expectedChannels = channels
        expectedSampleRate = sampleRate
    }

    func append(_ samples: UnsafePointer<Float>, frames: Int, channels: Int,
                sampleRate: Double) -> String? {
        guard frames > 0 else { return nil }
        guard channels == expectedChannels, sampleRate == expectedSampleRate else {
            issueLock.lock()
            let shouldReport = !didReportFormatIssue
            didReportFormatIssue = true
            issueLock.unlock()
            return shouldReport
                ? "Recording stopped because one chain's audio format changed. Start a new recording."
                : nil
        }
        _ = ring.writeInterleaved(samples, frames: UInt32(frames))
        return nil
    }
}

/// Graphs and UI state belong to the main thread. HAL ownership belongs to one
/// serial queue; UI cancellation never tears down a pipeline concurrently.
final class MultiChainAudioEngine: ObservableObject {
    enum State: Equatable { case stopped, starting, stopping, running, failed(String) }
    // Both callbacks execute on the serial audio queue, never on main.
    typealias Resolver = (AudioCaptureTarget) throws -> Set<AudioObjectID>
    typealias PipelineFactory = (AudioEngine, ProcessTapSelection) -> AudioChainPipeline

    @Published private(set) var definitions: [AudioChainDefinition] = []
    @Published private(set) var state: State = .stopped
    @Published private(set) var isTransitioning = false
    private(set) var processors: [UUID: AudioEngine] = [:]
    private var processTimer: Timer?
    @Published private(set) var globallyBypassed = false
    var onConfigurationRestored: (() -> Void)?

    // MARK: - Combined recording
    // One recording session captures the mixed, post-processing output of
    // every chain at once rather than a single selected chain.
    @Published private(set) var isRecording = false
    @Published private(set) var isFinalizingRecording = false
    @Published var recordingWarningText: String?
    @Published var recordingIssuePresented = false
    @Published private(set) var lastRecordingURL: URL?
    private var combinedRecordingSessionID: UUID?
    private var combinedRecordingSession: AudioRecordingSession?
    // Guards recordingInputs structure only: mutated on main (attach/detach) and
    // iterated on mixerQueue. Each ring's own audio data is still handed off
    // lock-free via its SPSC write/read calls.
    private let recordingRingsLock = NSLock()
    private var recordingInputs: [UUID: CombinedRecordingInput] = [:]
    private var recordingMixScratch: [Float] = []
    private var recordingChainScratch: [Float] = []
    private var recordingChunkFrames: Int = 0
    private var recordingChannelCount: Int = 0
    private var recordingSampleRate: Double = 0
    private let recordingPrerollChunks = 12
    private var mixerTimer: DispatchSourceTimer?
    private let mixerQueue = DispatchQueue(label: "Sonexis.CombinedRecordingMixer", qos: .userInitiated)
    private let resolve: Resolver
    private let makePipeline: PipelineFactory
    private let lifecycleQueue: DispatchQueue
    private let session = AudioPipelineSession()
    private let operationTimeout: TimeInterval
    private var request: AudioLifecycleRequest?
    private var timeoutWork: DispatchWorkItem?

    init(resolve: @escaping Resolver = { Set(try $0.processObjectIDs(excluding: kAudioObjectUnknown)) },
         makePipeline: PipelineFactory? = nil,
         operationTimeout: TimeInterval = 10) {
        let queue = DispatchQueue(label: "Sonexis.AudioLifecycle", qos: .userInitiated)
        self.lifecycleQueue = queue
        self.resolve = resolve
        self.operationTimeout = operationTimeout
        self.makePipeline = makePipeline ?? {
            ProcessTapDSPEngine(audioProcessor: $0, fixedSelection: $1, lifecycleQueue: queue)
        }
    }

    private func install(_ next: [AudioChainDefinition], reusing existing: [UUID: AudioEngine]) {
        let retainedIDs = Set(next.map(\.id))
        for (id, processor) in existing where !retainedIDs.contains(id) {
            processor.isRunning = false
            processor.isPowerTransitioning = false
            processor.resetOutputMeter()
            if isRecording { detachRecording(chainID: id) }
        }
        var nextProcessors: [UUID: AudioEngine] = [:]
        var recordingAttachFailed = false
        for chain in next {
            let processor = existing[chain.id] ?? AudioEngine(observeSystemLifecycle: false)
            processor.applyIndependentGraph(chain.graph)
            processor.processTapInputTrimDB = chain.inputTrimDB
            processor.processTapOutputMakeupDB = chain.outputMakeupDB
            processor.processTapOutputCeilingEnabled = chain.outputCeilingEnabled
            processor.processingEnabled = chain.effectsEnabled && !globallyBypassed
            processor.publishProcessingState()
            nextProcessors[chain.id] = processor
            if isRecording && !attachRecording(to: processor, chainID: chain.id) {
                recordingAttachFailed = true
            }
        }
        processors = nextProcessors
        definitions = next
        if recordingAttachFailed && isRecording {
            recordingWarningText = "Recording stopped because an input buffer could not be prepared for a new chain."
            recordingIssuePresented = true
            stopRecording()
        }
    }

    func configure(_ next: [AudioChainDefinition], rollbackOnAudioFailure: Bool = true,
                   completion: ((Bool) -> Void)? = nil) throws {
        precondition(Thread.isMainThread)
        guard !isTransitioning else { throw PrototypeError(message: "Wait for the audio transition to finish.") }
        // Structural checks never query HAL on the UI thread.
        _ = try AudioChainRoutingPlan(chains: next, resolve: { _ in [] })
        for chain in next { try chain.graph.validateForIndependentProcessing() }
        let previous = definitions
        let previousProcessors = processors
        let wasRunning = state == .running
        install(next, reusing: previousProcessors)
        if wasRunning {
            let restore: (() -> Void)? = rollbackOnAudioFailure ? { [weak self] in
                guard let self else { return }
                self.install(previous, reusing: previousProcessors)
                self.onConfigurationRestored?()
            } : nil
            transition(rollback: restore, completion: completion)
        } else { setState(.stopped); completion?(true) }
    }

    /// Capture editor changes without reapplying graphs or restarting workers.
    func captureDefinitions(excluding suspended: Set<UUID> = []) {
        var captured = definitions
        for index in captured.indices where !suspended.contains(captured[index].id) {
            guard let processor = processors[captured[index].id] else { continue }
            if let graph = processor.pendingGraphLoadRequest?.snapshot ?? processor.currentGraphSnapshot {
                captured[index].graph = graph
            }
            if !globallyBypassed { captured[index].effectsEnabled = processor.processingEnabled }
            captured[index].inputTrimDB = processor.processTapInputTrimDB
            captured[index].outputMakeupDB = processor.processTapOutputMakeupDB
            captured[index].outputCeilingEnabled = processor.processTapOutputCeilingEnabled
        }
        // The periodic persistence refresh must not redraw the entire menu bar
        // when every captured value is unchanged.
        if let capturedData = Self.persistenceData(for: captured),
           let currentData = Self.persistenceData(for: definitions),
           capturedData == currentData { return }
        definitions = captured
    }

    private static func persistenceData(for definitions: [AudioChainDefinition]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(definitions)
    }

    func setPresetID(_ presetID: UUID?, chainID: UUID) {
        guard let index = definitions.firstIndex(where: { $0.id == chainID }) else { return }
        definitions[index].presetID = presetID
    }

    /// Reorders only the workspace presentation. Active processors and audio
    /// pipelines are keyed by chain ID, so tab movement must not restart sound.
    @discardableResult
    func moveAppChain(_ movingID: UUID, toPositionOf destinationID: UUID) -> Bool {
        precondition(Thread.isMainThread)
        guard movingID != destinationID,
              let sourceIndex = definitions.firstIndex(where: { $0.id == movingID && $0.target != nil }),
              let destinationIndex = definitions.firstIndex(where: { $0.id == destinationID && $0.target != nil })
        else { return false }

        var reordered = definitions
        let moving = reordered.remove(at: sourceIndex)
        reordered.insert(moving, at: min(destinationIndex, reordered.count))
        definitions = reordered
        return true
    }

    func start() throws {
        precondition(Thread.isMainThread)
        guard state != .running, !isTransitioning else { return }
        _ = try AudioChainRoutingPlan(chains: definitions, resolve: { _ in [] })
        transition()
    }

    func stop() {
        precondition(Thread.isMainThread)
        processTimer?.invalidate()
        processTimer = nil
        stopRecording()
        if let request {
            request.cancel()
            setState(.stopping)
            return // The pending operation owns cleanup, even if HAL is stalled.
        }
        guard state != .stopped else { return }
        let token = beginRequest(state: .stopping)
        let session = session
        lifecycleQueue.async { [weak self] in
            session.stop()
            DispatchQueue.main.async { self?.complete(token, error: nil) }
        }
    }

    func refreshProcesses() throws {
        precondition(Thread.isMainThread)
        guard state == .running, !isTransitioning else { return }
        transition(refreshOnly: true)
    }

    private func setState(_ next: State) {
        state = next
        for processor in processors.values {
            processor.isRunning = next == .running
            processor.isPowerTransitioning = isTransitioning && next != .running
            if next != .running { processor.resetOutputMeter() }
        }
    }

    private func beginRequest(state: State) -> AudioLifecycleRequest {
        let token = AudioLifecycleRequest()
        request = token
        isTransitioning = true
        setState(state)
        let timeout = DispatchWorkItem { [weak self, weak token] in
            guard let self, let token, self.request === token else { return }
            token.cancel()
            self.setState(.failed("Core Audio is not responding. Cancellation is pending; you can keep using the editor. Retry audio after cleanup finishes, or quit and reopen Sonexis."))
        }
        timeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + operationTimeout, execute: timeout)
        return token
    }

    private func complete(_ token: AudioLifecycleRequest, error: Error?, rollback: (() -> Void)? = nil,
                          completion: ((Bool) -> Void)? = nil) {
        precondition(Thread.isMainThread)
        guard request === token else { return }
        if token.isCancelled {
            // Cancellation may arrive after the worker's last check, while its
            // completion is queued on main. Always acknowledge cleanup first.
            let session = session
            lifecycleQueue.async { [weak self] in
                session.stop()
                DispatchQueue.main.async {
                    guard let self, self.request === token else { return }
                    self.timeoutWork?.cancel()
                    self.timeoutWork = nil
                    self.request = nil
                    self.isTransitioning = false
                    if case .failed = self.state { self.setState(self.state) }
                    else { self.setState(.stopped) }
                    completion?(true) // Explicit cancellation preserves the accepted document.
                }
            }
            return
        }
        timeoutWork?.cancel()
        timeoutWork = nil
        request = nil
        isTransitioning = false
        if let error {
            if let rollback {
                rollback()
                completion?(false)
                transition() // Old partitions were fully stopped before restore.
                return
            }
            setState(.failed("Could not start audio: \(error)"))
            completion?(false)
        } else {
            setState(state == .stopping ? .stopped : .running)
            if state == .running { startProcessTimer() }
            completion?(true)
        }
    }

    private func transition(refreshOnly: Bool = false, rollback: (() -> Void)? = nil,
                            completion: ((Bool) -> Void)? = nil) {
        let token = beginRequest(state: refreshOnly ? .running : .starting)
        let definitions = definitions, processors = processors
        let session = session, resolve = resolve, factory = makePipeline
        lifecycleQueue.async { [weak self] in
            var failure: Error?
            do {
                guard !token.isCancelled else { throw PrototypeError(message: "Audio operation cancelled") }
                let plan = try AudioChainRoutingPlan(chains: definitions, resolve: resolve)
                if !refreshOnly || plan != session.plan {
                    session.stop()
                    if !token.isCancelled {
                        session.processors = Array(processors.values)
                        for chain in definitions {
                            if token.isCancelled { break }
                            guard let processor = processors[chain.id], let selection = plan.selections[chain.id] else {
                                throw PrototypeError(message: "Chain processor or route is missing")
                            }
                            let pipeline = factory(processor, selection)
                            session.pipelines.append(pipeline)
                            try pipeline.start()
                        }
                        session.plan = plan
                    }
                }
            } catch { failure = error }
            if failure != nil || token.isCancelled { session.stop() }
            let result = failure
            DispatchQueue.main.async { self?.complete(token, error: result, rollback: rollback, completion: completion) }
        }
    }

    private func startProcessTimer() {
        guard processTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            try? self?.refreshProcesses()
        }
        processTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func setGlobalBypass(_ bypassed: Bool) {
        precondition(Thread.isMainThread)
        globallyBypassed = bypassed
        for chain in definitions {
            processors[chain.id]?.processingEnabled = chain.effectsEnabled && !bypassed
            processors[chain.id]?.publishProcessingState()
        }
    }

    func setEffectsEnabled(_ enabled: Bool, chainID: UUID) {
        precondition(Thread.isMainThread)
        guard let index = definitions.firstIndex(where: { $0.id == chainID }) else { return }
        definitions[index].effectsEnabled = enabled
        processors[chainID]?.processingEnabled = enabled && !globallyBypassed
        processors[chainID]?.publishProcessingState()
    }

    func updateGraph(_ graph: GraphSnapshot, chainID: UUID) throws {
        precondition(Thread.isMainThread)
        try graph.validateForIndependentProcessing()
        guard let index = definitions.firstIndex(where: { $0.id == chainID }), let processor = processors[chainID] else {
            throw PrototypeError(message: "Unknown chain")
        }
        processor.applyIndependentGraph(graph)
        definitions[index].graph = graph
    }

    deinit {
        processTimer?.invalidate()
        timeoutWork?.cancel()
        request?.cancel()
        mixerTimer?.cancel()
        let session = session
        lifecycleQueue.async { session.stop() }
    }

}

extension MultiChainAudioEngine {
    /// Starts one recording that captures the mixed, post-processing output of
    /// every currently running chain. Chains added or removed while recording
    /// is in progress are attached to or dropped from the mix automatically.
    func startRecording(url: URL) {
        precondition(Thread.isMainThread)
        guard !isRecording, !isFinalizingRecording else { return }
        let formats = processors.values.compactMap { $0.currentTapFormat() }
        guard formats.count == processors.count, let format = formats.first else {
            recordingWarningText = "Recording is not ready yet. Start audio first."
            recordingIssuePresented = true
            return
        }
        guard formats.allSatisfy({ $0.channels == format.channels && abs($0.sampleRate - format.sampleRate) < 0.5 }) else {
            recordingWarningText = "Recording could not start because the active chains use different audio formats."
            recordingIssuePresented = true
            return
        }
        let chunkFrames = max(formats.map(\.frames).max() ?? format.frames, 256)
        let channels = format.channels
        let sampleRate = format.sampleRate
        let id = UUID()
        do {
            let session = try AudioRecordingSession(url: url, sampleRate: sampleRate,
                channels: AVAudioChannelCount(channels), frameCapacity: chunkFrames) { [weak self] message in
                DispatchQueue.main.async {
                    guard let self, self.combinedRecordingSessionID == id else { return }
                    self.recordingWarningText = message
                    if self.combinedRecordingSession?.mustStop == true { self.stopRecording() }
                }
            }
            combinedRecordingSessionID = id
            combinedRecordingSession = session
            recordingWarningText = nil
            recordingIssuePresented = false
            lastRecordingURL = nil
            recordingChunkFrames = chunkFrames
            recordingChannelCount = channels
            recordingSampleRate = sampleRate
            recordingMixScratch = [Float](repeating: 0, count: chunkFrames * channels)
            recordingChainScratch = [Float](repeating: 0, count: chunkFrames * channels)
            for (chainID, processor) in processors {
                guard attachRecording(to: processor, chainID: chainID) else {
                    for attachedID in currentRecordingInputIDs() { detachRecording(chainID: attachedID) }
                    combinedRecordingSession = nil
                    session.stop { _ in }
                    recordingWarningText = "Recording could not allocate an input buffer for every active chain."
                    recordingIssuePresented = true
                    return
                }
            }
            isRecording = true
            startMixerTimer()
        } catch {
            recordingWarningText = "Recording failed: \(error.localizedDescription)"
            recordingIssuePresented = true
        }
    }

    func stopRecording(waitForWrites: Bool = false) {
        precondition(Thread.isMainThread)
        guard let session = combinedRecordingSession else { return }
        if !isFinalizingRecording {
            isRecording = false
            isFinalizingRecording = true
            stopMixerTimer()
            for chainID in currentRecordingInputIDs() { processors[chainID]?.recordingSink = nil }
            // DispatchSource cancellation does not wait for an event handler that
            // is already running. Drain the serial mixer queue before finalizing.
            mixerQueue.sync {
                while self.canMixRecordingChunk() { self.mixTick() }
            }
            recordingRingsLock.lock()
            let finishedInputs = Array(recordingInputs.values)
            recordingInputs.removeAll()
            recordingRingsLock.unlock()
            // A process tap is allowed to be idle when its app is silent. The
            // mixer substitutes silence for that input, so ring underflow is
            // not missing final-output audio. Overflow is the only transport
            // condition that means samples were actually discarded.
            let transportLoss = finishedInputs.reduce(into: UInt64(0)) { total, input in
                total += input.ring.droppedFrames
            }
            let id = combinedRecordingSessionID
            session.stop { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.combinedRecordingSessionID == id else { return }
                    self.combinedRecordingSession = nil
                    self.isFinalizingRecording = false
                    self.lastRecordingURL = result.url
                    if let error = result.error {
                        self.recordingWarningText = error
                    } else if result.droppedFrames > 0 || transportLoss > 0 {
                        let missingFrames = UInt64(max(result.droppedFrames, 0)) + transportLoss
                        self.recordingWarningText = "Recording finished with \(missingFrames) missing frames. The saved file contains gaps."
                    }
                    self.recordingIssuePresented = self.recordingWarningText != nil
                }
            }
        }
        if waitForWrites { session.waitForWrites() }
    }

    @discardableResult
    private func attachRecording(to processor: AudioEngine, chainID: UUID) -> Bool {
        precondition(Thread.isMainThread)
        guard recordingChannelCount > 0, recordingSampleRate > 0, recordingChunkFrames > 0 else { return false }
        recordingRingsLock.lock()
        let alreadyAttached = recordingInputs[chainID] != nil
        recordingRingsLock.unlock()
        guard !alreadyAttached else { return true }
        let expectedChannels = recordingChannelCount
        let expectedSampleRate = recordingSampleRate
        let capacityFrames = max(UInt32(recordingSampleRate * 1.5), UInt32(recordingChunkFrames * recordingPrerollChunks * 2))
        guard let ring = try? RealtimeRingBuffer(capacityFrames: capacityFrames, channels: UInt32(expectedChannels)) else { return false }
        ring.setTargetFillFrames(UInt32(recordingChunkFrames * recordingPrerollChunks))
        let input = CombinedRecordingInput(ring: ring, channels: expectedChannels, sampleRate: expectedSampleRate)
        recordingRingsLock.lock()
        recordingInputs[chainID] = input
        recordingRingsLock.unlock()
        processor.recordingSink = { [weak self, weak input] samples, frames, channels, sampleRate in
            guard let input else { return }
            if let issue = input.append(samples, frames: frames, channels: channels, sampleRate: sampleRate) {
                DispatchQueue.main.async {
                    guard let self, self.isRecording else { return }
                    self.recordingWarningText = issue
                    self.stopRecording()
                }
            }
        }
        return true
    }

    private func detachRecording(chainID: UUID) {
        precondition(Thread.isMainThread)
        processors[chainID]?.recordingSink = nil
        recordingRingsLock.lock()
        recordingInputs[chainID] = nil
        recordingRingsLock.unlock()
    }

    private func currentRecordingInputIDs() -> [UUID] {
        recordingRingsLock.lock()
        defer { recordingRingsLock.unlock() }
        return Array(recordingInputs.keys)
    }

    private func startMixerTimer() {
        let interval = Double(recordingChunkFrames) / recordingSampleRate
        let timer = DispatchSource.makeTimerSource(queue: mixerQueue)
        // The wall clock owns recording duration. Individual process taps may
        // legitimately stop producing callbacks while their app is silent.
        // Keep a short jitter buffer so callbacks from independently scheduled taps
        // land before their shared wall-clock mix slot.
        timer.schedule(deadline: .now() + interval * Double(recordingPrerollChunks),
            repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.mixTick() }
        timer.resume()
        mixerTimer = timer
    }

    private func stopMixerTimer() {
        mixerTimer?.cancel()
        mixerTimer = nil
    }

    private func canMixRecordingChunk() -> Bool {
        recordingRingsLock.lock()
        let inputs = Array(recordingInputs.values)
        recordingRingsLock.unlock()
        let participatingInputs = inputs.filter { $0.ring.writtenFrames > 0 }
        return !participatingInputs.isEmpty && participatingInputs.allSatisfy {
            $0.ring.fillFrames >= UInt32(recordingChunkFrames)
        }
    }

    /// Runs on mixerQueue only. Sums one aligned block from every chain that has
    /// produced enough frames. An idle chain contributes silence; it must not
    /// stall the recording clock or cause another chain's ring to overflow.
    private func mixTick() {
        let chunkFrames = recordingChunkFrames
        let channels = recordingChannelCount
        guard chunkFrames > 0, channels > 0, recordingMixScratch.count == chunkFrames * channels else { return }
        recordingRingsLock.lock()
        let inputs = Array(recordingInputs.values)
        recordingRingsLock.unlock()
        guard !inputs.isEmpty else { return }
        recordingMixScratch.withUnsafeMutableBufferPointer { mix in
            mix.baseAddress?.update(repeating: 0, count: mix.count)
            for input in inputs where input.ring.fillFrames >= UInt32(chunkFrames) {
                recordingChainScratch.withUnsafeMutableBufferPointer { chainBuffer in
                    _ = input.ring.readInterleaved(chainBuffer.baseAddress!, frames: UInt32(chunkFrames))
                    for i in 0..<mix.count { mix[i] += chainBuffer[i] }
                }
            }
        }
        recordingMixScratch.withUnsafeBufferPointer { mix in
            combinedRecordingSession?.append(mix.baseAddress!, frames: chunkFrames, channels: channels, sampleRate: recordingSampleRate)
        }
    }
}

extension GraphSnapshot {
    func validateForIndependentProcessing() throws {
        guard Set(nodes.map(\.id)).count == nodes.count else {
            throw PrototypeError(message: "A chain contains duplicate node IDs")
        }
        if graphMode == .split {
            guard leftStartNodeID != nil, leftEndNodeID != nil,
                  rightStartNodeID != nil, rightEndNodeID != nil else {
                throw PrototypeError(message: "A split chain is missing its endpoints")
            }
        }
    }
}

extension AudioEngine {
    /// Load a graph without mounting a canvas. Each engine owns its own mutable
    /// node state and plugin host, even if presets reuse the same node UUIDs.
    func applyIndependentGraph(_ graph: GraphSnapshot) {
        // This is an authoritative headless load. A prior visual-load request
        // must not overwrite this graph during the next workspace capture.
        pendingGraphLoadRequest = nil
        func ordered(_ lane: GraphLane?) -> [BeginnerNode] {
            graph.nodes.filter { lane == nil || $0.lane == lane }.sorted {
                if $0.position.x == $1.position.x { return $0.position.y < $1.position.y }
                return $0.position.x < $1.position.x
            }
        }
        func connections(_ lane: GraphLane?, start: UUID, end: UUID) -> [BeginnerConnection] {
            let nodes = ordered(lane)
            if graph.wiringMode == .manual {
                let ids = Set(nodes.map(\.id) + [start, end])
                return graph.connections.filter { ids.contains($0.fromNodeId) && ids.contains($0.toNodeId) }
            }
            let path = [start] + nodes.map(\.id) + [end]
            return zip(path, path.dropFirst()).map { from, to in
                let gain = graph.autoGainOverrides.first { $0.fromNodeId == from && $0.toNodeId == to }?.gain ?? 1
                return BeginnerConnection(fromNodeId: from, toNodeId: to, gain: gain)
            }
        }
        if graph.graphMode == .split {
            guard let ls = graph.leftStartNodeID, let le = graph.leftEndNodeID,
                  let rs = graph.rightStartNodeID, let re = graph.rightEndNodeID else { return }
            updateEffectGraphSplit(leftNodes: ordered(.left), leftConnections: connections(.left, start: ls, end: le),
                leftStartID: ls, leftEndID: le, rightNodes: ordered(.right),
                rightConnections: connections(.right, start: rs, end: re), rightStartID: rs, rightEndID: re,
                autoConnectEnd: graph.autoConnectEnd)
        } else if graph.wiringMode == .automatic && graph.autoGainOverrides.isEmpty {
            updateEffectChain(ordered(nil))
        } else {
            updateEffectGraph(nodes: graph.nodes, connections: connections(nil, start: graph.startNodeID, end: graph.endNodeID),
                startID: graph.startNodeID, endID: graph.endNodeID,
                autoConnectEnd: graph.wiringMode == .manual && graph.autoConnectEnd)
        }
        updateGraphSnapshot(graph)
        publishProcessingState()
    }
}
