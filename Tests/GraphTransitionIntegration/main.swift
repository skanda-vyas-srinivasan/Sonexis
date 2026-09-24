@testable import Sonexis

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func publish() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
let engine = AudioEngine() // Offline DSP only: never starts capture or playback.
engine.processTapInputTrimDB = 0
engine.processTapOutputMakeupDB = 0
engine.processTapOutputCeilingEnabled = true
engine.updateEffectChain([])
publish()
func render(_ frames: Int = 256) -> [Float] {
    let input = [Float](repeating: 0.1, count: frames * 2)
    var output = [Float](repeating: 0, count: input.count)
    input.withUnsafeBufferPointer { source in
        output.withUnsafeMutableBufferPointer { destination in
            engine.processSystemAudio(input: source.baseAddress!, output: destination.baseAddress!,
                frameCount: frames, channelCount: 2, sampleRate: 48_000)
        }
    }
    return output
}
_ = render()
var captured: [Float] = []
engine.recordingSink = { samples, frames, channels, _ in
    captured.append(contentsOf: UnsafeBufferPointer(start: samples, count: frames * channels))
}
var expected: [Float] = []
func checkAudio() {
    let output = render()
    expect(output.allSatisfy { $0.isFinite && $0 > 0.09 && $0 < 0.11 }, "Graph edit muted or boosted neutral audio")
    expected += output
    publish()
}
let a = BeginnerNode(type: .simpleEQ, isEnabled: false)
let b = BeginnerNode(type: .delay, isEnabled: false)
engine.updateEffectChain([a]); publish(); checkAudio()
engine.updateEffectChain([a, b]); publish(); checkAudio()
engine.updateEffectChain([b, a]); publish(); checkAudio()
engine.updateEffectChain([a]); publish(); checkAudio()
let start = UUID(), end = UUID()
let wiring = [BeginnerConnection(fromNodeId: start, toNodeId: a.id), BeginnerConnection(fromNodeId: a.id, toNodeId: end)]
engine.updateEffectGraph(nodes: [a], connections: wiring, startID: start, endID: end)
publish(); checkAudio()
engine.updateEffectGraph(nodes: [a], connections: [BeginnerConnection(fromNodeId: start, toNodeId: end)], startID: start, endID: end)
publish(); checkAudio()
engine.processingEnabled = false; publish(); checkAudio()
engine.processingEnabled = true; publish(); checkAudio()
let rightStart = UUID(), rightEnd = UUID()
engine.updateEffectGraphSplit(leftNodes: [], leftConnections: [BeginnerConnection(fromNodeId: start, toNodeId: end)], leftStartID: start, leftEndID: end,
    rightNodes: [], rightConnections: [BeginnerConnection(fromNodeId: rightStart, toNodeId: rightEnd)], rightStartID: rightStart, rightEndID: rightEnd)
publish(); checkAudio()
engine.updateEffectChain([]); publish(); checkAudio()
engine.recordingSink = nil
expect(captured == expected, "Final-output recording tap differs from transition output")

// An unwired empty lane passes through, but adding a disconnected effect must
// not silently bypass manual routing. Explicit dry wires retain their gain.
let dry = [[Float]](repeating: [Float](repeating: 0.1, count: 256), count: 2)
func graphOutput(nodes: [BeginnerNode], connections: [BeginnerConnection]) -> [[Float]] {
    engine.graphProcessor.processGraph(inputBuffer: dry, channelCount: 2, sampleRate: 48_000,
        plan: GraphRoutingPlan(nodes: nodes, connections: connections, startID: start, endID: end,
            autoConnectEnd: false), snapshot: engine.currentProcessingSnapshot()).0
}
expect(graphOutput(nodes: [], connections: []) == dry, "Empty manual canvas muted audio")
expect(graphOutput(nodes: [a], connections: []).flatMap { $0 }.allSatisfy { $0 == 0 }, "Disconnected effect bypassed manual routing")
let attenuated = graphOutput(nodes: [], connections: [BeginnerConnection(fromNodeId: start, toNodeId: end, gain: 0.5)])
expect(attenuated.flatMap { $0 }.allSatisfy { abs($0 - 0.05) < 0.000001 }, "Explicit empty-canvas wire gain ignored")
engine.updateEffectGraphSplit(leftNodes: [], leftConnections: [], leftStartID: start, leftEndID: end,
    rightNodes: [], rightConnections: [], rightStartID: rightStart, rightEndID: rightEnd)
