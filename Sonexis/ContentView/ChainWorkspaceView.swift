import AppKit
import Combine
import SwiftUI
struct ChainWorkspaceView: View {
    let openEditor: () -> Void
    @StateObject private var workspace = ChainWorkspace()
    @StateObject private var menuBar = MenuBarController()
    @State private var activeScreen: AppScreen = .home

    var body: some View {
        Group {
            if let processor = workspace.selectedProcessor {
                let chainID = workspace.selectedID
                ContentView(openEditor: openEditor, audioEngine: processor, presetManager: workspace.presets,
                    chainWorkspace: workspace, tutorial: workspace.tutorial, activeScreen: $activeScreen,
                    currentPresetID: Binding(get: { workspace.chains.first(where: { $0.id == chainID })?.presetID },
                        set: { workspace.setPreset($0, chainID: chainID) }))
                    .id(chainID)
            } else {
                Text("The chain workspace could not be loaded.").frame(minWidth: 1100, minHeight: 700)
            }
        }
        .onAppear {
            menuBar.onOpen = {
                workspace.tutorial.didOpenMenuBar(hasPresets: !workspace.presets.presets.isEmpty)
            }
            menuBar.install {
                AnyView(ChainMenuBarPanel(workspace: workspace, openChain: { id in
                    guard workspace.canOpenChainFromMenu(id) else { return }
                    workspace.select(id)
                    workspace.tutorial.didOpenEditor(chainID: id)
                    activeScreen = .beginner
                    menuBar.close()
                    openEditor()
                }, chooseRecordingURL: { menuBar.promptForRecordingURL() },
                   close: { menuBar.close() }))
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in workspace.refreshAndSave() }
        .onReceive(NotificationCenter.default.publisher(for: .sonexisEditorWillHide)) { _ in
            workspace.refreshAndSave(); workspace.store.flush()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in workspace.shutdown() }
        .sonexisDialog("Chains",
            message: workspace.issue ?? "",
            tone: .error,
            isPresented: Binding(get: { workspace.issue != nil }, set: { if !$0 { workspace.issue = nil } }),
            actions: [
                SonexisDialogAction("Show Workspace Files") { NSWorkspace.shared.open(workspace.store.directory) },
                SonexisDialogAction("OK", role: .primary) { workspace.issue = nil }
            ]
        )
        .onReceive(workspace.runtime.$state) { state in
            if case .failed(let message) = state { workspace.issue = message }
        }
    }
}
