import AppKit
import Foundation

struct PluginRenderFormat: Equatable {
    let sampleRate: Double
    let channelCount: Int
    let maximumFrameCount: Int
}

/// Immutable-reference render capability captured in a ProcessingSnapshot.
/// Its internal DSP state is used only by the processing worker.
protocol PluginRenderState: AnyObject {
    var format: PluginRenderFormat { get }

    @discardableResult
    func process(
        buffer: inout [[Float]],
        frameLength: Int,
        sampleRate: Double,
        channelCount: Int
    ) -> Bool
}

/// Keeps potentially expensive third-party destruction off the processing
/// worker. The final wrapper release may occur after a render block, but the
/// wrapped Audio Unit remains alive until a lifecycle queue releases it.
final class DeferredReleasePluginRenderState: PluginRenderState {
    let format: PluginRenderFormat
    let wrappedState: PluginRenderState
    private let retirementQueue: DispatchQueue

    init(state: PluginRenderState, retirementQueue: DispatchQueue) {
        self.format = state.format
        self.wrappedState = state
        self.retirementQueue = retirementQueue
    }

    func process(
        buffer: inout [[Float]],
        frameLength: Int,
        sampleRate: Double,
        channelCount: Int
    ) -> Bool {
        wrappedState.process(
            buffer: &buffer,
            frameLength: frameLength,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    deinit {
        let state = wrappedState
        retirementQueue.async {
            withExtendedLifetime(state) {}
        }
    }
}

/// Narrow publication seam between lifecycle preparation and graph snapshots.
/// The lock is used only while publishing or building a snapshot. Rendering uses
/// the retained state reference directly and never enters this object.
final class PluginRenderStateHandoff {
    private let lock = NSLock()
    private var state: PluginRenderState?

    func publish(_ state: PluginRenderState?) {
        lock.lock()
        self.state = state
        lock.unlock()
    }

    func snapshot() -> PluginRenderState? {
        lock.lock()
        defer { lock.unlock() }
        return state
    }
}

/// Serial lifecycle coordinator with an injectable preparer. Preparation may be
/// asynchronous, but only the newest successful generation is published. A
/// failure never evicts the previous valid render state.
final class PluginRenderLifecycle {
    typealias Preparer = (
        PluginRenderFormat,
        Data?,
        @escaping (Result<PluginRenderState, Error>) -> Void
    ) -> Void

    var onPublication: (() -> Void)?

    private let queue: DispatchQueue
    private let handoff = PluginRenderStateHandoff()
    private let statusLock = NSLock()
    private let preparer: Preparer
    private var requestedFormat: PluginRenderFormat?
    private var requestedStateData: Data?
    private var generation = 0
    private var preparationFailure: String?

    init(label: String, initialStateData: Data?, preparer: @escaping Preparer) {
        self.queue = DispatchQueue(label: label, qos: .userInitiated)
        self.requestedStateData = initialStateData
        self.preparer = preparer
    }

    var renderState: PluginRenderState? { handoff.snapshot() }
    var failureDescription: String? {
        statusLock.lock()
        defer { statusLock.unlock() }
        return preparationFailure
    }

    func prepare(format: PluginRenderFormat) {
        queue.async { [weak self] in
            guard let self else { return }
            if requestedFormat == format, handoff.snapshot()?.format == format { return }
            requestedFormat = format
            startPreparation(format: format, stateData: requestedStateData)
        }
    }

    func loadState(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            requestedStateData = data
            if let requestedFormat {
                startPreparation(format: requestedFormat, stateData: data)
            }
        }
    }

    private func startPreparation(format: PluginRenderFormat, stateData: Data?) {
        generation &+= 1
        let requestedGeneration = generation
        preparer(format, stateData) { [weak self] result in
            guard let self else { return }
            queue.async {
                guard requestedGeneration == self.generation else { return }
                switch result {
                case .success(let state):
                    self.handoff.publish(state)
                    self.setFailure(nil)
                case .failure(let error):
                    self.setFailure(error.localizedDescription)
                }
                self.onPublication?()
            }
        }
    }

    private func setFailure(_ message: String?) {
        statusLock.lock()
        preparationFailure = message
        statusLock.unlock()
    }
}

protocol PluginInstance: AnyObject {
    var reference: PluginReference { get }
    var isReady: Bool { get }
    var failureDescription: String? { get }
    var displayName: String { get }
    var vendorName: String { get }
    var renderState: PluginRenderState? { get }

    func prepare(format: PluginRenderFormat)
    func editorView() -> NSView?
    func parameters() -> [PluginParameter]
    func setParameter(id: String, value: Double)
    func stateData() -> Data?
    func loadState(_ data: Data)
}
