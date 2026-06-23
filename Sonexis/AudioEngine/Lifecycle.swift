import AppKit
import Foundation

extension AudioEngine {

    // MARK: - Engine Control

    func start() {
        startProcessTapBackend()
    }

    func stop() {
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
        stopProcessTapBackendImmediately(reason: "Sonexis terminate")
    }
}
