import Foundation

final class ProcessTapDSPEngine {
    private let app: ProcessTapDSPApp

    init(
        configuration: DSPConfiguration = .productBaseline,
        audioProcessor: ProcessTapAudioProcessor? = nil,
        captureTarget: AudioCaptureTarget? = nil,
        fixedSelection: ProcessTapSelection? = nil
    ) {
        self.app = ProcessTapDSPApp(
            configuration: configuration,
            audioProcessor: audioProcessor,
            captureTarget: captureTarget,
            fixedSelection: fixedSelection
        )
    }

    func setCaptureTarget(_ target: AudioCaptureTarget?) throws {
        try app.setCaptureTarget(target)
    }

    func start() throws {
        try app.start()
    }

    func stop(reason: String = "shutdown", completion: @escaping () -> Void = {}) {
        app.stop(reason: reason, completion: completion)
    }

    func stopImmediately(reason: String = "immediate shutdown") {
        app.stopImmediately(reason: reason)
    }
}
