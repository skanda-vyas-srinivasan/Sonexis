import Foundation
@testable import Sonexis

// This fake-runtime harness verifies Sonexis lifecycle generation and handoff
// semantics. It does not establish compatibility or internal thread safety for
// arbitrary third-party Audio Units.

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

final class LockedCounter {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    func read() -> Int { lock.lock(); defer { lock.unlock() }; return value }
}

final class FakeRenderState: PluginRenderState {
    let format: PluginRenderFormat
    let name: String
    let renders = LockedCounter()
    let parameterChanges = LockedCounter()
    var stateReadDelay: TimeInterval = 0
    var onDeinit: (() -> Void)?

    init(name: String, format: PluginRenderFormat) {
        self.name = name
        self.format = format
    }

    deinit { onDeinit?() }

    func process(
        buffer: inout [[Float]],
        frameLength: Int,
        sampleRate: Double,
        channelCount: Int
    ) -> Bool {
        renders.increment()
        return sampleRate == format.sampleRate
            && channelCount == format.channelCount
            && frameLength <= format.maximumFrameCount
    }

    func setParameter() { parameterChanges.increment() }

    func readState() -> Data {
        Thread.sleep(forTimeInterval: stateReadDelay)
        return Data(name.utf8)
    }
}

enum FakePreparationError: LocalizedError {
    case rejected
    var errorDescription: String? { "controlled preparation failure" }
}

final class ControlledPreparer {
    struct Request {
        let format: PluginRenderFormat
        let stateData: Data?
        let completion: (Result<PluginRenderState, Error>) -> Void
    }

    private let lock = NSLock()
    private var requests: [Request] = []
    private let available = DispatchSemaphore(value: 0)
    let calls = LockedCounter()

    func prepare(
        format: PluginRenderFormat,
        stateData: Data?,
        completion: @escaping (Result<PluginRenderState, Error>) -> Void
    ) {
        calls.increment()
        lock.lock()
        requests.append(Request(format: format, stateData: stateData, completion: completion))
        lock.unlock()
        available.signal()
    }

    func next(_ label: String) -> Request {
        expect(available.wait(timeout: .now() + 3) == .success, "\(label) preparation request timed out")
        lock.lock()
        defer { lock.unlock() }
        return requests.removeFirst()
    }
}

let preparer = ControlledPreparer()
let lifecycle = PluginRenderLifecycle(
    label: "Sonexis.Tests.PluginLifecycle",
    initialStateData: nil,
    preparer: preparer.prepare
)
let publication = DispatchSemaphore(value: 0)
lifecycle.onPublication = { publication.signal() }
let format1 = PluginRenderFormat(sampleRate: 48_000, channelCount: 2, maximumFrameCount: 128)
let format2 = PluginRenderFormat(sampleRate: 96_000, channelCount: 2, maximumFrameCount: 128)

lifecycle.prepare(format: format1)
let initialRequest = preparer.next("initial")
let state1 = FakeRenderState(name: "initial", format: format1)
initialRequest.completion(.success(state1))
expect(publication.wait(timeout: .now() + 3) == .success, "initial render state was not published")
expect(lifecycle.renderState === state1, "initial render state is not active")

var audio = [[Float]](repeating: [Float](repeating: 0.25, count: 64), count: 2)
let oldSnapshot = lifecycle.renderState!
let renderFinished = DispatchSemaphore(value: 0)
DispatchQueue(label: "Sonexis.Tests.RenderLoop").async {
    var localAudio = audio
    for _ in 0..<2_000 {
        expect(oldSnapshot.process(
            buffer: &localAudio,
            frameLength: 64,
            sampleRate: format1.sampleRate,
            channelCount: format1.channelCount
        ), "old state failed during replacement preparation")
    }
    renderFinished.signal()
}
lifecycle.prepare(format: format2)
let replacementRequest = preparer.next("replacement")
expect(renderFinished.wait(timeout: .now() + 3) == .success, "replacement preparation blocked rendering")
expect(lifecycle.renderState === state1, "unprepared replacement displaced the active state")

let state2 = FakeRenderState(name: "replacement", format: format2)
let inFlightBlockState = lifecycle.renderState
replacementRequest.completion(.success(state2))
expect(publication.wait(timeout: .now() + 3) == .success, "replacement was not published")
expect(lifecycle.renderState === state2, "replacement did not become visible at the next snapshot boundary")
expect(inFlightBlockState === state1, "publication changed a state already captured for an in-flight block")
expect(oldSnapshot === state1, "old snapshot lost its retained render state")

lifecycle.prepare(format: format1)
let failedRequest = preparer.next("failure")
failedRequest.completion(.failure(FakePreparationError.rejected))
expect(publication.wait(timeout: .now() + 3) == .success, "failure was not published")
expect(lifecycle.renderState === state2, "preparation failure evicted the previous valid state")
expect(lifecycle.failureDescription == "controlled preparation failure", "failure status was not retained")

