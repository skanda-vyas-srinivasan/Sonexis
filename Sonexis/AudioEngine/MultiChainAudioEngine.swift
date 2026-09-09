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

/// Main-thread owner of independent DSP/plugin state and non-overlapping taps.
/// UI selection is deliberately absent: changing the visible canvas must never
/// change which chains run. The chain-list UI will own this runtime next.
final class MultiChainAudioEngine: ObservableObject {
    enum State: Equatable { case stopped, running, failed(String) }
    typealias Resolver = (AudioCaptureTarget) throws -> Set<AudioObjectID>
    typealias PipelineFactory = (AudioEngine, ProcessTapSelection) -> AudioChainPipeline

    @Published private(set) var definitions: [AudioChainDefinition] = []
    @Published private(set) var state: State = .stopped
    private(set) var processors: [UUID: AudioEngine] = [:]
    private var pipelines: [UUID: AudioChainPipeline] = [:]
    private var activePlan: AudioChainRoutingPlan?
    private var processTimer: Timer?
    @Published private(set) var globallyBypassed = false
    private let resolve: Resolver
    private let makePipeline: PipelineFactory

    init(resolve: @escaping Resolver = { Set(try $0.processObjectIDs(excluding: kAudioObjectUnknown)) },
         makePipeline: @escaping PipelineFactory = {
             ProcessTapDSPEngine(audioProcessor: $0, fixedSelection: $1)
         }) {
        self.resolve = resolve
        self.makePipeline = makePipeline
    }

    func configure(_ next: [AudioChainDefinition]) throws {
        precondition(Thread.isMainThread)
        let nextPlan = try AudioChainRoutingPlan(chains: next, resolve: resolve)
        for chain in next { try chain.graph.validateForIndependentProcessing() }
        let previous = definitions
        let previousProcessors = processors
        let wasRunning = state == .running
        stopPipelines()
        do {
            var nextProcessors: [UUID: AudioEngine] = [:]
            for chain in next {
                let processor = previousProcessors[chain.id] ?? AudioEngine(observeSystemLifecycle: false)
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
            if wasRunning { try startPipelines(plan: nextPlan) }
            else { state = .stopped }
        } catch {
            stopPipelines()
            definitions = previous
            processors = previousProcessors
            for chain in previous {
                processors[chain.id]?.applyIndependentGraph(chain.graph)
                processors[chain.id]?.processTapInputTrimDB = chain.inputTrimDB
                processors[chain.id]?.processTapOutputMakeupDB = chain.outputMakeupDB
                processors[chain.id]?.processTapOutputCeilingEnabled = chain.outputCeilingEnabled
                processors[chain.id]?.processingEnabled = chain.effectsEnabled && !globallyBypassed
                processors[chain.id]?.publishProcessingState()
            }
            if wasRunning {
                do { try startPipelines(plan: AudioChainRoutingPlan(chains: previous, resolve: resolve)) }
                catch { state = .failed("Could not restore chains: \(error)") }
            }
            throw error
        }
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
        guard state != .running else { return }
        do {
            try startPipelines(plan: AudioChainRoutingPlan(chains: definitions, resolve: resolve))
            processTimer?.invalidate()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, self.state == .running else { return }
                do { try self.refreshProcesses() }
                catch { self.stopPipelines(); self.state = .failed("App routing update failed: \(error)") }
            }
            RunLoop.main.add(timer, forMode: .common)
            processTimer = timer
        } catch {
            stopPipelines()
            state = .failed(String(describing: error))
            throw error
        }
    }

    func stop() {
        precondition(Thread.isMainThread)
        processTimer?.invalidate()
        processTimer = nil
        stopPipelines()
        for processor in processors.values { processor.stopRecording() }
        state = .stopped
    }

    func refreshProcesses() throws {
        precondition(Thread.isMainThread)
        guard state == .running else { return }
        let next = try AudioChainRoutingPlan(chains: definitions, resolve: resolve)
        guard next != activePlan else { return }
        // Stop every old partition before starting any new one. Otherwise the
        // default could still contain a process that an override has just added.
        stopPipelines()
        do { try startPipelines(plan: next) }
        catch { state = .failed(String(describing: error)); throw error }
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

    private func startPipelines(plan: AudioChainRoutingPlan) throws {
        do {
            for chain in definitions {
                guard let processor = processors[chain.id], let selection = plan.selections[chain.id] else {
                    throw PrototypeError(message: "Chain processor or route is missing")
                }
                let pipeline = makePipeline(processor, selection)
                pipelines[chain.id] = pipeline
                try pipeline.start()
                processor.isRunning = true
            }
            activePlan = plan
            state = .running
        } catch {
            stopPipelines()
            throw error
        }
    }

    private func stopPipelines() {
        for pipeline in pipelines.values { pipeline.stopImmediately(reason: "multi-chain routing transition") }
        pipelines.removeAll()
        for processor in processors.values {
            processor.isRunning = false
            processor.resetOutputMeter()
        }
        activePlan = nil
    }

    deinit {
        processTimer?.invalidate()
        for pipeline in pipelines.values { pipeline.stopImmediately(reason: "multi-chain runtime released") }
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
