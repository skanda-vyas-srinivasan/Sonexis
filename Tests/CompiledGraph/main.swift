import Foundation
@testable import Sonexis

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
func publish() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
let start = UUID(), end = UUID()
var a = BeginnerNode(type: .simpleEQ)
a.parameters.eqBass = 0.2
let b = BeginnerNode(type: .tremolo)
let c = BeginnerNode(type: .delay)
let nodes = [a, b, c]
func edge(_ from: UUID, _ to: UUID, _ gain: Double = 1) -> BeginnerConnection {
    BeginnerConnection(fromNodeId: from, toNodeId: to, gain: gain)
}
struct Fixture {
    let name: String
    let nodes: [BeginnerNode]
    let edges: [BeginnerConnection]
    var auto = false
}
let fixtures = [
    Fixture(name: "empty", nodes: [], edges: []),
    Fixture(name: "dry gain", nodes: [], edges: [edge(start, end, 0.37)]),
    Fixture(name: "disconnected", nodes: nodes, edges: []),
    Fixture(name: "serial", nodes: nodes, edges: [edge(start, a.id, 0.6), edge(a.id, b.id), edge(b.id, c.id), edge(c.id, end, 0.7)]),
    Fixture(name: "parallel merge", nodes: nodes, edges: [edge(start, a.id), edge(start, b.id), edge(a.id, c.id, 0.3), edge(b.id, c.id, 0.7), edge(c.id, end, 0.8)]),
    Fixture(name: "implicit sinks", nodes: nodes, edges: [edge(start, a.id), edge(start, b.id)], auto: true),
    Fixture(name: "unreachable predecessor", nodes: nodes, edges: [edge(start, a.id), edge(a.id, c.id), edge(b.id, c.id), edge(c.id, end)]),
    Fixture(name: "cycle", nodes: nodes, edges: [edge(start, a.id), edge(a.id, b.id), edge(b.id, a.id), edge(b.id, end)]),
    Fixture(name: "duplicate edge", nodes: [a], edges: [edge(start, a.id, 0.2), edge(start, a.id, 0.3), edge(a.id, end)]),
    Fixture(name: "explicit dry plus effects", nodes: [a], edges: [edge(start, a.id), edge(a.id, end, 0.6), edge(start, end, 0.4)], auto: true)
]
var comparedSamples = 0
for fixture in fixtures {
    for channels in [1, 2] {
        let oldEngine = AudioEngine(), newEngine = AudioEngine()
        oldEngine.updateEffectGraph(nodes: fixture.nodes, connections: fixture.edges, startID: start, endID: end, autoConnectEnd: fixture.auto)
        newEngine.updateEffectGraph(nodes: fixture.nodes, connections: fixture.edges, startID: start, endID: end, autoConnectEnd: fixture.auto)
        publish()
        oldEngine.applyPendingResets(); newEngine.applyPendingResets()
        oldEngine.initializeEffectStates(channelCount: channels)
        newEngine.initializeEffectStates(channelCount: channels)
        let legacy = LegacyGraphRenderer(engine: oldEngine)
        let oldSnapshot = oldEngine.currentProcessingSnapshot()
        let newSnapshot = newEngine.currentProcessingSnapshot()
        for count in [1, 17, 128, 1024, 31, 256] {
            let input = (0..<channels).map { channel in
                (0..<count).map { frame in Float(sin(Double(frame + channel * 13) * 0.13)) * 0.15 }
            }
            let old = legacy.processGraph(inputBuffer: input, channelCount: channels, sampleRate: 48_000,
                nodes: fixture.nodes, connections: fixture.edges, startID: start, endID: end,
                autoConnectEnd: fixture.auto, snapshot: oldSnapshot)
            let new = newEngine.processGraph(inputBuffer: input, channelCount: channels, sampleRate: 48_000,
                plan: newSnapshot.manualRoutingPlan, snapshot: newSnapshot)
            for channel in 0..<channels {
                for frame in 0..<count {
                    expect(new.0[channel][frame].isFinite && abs(new.0[channel][frame] - old.0[channel][frame]) < 0.000001,
                        "Output mismatch: \(fixture.name), \(channels) channels, \(count) frames")
                    comparedSamples += 1
                }
            }
            expect(Set(new.1.keys) == Set(old.1.keys), "Meter node set changed")
            for id in old.1.keys { expect(abs(new.1[id]! - old.1[id]!) < 0.000001, "Meter values changed") }
        }
    }
}

// Cache only routing identity, not parameters, enabled state, layout or wire IDs.
let cache = GraphRoutingPlanCache()
let wiring = [edge(start, a.id), edge(a.id, end)]
let first = cache.plan(nodes: [a], connections: wiring, startID: start, endID: end, autoConnectEnd: false)
var edited = a
edited.position.x += 120
edited.parameters.eqBass = -0.4
edited.isEnabled = false
let sameEdges = wiring.map { edge($0.fromNodeId, $0.toNodeId, $0.gain) }
expect(cache.plan(nodes: [edited], connections: sameEdges, startID: start, endID: end, autoConnectEnd: false) === first,
    "Non-routing edit rebuilt plan")