// A failed request can be retried even while the prior generation remains active.
lifecycle.prepare(format: format1)
let retryRequest = preparer.next("retry")
expect(retryRequest.format == format1, "failed preparation suppressed a retry for the requested format")
retryRequest.completion(.failure(FakePreparationError.rejected))
expect(publication.wait(timeout: .now() + 3) == .success, "retry failure was not published")
expect(lifecycle.renderState === state2, "failed retry evicted the previous valid state")

let loadedState = Data("loaded-state".utf8)
lifecycle.loadState(loadedState)
let stateLoadRequest = preparer.next("state load")
expect(stateLoadRequest.stateData == loadedState, "state load did not prepare a replacement generation")
expect(lifecycle.renderState === state2, "state loading mutated the active generation")
let stateLoadRenderFinished = DispatchSemaphore(value: 0)
DispatchQueue(label: "Sonexis.Tests.StateLoadRendering").async {
    var localAudio = audio
    for _ in 0..<2_000 {
        expect(state2.process(
            buffer: &localAudio,
            frameLength: 64,
            sampleRate: format2.sampleRate,
            channelCount: format2.channelCount
        ), "active state failed while persisted state was loading")
    }
    stateLoadRenderFinished.signal()
}
expect(stateLoadRenderFinished.wait(timeout: .now() + 3) == .success,
       "state loading blocked the active render generation")
let activeFormat = stateLoadRequest.format
let state3 = FakeRenderState(name: "loaded", format: activeFormat)
stateLoadRequest.completion(.success(state3))
expect(publication.wait(timeout: .now() + 3) == .success, "state-loaded generation was not published")
expect(lifecycle.renderState === state3, "state-loaded generation did not become active")

let callsBeforeRendering = preparer.calls.read()
let concurrentWork = DispatchGroup()
concurrentWork.enter()
DispatchQueue(label: "Sonexis.Tests.ParameterChanges").async {
    for _ in 0..<2_000 { state3.setParameter() }
    concurrentWork.leave()
}
concurrentWork.enter()
DispatchQueue(label: "Sonexis.Tests.ActiveRendering").async {
    var localAudio = audio
    for _ in 0..<2_000 {
        expect(state3.process(
            buffer: &localAudio,
            frameLength: 64,
            sampleRate: activeFormat.sampleRate,
            channelCount: activeFormat.channelCount
        ), "active state render failed")
    }
    concurrentWork.leave()
}
expect(concurrentWork.wait(timeout: .now() + 3) == .success, "parameter/render concurrency timed out")
expect(state3.parameterChanges.read() == 2_000, "parameter changes were lost")
expect(preparer.calls.read() == callsBeforeRendering, "live rendering invoked lifecycle preparation")

state3.stateReadDelay = 0.3
let slowReadStarted = DispatchSemaphore(value: 0)
let slowReadFinished = DispatchSemaphore(value: 0)
DispatchQueue(label: "Sonexis.Tests.SlowStateRead").async {
    slowReadStarted.signal()
    _ = state3.readState()
    slowReadFinished.signal()
}
expect(slowReadStarted.wait(timeout: .now() + 1) == .success, "slow state read did not start")
let start = DispatchTime.now().uptimeNanoseconds
for _ in 0..<500 {
    expect(state3.process(
        buffer: &audio,
        frameLength: 64,
        sampleRate: activeFormat.sampleRate,
        channelCount: activeFormat.channelCount
    ), "render failed during slow state operation")
}
let renderSeconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
expect(renderSeconds < 0.2, "slow UI/state work blocked the render loop")
expect(slowReadFinished.wait(timeout: .now() + 1) == .success, "slow state read did not finish")

let removalHandoff = PluginRenderStateHandoff()
let retirementQueue = DispatchQueue(label: "Sonexis.Tests.PluginRetirement")
let retirementKey = DispatchSpecificKey<Bool>()
retirementQueue.setSpecific(key: retirementKey, value: true)
var removable: FakeRenderState? = FakeRenderState(name: "removable", format: format1)
weak var weakRemovable = removable
let deinitialized = DispatchSemaphore(value: 0)
removable?.onDeinit = {
    expect(DispatchQueue.getSpecific(key: retirementKey) == true,
           "removed render state was destroyed on the processing worker")
    deinitialized.signal()
}
var deferredRemovable: DeferredReleasePluginRenderState? = DeferredReleasePluginRenderState(
    state: removable!,
    retirementQueue: retirementQueue
)
removalHandoff.publish(deferredRemovable)
var retainedBlockState: PluginRenderState? = removalHandoff.snapshot()
removalHandoff.publish(nil)
removable = nil
expect(weakRemovable != nil, "removal invalidated an in-flight render state")
expect(retainedBlockState!.process(
    buffer: &audio,
    frameLength: 64,
    sampleRate: format1.sampleRate,
    channelCount: format1.channelCount
), "retained state could not finish after removal")
deferredRemovable = nil
retainedBlockState = nil
expect(deinitialized.wait(timeout: .now() + 1) == .success, "removed state outlived its final snapshot")

print("PASS: fake-runtime lifecycle generations, prepared-state handoff, failure retention, removal lifetime, and render isolation")
