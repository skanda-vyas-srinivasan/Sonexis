import Foundation

final class ProcessTapDSPEngine {
    private let app: ProcessTapDSPApp

    init(configuration: DSPConfiguration = .productBaseline) {
        self.app = ProcessTapDSPApp(configuration: configuration)
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
