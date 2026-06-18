import Foundation

enum ProcessTapBackendFlag {
    static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["SONEXIS_USE_PROCESS_TAP"] == "1" {
            return true
        }

        return UserDefaults.standard.bool(forKey: "SonexisUseProcessTapEngine")
    }
}

extension AudioEngine {
    func startProcessTapBackend() {
        guard #available(macOS 14.4, *) else {
            errorMessage = "Process Tap system audio requires macOS 14.4 or newer."
            isRunning = false
            return
        }

        let engine = ProcessTapDSPEngine(configuration: .productBaseline)
        processTapEngine = engine

        do {
            try engine.start()
            inputDeviceName = "System Audio"
            outputDeviceName = "Default Output"
            errorMessage = nil
            isRunning = true
            signalFlowToken += 1
            scheduleSnapshotUpdate()
        } catch {
            processTapEngine = nil
            errorMessage = "Failed to start Process Tap engine: \(error)"
            isRunning = false
            scheduleSnapshotUpdate()
        }
    }

    func stopProcessTapBackend(reason: String = "Sonexis stop") {
        guard let engine = processTapEngine else { return }

        processTapEngine = nil
        engine.stop(reason: reason) { [weak self] in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.scheduleSnapshotUpdate()
            }
        }
    }

    func stopProcessTapBackendImmediately(reason: String = "Sonexis terminate") {
        guard let engine = processTapEngine else { return }

        processTapEngine = nil
        engine.stopImmediately(reason: reason)
        isRunning = false
        scheduleSnapshotUpdate()
    }
}
