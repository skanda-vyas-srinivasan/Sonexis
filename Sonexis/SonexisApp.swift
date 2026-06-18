import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var processTapSmokeEngine: ProcessTapDSPEngine?

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

        let engine = ProcessTapDSPEngine(configuration: .productBaseline)
        processTapSmokeEngine = engine

        do {
            try engine.start()
            print("Sonexis Process Tap smoke test started.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                engine.stop(reason: "Sonexis Process Tap smoke test") {
                    DispatchQueue.main.async {
                        print("Sonexis Process Tap smoke test stopped.")
                        self?.processTapSmokeEngine = nil
                        NSApp.terminate(nil)
                    }
                }
            }
        } catch {
            print("Sonexis Process Tap smoke test failed: \(error)")
            processTapSmokeEngine = nil
            NSApp.terminate(nil)
        }
    }
}

@main
struct SonexisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
