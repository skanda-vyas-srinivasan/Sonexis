import AppKit
import Foundation

extension AudioEngine {

    // MARK: - Engine Control

    func start() {
        if let onPowerStart { onPowerStart(); return }
        startProcessTapBackend()
    }

    func stop() {
        if let onPowerStop { onPowerStop(); return }
        stopProcessTapBackend()
    }

    func reconfigureAudio() {
        refreshOutputDevices()
    }

    // MARK: - Notifications

    func setupNotifications() {
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func handleAppWillTerminate(notification: Notification) {
        refreshPresetPluginState()
        stopProcessTapBackendImmediately(reason: "Sonexis terminate")
    }
}