let gainChanged = cache.plan(nodes: [edited], connections: [edge(start, a.id, 0.5), edge(a.id, end)], startID: start, endID: end, autoConnectEnd: false)
expect(gainChanged !== first, "Gain change reused stale plan")
let autoChanged = cache.plan(nodes: [edited], connections: [edge(start, a.id, 0.5), edge(a.id, end)], startID: start, endID: end, autoConnectEnd: true)
expect(autoChanged !== gainChanged, "Auto-connect flag reused stale plan")
expect(first.steps.first!.inputs.first!.1 == 1, "Old published plan mutated")
let disconnected = cache.plan(nodes: [edited], connections: [], startID: start, endID: end, autoConnectEnd: false)
expect(disconnected.steps.isEmpty && disconnected.endInputs.isEmpty, "Deleted wiring retained stale output routes")

// Verify cache reuse at the real snapshot-publication boundary and independent lanes.
let engine = AudioEngine()
let endpointCases: [(UUID?, UUID?)] = [(nil, nil), (start, nil), (nil, end)]
for endpoints in endpointCases {
    let plan = GraphRoutingPlan(nodes: [], connections: [], startID: endpoints.0, endID: endpoints.1, autoConnectEnd: false)
    let input: [[Float]] = [[0.1, -0.2]]
    expect(engine.processGraph(inputBuffer: input, channelCount: 1, sampleRate: 48_000,
        plan: plan, snapshot: engine.currentProcessingSnapshot()).0 == input, "Missing endpoint lost passthrough")
}
engine.updateEffectGraph(nodes: [a], connections: wiring, startID: start, endID: end)
publish()
let before = engine.currentProcessingSnapshot()
engine.updateEffectGraph(nodes: [edited], connections: sameEdges, startID: start, endID: end)
publish()
let after = engine.currentProcessingSnapshot()
expect(before.manualRoutingPlan === after.manualRoutingPlan, "Parameter publication recompiled graph")
expect(after.nodeParameters[a.id]?.eqBass == -0.4 && after.nodeEnabled[a.id] == false, "Cached plan froze parameters/bypass")
let rightStart = UUID(), rightEnd = UUID()
engine.updateEffectGraphSplit(leftNodes: [a], leftConnections: wiring, leftStartID: start, leftEndID: end,
    rightNodes: [], rightConnections: [], rightStartID: rightStart, rightEndID: rightEnd)
publish()
let split = engine.currentProcessingSnapshot()
expect(split.splitLeftRoutingPlan.steps.count == 1 && split.splitRightRoutingPlan.mode == .empty, "Split plans mixed lanes")
engine.updateEffectGraphSplit(leftNodes: [a], leftConnections: [], leftStartID: start, leftEndID: end,
    rightNodes: [], rightConnections: [], rightStartID: rightStart, rightEndID: rightEnd)
publish()
let splitEdited = engine.currentProcessingSnapshot()
expect(splitEdited.splitRightRoutingPlan === split.splitRightRoutingPlan, "Left edit recompiled unchanged right lane")
expect(splitEdited.splitLeftRoutingPlan !== split.splitLeftRoutingPlan, "Left edit reused stale plan")
print("PASS: \(comparedSamples) legacy/new sample comparisons; topology cases, variable blocks, stateful effects, cache invalidation, fresh parameters, split isolation")

// Same-process Debug comparison, neutral EQ chains, no live audio/device timing.
for count in [4, 16, 48] {
    let benchNodes = (0..<count).map { _ in BeginnerNode(type: .simpleEQ) }
    let ids = [start] + benchNodes.map(\.id) + [end]
    let connections = zip(ids, ids.dropFirst()).map { edge($0, $1) }
    let oldEngine = AudioEngine(), newEngine = AudioEngine()
    let legacy = LegacyGraphRenderer(engine: oldEngine)
    let plan = GraphRoutingPlan(nodes: benchNodes, connections: connections, startID: start, endID: end, autoConnectEnd: false)
    let oldSnapshot = oldEngine.currentProcessingSnapshot(), newSnapshot = newEngine.currentProcessingSnapshot()
    let input = [[Float]](repeating: [Float](repeating: 0.01, count: 128), count: 2)
    func renderOld() { _ = legacy.processGraph(inputBuffer: input, channelCount: 2, sampleRate: 48_000,
        nodes: benchNodes, connections: connections, startID: start, endID: end, autoConnectEnd: false, snapshot: oldSnapshot) }
    func renderNew() { _ = newEngine.processGraph(inputBuffer: input, channelCount: 2, sampleRate: 48_000, plan: plan, snapshot: newSnapshot) }
    for _ in 0..<50 { renderOld(); renderNew() }
    func time(_ run: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<200 { run() }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 200_000
    }
    var oldTimes: [Double] = [], newTimes: [Double] = []
    for _ in 0..<5 { oldTimes.append(time(renderOld)); newTimes.append(time(renderNew)) }
    let old = oldTimes.sorted()[2], new = newTimes.sorted()[2]
    print(String(format: "%d nodes: legacy %.2f us/block, prepared %.2f us/block, %.1f%% less block time (Debug median)", count, old, new, (1 - new / old) * 100))
}
