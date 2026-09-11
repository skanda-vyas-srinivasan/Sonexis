import Foundation
import Combine
@testable import Sonexis

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func until(_ message: String, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    expect(condition(), message)
}
final class Probe {
    let lock = NSLock()
    private var events: [String] = []
    func add(_ event: String) {
        expect(!Thread.isMainThread, "HAL lifecycle work ran on main")
        lock.lock(); events.append(event); lock.unlock()
    }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return events }
}
final class Pipeline: AudioChainPipeline {
    let probe: Probe
    let startGate: DispatchSemaphore?
    let stopGate: DispatchSemaphore?
    let startReturned: (() -> Void)?
    init(_ probe: Probe, start: DispatchSemaphore? = nil, stop: DispatchSemaphore? = nil,
         startReturned: (() -> Void)? = nil) {
        self.probe = probe; startGate = start; stopGate = stop; self.startReturned = startReturned
    }
    func start() throws {
        probe.add("start-enter")
        startGate?.wait()
        probe.add("start-return")
        startReturned?()
    }
    func stopImmediately(reason: String) {
        probe.add("stop-enter")
        stopGate?.wait()
        probe.add("stop-return")
    }
}
let base = ChainWorkspace.emptyChain(target: nil)

// A blocked start must allow main-queue work, timeout, cancel and eventual retry.
let probe = Probe(), gate = DispatchSemaphore(value: 0)
var first = true
let runtime = MultiChainAudioEngine(makePipeline: { _, _ in
    let blocked = first; first = false
    return Pipeline(probe, start: blocked ? gate : nil)
}, operationTimeout: 0.08)
var publishedOnMain = true
let observation = runtime.$state.sink { _ in publishedOnMain = publishedOnMain && Thread.isMainThread }
try runtime.configure([base])
try runtime.start()
expect(runtime.state == .starting && !runtime.processors[base.id]!.isRunning, "Startup must not claim running early")
until("Start probe did not enter") { probe.values.contains("start-enter") }
var heartbeat = false
DispatchQueue.main.async { heartbeat = true }
until("Main queue froze") { heartbeat }
until("Pending start did not time out") { if case .failed = runtime.state { return true }; return false }
expect(runtime.isTransitioning, "Timeout must retain ownership until HAL returns")
try runtime.start()
expect(probe.values == ["start-enter"], "Retry created overlapping taps while start was blocked")
gate.signal()
until("Cancelled start failed to clean up") { !runtime.isTransitioning }
expect(probe.values == ["start-enter", "start-return", "stop-enter", "stop-return"], "Cancelled start must stop before releasing ownership")
expect(!runtime.processors[base.id]!.isRunning, "Late completion re-enabled audio")
try runtime.start()
until("Retry failed after cleanup") { runtime.state == .running }
runtime.stop()
until("Stop did not complete") { !runtime.isTransitioning }
expect(runtime.state == .stopped && publishedOnMain, "UI state updates must remain on main")
print("PASS: blocked start leaves main responsive, timeout, serialized cleanup, late-completion suppression, safe retry")

// Cancellation may arrive after start returns but BEFORE its main completion.
let raceProbe = Probe()
var raceRuntime: MultiChainAudioEngine!
raceRuntime = MultiChainAudioEngine(makePipeline: { _, _ in
    Pipeline(raceProbe, startReturned: { DispatchQueue.main.async { raceRuntime.stop() } })
})
try raceRuntime.configure([base]); try raceRuntime.start()
until("Completion race did not settle") { !raceRuntime.isTransitioning }
expect(raceRuntime.state == .stopped && raceProbe.values.last == "stop-return", "Late cancellation left a live pipeline")
raceRuntime = nil
print("PASS: cancellation between worker return and main completion cannot leak live taps")

let stopProbe = Probe(), stopGate = DispatchSemaphore(value: 0)
let stopping = MultiChainAudioEngine(makePipeline: { _, _ in Pipeline(stopProbe, stop: stopGate) }, operationTimeout: 0.08)
try stopping.configure([base]); try stopping.start()
until("Stop fixture failed to start") { stopping.state == .running }
stopping.stop()
until("Stop fixture did not block") { stopProbe.values.contains("stop-enter") }
until("Blocked stop did not time out") { if case .failed = stopping.state { return true }; return false }
try stopping.start()
expect(stopProbe.values.filter { $0 == "start-enter" }.count == 1, "Started while teardown still owned old IO")
stopGate.signal()
until("Blocked stop did not finish") { !stopping.isTransitioning }
print("PASS: blocked stop does not freeze main or allow concurrent restart")

// Resolving per-app HAL identities is also off main, including refreshes.
let resolverGate = DispatchSemaphore(value: 0), resolverProbe = Probe()
let app = AudioCaptureTarget(bundleID: "test.lifecycle", name: "Lifecycle", bundlePath: "/Lifecycle.app")
let resolving = MultiChainAudioEngine(resolve: { _ in
    resolverProbe.add("resolve"); resolverGate.wait(); return []
}, makePipeline: { _, _ in Pipeline(resolverProbe) }, operationTimeout: 0.08)
try resolving.configure([base, ChainWorkspace.emptyChain(target: app)])
expect(resolverProbe.values.isEmpty, "Document setup queried HAL synchronously")
try resolving.start()
until("Resolver did not enter") { resolverProbe.values.contains("resolve") }
resolving.stop(); resolverGate.signal()
until("Resolver cancellation did not finish") { !resolving.isTransitioning }
expect(!resolverProbe.values.contains("start-enter"), "Cancelled resolution started capture")
print("PASS: HAL resolution off main; cancelled resolution cannot create taps")

let releaseProbe = Probe(), releaseGate = DispatchSemaphore(value: 0)
var releasing: MultiChainAudioEngine? = MultiChainAudioEngine(makePipeline: { _, _ in Pipeline(releaseProbe, start: releaseGate) })
try releasing!.configure([base])
weak var retainedProcessor = releasing!.processors[base.id]
try releasing!.start()
until("Release fixture did not enter start") { releaseProbe.values.contains("start-enter") }
releasing = nil
expect(retainedProcessor != nil, "Pending IO lost its processor before teardown")
releaseGate.signal()
until("Release did not finish cleanup") { releaseProbe.values.last == "stop-return" && retainedProcessor == nil }
print("PASS: releasing a runtime during blocked startup retains its processor until serial teardown finishes")

// The editor/tutorial adapter must treat repeated start requests as idempotent,
// while an explicit Stop still cancels the pending request.
let editorProbe = Probe(), editorGate = DispatchSemaphore(value: 0)
let editorDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Sonexis-lifecycle-editor-\(UUID())")
defer { try? FileManager.default.removeItem(at: editorDirectory) }
let editor = ChainWorkspace(directory: editorDirectory, runtime: MultiChainAudioEngine(
    makePipeline: { _, _ in Pipeline(editorProbe, start: editorGate) }))
editor.selectedProcessor!.start()
until("Editor start did not enter") { editorProbe.values.contains("start-enter") }
editor.selectedProcessor!.start()
editorGate.signal()
until("Repeated editor start cancelled pending audio") { editor.runtime.state == .running }
expect(editorProbe.values.filter { $0 == "start-enter" }.count == 1, "Repeated editor start duplicated capture")
editor.selectedProcessor!.stop()
until("Editor stop did not complete") { !editor.runtime.isTransitioning }
expect(editor.runtime.state == .stopped, "Editor stop did not reach runtime")
print("PASS: repeated editor/tutorial start requests are idempotent; explicit stop still works")
