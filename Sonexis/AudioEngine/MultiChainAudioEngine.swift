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
        }
        var nextProcessors: [UUID: AudioEngine] = [:]
        for chain in next {
            let processor = existing[chain.id] ?? AudioEngine(observeSystemLifecycle: false)
            processor.applyIndependentGraph(chain.graph)
            processor.processTapInputTrimDB = chain.inputTrimDB
            processor.processTapOutputMakeupDB = chain.outputMakeupDB
            processor.processTapOutputCeilingEnabled = chain.outputCeilingEnabled
            processor.processingEnabled = chain.effectsEnabled && !globallyBypassed
            processor.publishProcessingState()
            nextProcessors[chain.id] = processor
        }
        processors = nextProcessors
        definitions = next
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
        for index in definitions.indices where !suspended.contains(definitions[index].id) {
            guard let processor = processors[definitions[index].id] else { continue }
            if let graph = processor.pendingGraphLoadRequest?.snapshot ?? processor.currentGraphSnapshot {
                definitions[index].graph = graph
            }
            if !globallyBypassed { definitions[index].effectsEnabled = processor.processingEnabled }
            definitions[index].inputTrimDB = processor.processTapInputTrimDB
            definitions[index].outputMakeupDB = processor.processTapOutputMakeupDB
            definitions[index].outputCeilingEnabled = processor.processTapOutputCeilingEnabled
        }
    }

    func setPresetID(_ presetID: UUID?, chainID: UUID) {
        guard let index = definitions.firstIndex(where: { $0.id == chainID }) else { return }
        definitions[index].presetID = presetID
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
        for processor in processors.values { processor.stopRecording() }
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
        let session = session
        lifecycleQueue.async { session.stop() }
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
