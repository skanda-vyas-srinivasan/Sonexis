import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var processTapSmokeAudioEngine: AudioEngine?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["SONEXIS_PROCESS_TAP_SMOKE"] == "1" else {
            return
        }

        guard #available(macOS 14.4, *) else {
            print("Sonexis Process Tap smoke test requires macOS 14.4 or newer.")
            NSApp.terminate(nil)
            return
        }

        let audioEngine = AudioEngine()
        processTapSmokeAudioEngine = audioEngine
        audioEngine.startProcessTapBackend()

        guard audioEngine.isRunning else {
            print("Sonexis Process Tap smoke test failed: \(audioEngine.errorMessage ?? "unknown error")")
            processTapSmokeAudioEngine = nil
            NSApp.terminate(nil)
            return
        }

        print("Sonexis Process Tap smoke test started.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            audioEngine.stopProcessTapBackend(reason: "Sonexis Process Tap smoke test") {
                print("Sonexis Process Tap smoke test stopped.")
                self?.processTapSmokeAudioEngine = nil
                NSApp.terminate(nil)
            }
        }
    }
}

@main
struct SonexisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["SONEXIS_PROCESS_TAP_SMOKE"] == "1" {
                EmptyView()
            } else {
                ContentView()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
