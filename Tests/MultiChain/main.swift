import Foundation
import CoreAudio
@testable import Sonexis
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
func expectFailure(_ message: String, _ action: () throws -> Void) {
    do { try action(); fatalError(message) } catch {}
}
let appA = AudioCaptureTarget(bundleID: "test.a", name: "A", bundlePath: "/A.app")
let appB = AudioCaptureTarget(bundleID: "test.b", name: "B", bundlePath: "/B.app")
var node = BeginnerNode(type: .delay)
node.parameters.delayTime = 0.01
node.parameters.delayFeedback = 0.4
node.parameters.delayMix = 1
let graph = GraphSnapshot(graphMode: .single, wiringMode: .automatic, nodes: [node],
                          connections: [], startNodeID: UUID(), endNodeID: UUID())
let empty = GraphSnapshot(graphMode: .single, wiringMode: .automatic, nodes: [],
                          connections: [], startNodeID: UUID(), endNodeID: UUID())
let base = AudioChainDefinition(id: UUID(), target: nil, graph: empty, effectsEnabled: true)
let a = AudioChainDefinition(id: UUID(), target: appA, graph: graph, effectsEnabled: true)
let b = AudioChainDefinition(id: UUID(), target: appB, graph: graph, effectsEnabled: true)
let definitions = [base, a, b]
var processes: [String: Set<AudioObjectID>] = [appA.id: [10, 11], appB.id: [20]]
func resolve(_ target: AudioCaptureTarget) -> Set<AudioObjectID> { processes[target.id] ?? [] }
let plan = try AudioChainRoutingPlan(chains: definitions, resolve: resolve)
expect(plan.selections[base.id] == .allAudio(excluding: [10,11,20]), "Default excludes every override process")
expect(plan.selections[a.id] == .only([10,11]), "A captures only A")
expect(plan.selections[b.id] == .only([20]), "B captures only B")
expect(plan.selections[base.id]!.safeProcessIDs(ownProcessID: 99) == [10,11,20,99], "Default must also exclude Sonexis")
expect(ProcessTapSelection.only([99,10]).safeProcessIDs(ownProcessID:99) == [10], "Overrides exclude Sonexis")
expectFailure("Reject duplicate app assignment") {
    _ = try AudioChainRoutingPlan(chains: [base,a,AudioChainDefinition(id:UUID(), target:appA, graph:graph,effectsEnabled:true)], resolve:resolve)
}
expectFailure("Reject overlapping process ownership") {
    _ = try AudioChainRoutingPlan(chains:definitions, resolve: { _ in [10] })
}
expectFailure("Require default chain") { _ = try AudioChainRoutingPlan(chains:[a,b],resolve:resolve) }
let data = try JSONEncoder().encode(definitions)
let decoded = try JSONDecoder().decode([AudioChainDefinition].self,from:data)
expect(decoded.map(\.id) == definitions.map(\.id), "Chain identity survives persistence encoding")

final class FakePipeline: AudioChainPipeline {
    let number: Int
    let event: (String) -> Void
    let shouldFail: Bool
    init(_ number:Int, shouldFail:Bool, event:@escaping (String)->Void) {
        self.number=number; self.shouldFail=shouldFail; self.event=event
    }
    func start() throws {
        event("start\(number)")
        if shouldFail { throw PrototypeError(message:"fixture failure") }
    }
    func stopImmediately(reason:String) { event("stop\(number)") }
}
var events:[String]=[]
var counter=0
var failNext=false
let runtime = MultiChainAudioEngine(resolve:resolve, makePipeline: { _,_ in
    counter += 1
    let fail=failNext; failNext=false
    return FakePipeline(counter,shouldFail:fail) { events.append($0) }
})
try runtime.configure(definitions)
let processorA = runtime.processors[a.id]!, processorB = runtime.processors[b.id]!
expect(processorA !== processorB, "Processors are distinct even for the same preset node IDs")
expect(processorA.pluginHost !== processorB.pluginHost, "Plugin hosts must be independent")
for p in runtime.processors.values {
    p.processTapInputTrimDB=0; p.processTapOutputMakeupDB=0; p.processTapOutputCeilingEnabled=false
    p.publishProcessingState()
}
func render(_ p:AudioEngine, input:[Float]) -> [Float] {
    var output=[Float](repeating:0,count:input.count)
    input.withUnsafeBufferPointer { i in output.withUnsafeMutableBufferPointer { o in
        p.processSystemAudio(input:i.baseAddress!,output:o.baseAddress!,frameCount:input.count/2,channelCount:2,sampleRate:48000)
    }}
    return output
}
let processorBase = runtime.processors[base.id]!
processorBase.processTapInputTrimDB = 0
processorBase.processTapOutputMakeupDB = 0
processorBase.processTapOutputCeilingEnabled = false
var impulse=[Float](repeating:0,count:256*2); impulse[0]=0.5; impulse[1]=0.5
_ = render(processorA,input:impulse)
var tail:[Float]=[]
for _ in 0..<8 {
    tail += render(processorA,input:[Float](repeating:0,count:512))
    expect(render(processorB,input:[Float](repeating:0,count:512)).allSatisfy { abs($0)<1e-8 }, "A's delay state must never enter B")
}
expect(tail.contains { abs($0)>0.001 }, "State isolation test must exercise a real delay tail")
runtime.setEffectsEnabled(false,chainID:a.id)
expect(!processorA.processingEnabled && processorB.processingEnabled, "Individual bypass is independent")
runtime.setGlobalBypass(true)
expect(!processorA.processingEnabled && !processorB.processingEnabled, "Global bypass applies to all")
runtime.setGlobalBypass(false)
expect(!processorA.processingEnabled && processorB.processingEnabled, "Global bypass preserves individual choices")
try runtime.start()
expect(runtime.state == .running, "All chains start")
events=[]
try runtime.refreshProcesses()
expect(events.isEmpty, "Unchanged process list must not restart playback")
processes[appA.id]=[30]
try runtime.refreshProcesses()
expect(events.prefix(3).allSatisfy { $0.hasPrefix("stop") }, "Stop ALL old routes before starting ANY replacements")
expect(events.suffix(3).allSatisfy { $0.hasPrefix("start") }, "Start new partitions after old ones stop")
expect(runtime.processors[a.id] === processorA, "Relaunch preserves the processor and effect state")
processes[appA.id]=[]
let absent = try AudioChainRoutingPlan(chains:definitions,resolve:resolve)
expect(absent.selections[a.id] == .only([]), "Absent app stays an empty override")
expect(absent.selections[base.id] == .allAudio(excluding:[20]), "Default retains other-app exclusion")
failNext=true
expectFailure("Surface pipeline startup failure") { try runtime.configure([base,a]) }
expect(runtime.definitions.count == 3 && runtime.state == .running, "Failed configuration restores previous routing")
runtime.stop()
expect(runtime.state == .stopped, "Stop all chains")
var invalid=empty; invalid.nodes=[node,node]
expectFailure("Reject duplicate nodes before DSP dictionaries") { try runtime.updateGraph(invalid,chainID:a.id) }
print("PASS: independent delay/plugin state, app overrides, disjoint routing, bypass, relaunch, atomic stop/start, rollback, graph validation, persistence encoding")