publish()
expect(render().allSatisfy { abs($0 - 0.1) < 0.000001 }, "Empty split lanes muted audio")

// Graph publication runs on the main thread while the processing worker owns
// and mutates per-node DSP state. Repeated removal must never let graph editing
// touch the worker's dictionaries.
let concurrencyNodes = (0..<8).map { index -> BeginnerNode in
    switch index % 4 {
    case 0: return BeginnerNode(type: .tremolo)
    case 1: return BeginnerNode(type: .delay)
    case 2: return BeginnerNode(type: .compressor)
    default: return BeginnerNode(type: .bitcrusher)
    }
}
let renderFinished = DispatchSemaphore(value: 0)
DispatchQueue(label: "GraphTransitionIntegration.processing").async {
    for _ in 0..<300 {
        let output = render(64)
        expect(output.allSatisfy(\.isFinite), "Concurrent graph edit produced non-finite audio")
    }
    renderFinished.signal()
}
for iteration in 0..<300 {
    let retainedCount = iteration % (concurrencyNodes.count + 1)
    engine.updateEffectChain(Array(concurrencyNodes.prefix(retainedCount)))
    RunLoop.main.run(until: Date().addingTimeInterval(0.001))
}
expect(renderFinished.wait(timeout: .now() + 10) == .success, "Concurrent render did not finish")
engine.updateEffectChain([])
publish()
_ = render(64)
expect(engine.graphProcessor.tremoloPhaseByNode.isEmpty, "Retired node state was not reclaimed at a block boundary")

// Legacy/imported VST3 metadata remains representable, but the runtime must not
// manufacture a ready-looking no-op processor for an unsupported format.
let unsupportedHost = PluginHost()
let unsupportedNode = BeginnerNode(
    type: .plugin,
    plugin: PluginReference(format: .vst3, identifier: "test.vst3", name: "Unsupported", vendor: "Test")
)
unsupportedHost.sync(nodes: [unsupportedNode])
expect(unsupportedHost.processingRenderStates().isEmpty, "Unsupported VST3 created a runtime processor")
expect(unsupportedHost.statusText(nodeId: unsupportedNode.id) == "VST3 unsupported", "Unsupported VST3 status was hidden")
let audioUnitNode = BeginnerNode(
    type: .plugin,
    plugin: PluginReference(format: .au, identifier: "test.au", name: "Audio Unit", vendor: "Test")
)
unsupportedHost.sync(nodes: [audioUnitNode])
var changedFormatNode = audioUnitNode
changedFormatNode.plugin = PluginReference(format: .vst3, identifier: "test.vst3", name: "Unsupported", vendor: "Test")
unsupportedHost.sync(nodes: [changedFormatNode])
expect(unsupportedHost.processingRenderStates().isEmpty, "Changing a node to unsupported VST3 retained an Audio Unit render state")

// Manual/automatic switches must advance a shared stateful effect only once.
let tremolo = BeginnerNode(type: .tremolo)
engine.updateEffectChain([tremolo]); publish(); _ = render()
let before = engine.graphProcessor.tremoloPhaseByNode[tremolo.id]!
engine.updateEffectGraph(nodes: [tremolo], connections: [
    BeginnerConnection(fromNodeId: start, toNodeId: tremolo.id),
    BeginnerConnection(fromNodeId: tremolo.id, toNodeId: end)], startID: start, endID: end)
publish(); _ = render()
let increment = tremolo.parameters.tremoloRate * 2 * Double.pi / 48_000 * 256
let after = engine.graphProcessor.tremoloPhaseByNode[tremolo.id]!
expect(abs(after - before - increment) < 0.000001, "Mode switch advanced shared tremolo twice")
engine.updateEffectChain([tremolo]); publish(); _ = render()
expect(abs(engine.graphProcessor.tremoloPhaseByNode[tremolo.id]! - after - increment) < 0.000001, "Reverse switch advanced shared tremolo twice")
print("PASS: real engine add/remove/reorder/rewire, bypass, split/manual/automatic, exact final-output tap, single stateful render per block")
