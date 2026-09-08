import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var processTapSmokeAudioEngine: AudioEngine?
    let editorWindowController = EditorWindowController()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Handled here even when another Sonexis window (such as a plugin
        // editor) is visible. Never create another engine on a Dock click.
        return !editorWindowController.reopen()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        editorWindowController.isQuitting = true
        return .terminateNow
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use the flat artwork directly for the running Dock icon.
        if let dockIcon = NSImage(named: "DockMark") {
            NSApp.applicationIconImage = dockIcon
        }

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
        Window("Sonexis", id: "editor") {
            if ProcessInfo.processInfo.environment["SONEXIS_PROCESS_TAP_SMOKE"] == "1" {
                EmptyView()
            } else {
                ContentView(openEditor: {
                    NSApp.activate(ignoringOtherApps: true)
                    appDelegate.editorWindowController.reopen()
                })
                    .background(EditorWindowReader { window in
                        appDelegate.editorWindowController.attach(to: window)
                    })
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
