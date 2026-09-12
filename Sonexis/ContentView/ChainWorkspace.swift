import AppKit
import Combine
import SwiftUI

struct ChainWorkspaceDocument: Codable {
    var version = 1
    var chains: [AudioChainDefinition]
    var selectedID: UUID
    var globalBypass: Bool
}

/// Separate file from the old workspace: migration never overwrites its source.
final class ChainWorkspaceStore {
    let directory: URL
    private let queue = DispatchQueue(label: "Sonexis.ChainWorkspace", qos: .utility)
    private var pending: DispatchWorkItem?
    private var pendingData: Data?
    private var lastData: Data?
    private var blocked = false
    var onError: ((String) -> Void)?
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sonexis")
    }
    private var file: URL { directory.appendingPathComponent("chains.json") }
    private var backup: URL { directory.appendingPathComponent("chains.backup.json") }

    private func decode(_ data: Data) throws -> ChainWorkspaceDocument {
        let document = try JSONDecoder().decode(ChainWorkspaceDocument.self, from: data)
        guard document.version == 1 else { throw PrototypeError(message: "Unsupported chain workspace version") }
        _ = try AudioChainRoutingPlan(chains: document.chains, resolve: { _ in [] })
        for chain in document.chains { try chain.graph.validateForIndependentProcessing() }
        guard document.chains.contains(where: { $0.id == document.selectedID }) else {
            throw PrototypeError(message: "Selected chain is missing")
        }
        return document
    }

    func load() throws -> ChainWorkspaceDocument? {
        guard FileManager.default.fileExists(atPath: file.path) || FileManager.default.fileExists(atPath: backup.path) else { return nil }
        do {
            let data = try Data(contentsOf: file)
            let document = try decode(data)
            lastData = data
            return document
        } catch {
            // A future version must never be overwritten with an older backup.
            if let data = try? Data(contentsOf: file),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = object["version"] as? Int, version != 1 {
                blocked = true
                throw error
            }
            do {
                let data = try Data(contentsOf: backup)
                let document = try decode(data)
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.copyItem(at: file, to: directory.appendingPathComponent("chains-recovery-\(UUID().uuidString).json"))
                }
                try data.write(to: file, options: .atomic)
                lastData = data
                return document
            } catch {
                blocked = true
                throw PrototypeError(message: "Chain workspace could not be restored. Original files are preserved; autosave is paused.")
            }
        }
    }

    func schedule(_ document: ChainWorkspaceDocument) {
        guard !blocked else { return }
        let data: Data
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            data = try encoder.encode(document)
        } catch { onError?(String(describing: error)); return }
        pending?.cancel()
        pendingData = data
        let item = DispatchWorkItem { [weak self] in self?.write(data) }
        pending = item
        queue.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func write(_ data: Data) {
        guard data != lastData else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let lastData { try lastData.write(to: backup, options: .atomic) }
            try data.write(to: file, options: .atomic)
            lastData = data
        } catch {
            DispatchQueue.main.async { self.onError?("Could not save chains: \(error)") }
        }
    }

    func flush() {
        pending?.cancel()
        pending = nil
        let data = pendingData
        pendingData = nil
        queue.sync { if let data { write(data) } }
    }

}

final class ChainWorkspace: ObservableObject {
    let runtime: MultiChainAudioEngine
    let presets: PresetManager
    let store: ChainWorkspaceStore
    let tutorial = TutorialController()
    private var tutorialObservation: AnyCancellable?
    private var appTutorialSnapshot: ChainWorkspaceDocument?
    private var appTutorialWasRunning = false
    @Published private(set) var selectedID: UUID
    @Published var issue: String?
    let didRestore: Bool
    private var observation: AnyCancellable?
    private var savingPaused = false
    private var suspendedChains = Set<UUID>()
    private var suspendedDefinitions: [UUID: AudioChainDefinition] = [:]
    var chains: [AudioChainDefinition] { runtime.definitions }
    var selectedProcessor: AudioEngine? { runtime.processors[selectedID] }
    var isRecording: Bool { runtime.isRecording || runtime.isFinalizingRecording }

    init(directory: URL? = nil, runtime: MultiChainAudioEngine = MultiChainAudioEngine()) {
        self.runtime = runtime
        presets = PresetManager(directory: directory)
        store = ChainWorkspaceStore(directory: directory)
        var document: ChainWorkspaceDocument?
        var startupIssue: String?
        do { document = try store.load() } catch { startupIssue = String(describing: error) }
        if document == nil && startupIssue == nil {
            let legacy = WorkspaceStore(directory: directory)
            if let saved = legacy.restore() {
                var chain = AudioChainDefinition(id: UUID(), target: nil, graph: saved.graph,
                    effectsEnabled: saved.effectsEnabled, presetID: saved.presetID)
                chain.inputTrimDB = saved.inputTrimDB
                chain.outputMakeupDB = saved.outputMakeupDB
                chain.outputCeilingEnabled = saved.outputCeilingEnabled
                // Preserve a previous app-only workspace as an override; leave
                // other apps dry instead of unexpectedly applying its effects globally.
                if directory == nil, let target = AudioCaptureTarget.restore() {
                    chain.target = target
                    let defaultChain = Self.emptyChain(target: nil)
                    document = ChainWorkspaceDocument(chains: [defaultChain, chain], selectedID: chain.id, globalBypass: false)
                } else {
                    document = ChainWorkspaceDocument(chains: [chain], selectedID: chain.id, globalBypass: false)
                }
            } else if legacy.recoveryRequired { startupIssue = legacy.issue }
        }
        didRestore = document != nil
        let initial = document ?? {
            let chain = Self.emptyChain(target: nil)
            return ChainWorkspaceDocument(chains: [chain], selectedID: chain.id, globalBypass: false)
        }()
        selectedID = initial.selectedID
        do {
            try runtime.configure(initial.chains)
            runtime.setGlobalBypass(initial.globalBypass)
        } catch { startupIssue = "Could not prepare saved chains: \(error)" }
        issue = startupIssue
        savingPaused = startupIssue != nil
        wireProcessors()
        runtime.onConfigurationRestored = { [weak self] in
            guard let self else { return }
            self.wireProcessors()
            if !self.chains.contains(where: { $0.id == self.selectedID }), let first = self.chains.first {
                self.selectedID = first.id
            }
            self.prepareSelectedCanvas()
            self.capture()
            self.issue = "The audio change failed. Your previous chains have been restored."
        }
        store.onError = { [weak self] in self?.issue = $0 }
        observation = runtime.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        tutorialObservation = tutorial.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        tutorial.onBeginAppTour = { [weak self] in self?.beginAppTutorial() ?? false }
        tutorial.onEndAppTour = { [weak self] in self?.restoreAppTutorial() ?? false }
        prepareSelectedCanvas()
    }

    private func beginAppTutorial() -> Bool {
        guard !runtime.isTransitioning else {
            issue = "Wait for audio to finish starting or stopping before starting the app-chain lesson."
            return false
        }
        guard !isRecording, !savingPaused, suspendedChains.isEmpty else {
            issue = "Finish recording or the current tutorial before starting the app-chain lesson."
            return false
        }
        refreshAndSave()
        store.flush()
        appTutorialSnapshot = ChainWorkspaceDocument(chains: chains, selectedID: selectedID,
                                                     globalBypass: runtime.globallyBypassed)
        appTutorialWasRunning = runtime.state == .running
        return true
    }

    private func restoreAppTutorial() -> Bool {
        guard let original = appTutorialSnapshot else { return true }
        do {
            // Restoring user work must not put the practice document back if
            // restarting audio later fails. Report audio failure separately.
            try runtime.configure(original.chains, rollbackOnAudioFailure: false)
            runtime.setGlobalBypass(original.globalBypass)
            wireProcessors()
            selectedID = original.selectedID
            prepareSelectedCanvas()
            if appTutorialWasRunning { try runtime.start() } else { runtime.stop() }
            appTutorialSnapshot = nil
            capture()
            store.flush()
            return true
        } catch {
            issue = "Could not restore your chains: \(error). Your saved workspace is unchanged. Try finishing the tutorial again."
            return false
        }
    }

    var canAddChain: Bool {
        !runtime.isTransitioning && !isRecording && suspendedChains.isEmpty && (!tutorial.isActive || tutorial.step == .chainsAdd)
    }

    func canSelectChain(_ id: UUID) -> Bool {
        guard suspendedChains.isEmpty else { return false }
        guard tutorial.isActive else { return true }
        return [.chainsOpenEditor, .chainsClose].contains(tutorial.step) && id == tutorial.practiceChainID
    }

    func canRemoveChain(_ id: UUID) -> Bool {
        !runtime.isTransitioning && !isRecording && suspendedChains.isEmpty && (!tutorial.isActive ||
            (tutorial.step == .chainsClose && id == tutorial.practiceChainID))
    }

    func canToggleChain(_ id: UUID) -> Bool {
        !suspendedChains.contains(id) && (!tutorial.isActive ||
            ([.chainsDisable, .chainsEnable].contains(tutorial.step) && id == tutorial.practiceChainID))
    }

    func canLoadPreset(into id: UUID) -> Bool {
        !suspendedChains.contains(id) && (!tutorial.isActive ||
            (tutorial.step == .chainsChoosePreset && id == tutorial.practiceChainID))
    }

    func canOpenChainFromMenu(_ id: UUID) -> Bool {
        !tutorial.isActive || (tutorial.step == .chainsOpenEditor && id == tutorial.practiceChainID)
    }

    static func emptyChain(target: AudioCaptureTarget?) -> AudioChainDefinition {
        AudioChainDefinition(id: UUID(), target: target,
            graph: GraphSnapshot(graphMode: .single, wiringMode: .automatic, nodes: [], connections: [],
                startNodeID: UUID(), endNodeID: UUID(), leftStartNodeID: UUID(), leftEndNodeID: UUID(),
                rightStartNodeID: UUID(), rightEndNodeID: UUID()), effectsEnabled: true)
    }

    func name(for chain: AudioChainDefinition) -> String { chain.target?.name ?? "Default" }

    func select(_ id: UUID) {
        guard canSelectChain(id) else { return }
        guard chains.contains(where: { $0.id == id }), selectedID != id else { return }
        capture()
        selectedID = id
        prepareSelectedCanvas()
        capture()
    }

    func moveAppChain(_ movingID: UUID, toPositionOf destinationID: UUID) {
        guard !tutorial.isActive, suspendedChains.isEmpty else { return }
        runtime.captureDefinitions()
        guard runtime.moveAppChain(movingID, toPositionOf: destinationID) else { return }
        capture()
    }

    func add(_ target: AudioCaptureTarget) {
        guard canAddChain else { return }
        if let existing = chains.first(where: { $0.target?.id == target.id }) { select(existing.id); return }
        capture()
        let chain = Self.emptyChain(target: target)
        let previousSelection = selectedID
        do {
            try runtime.configure(chains + [chain]) { [weak self] succeeded in
                guard let self else { return }
                guard succeeded else {
                    self.selectedID = previousSelection
                    self.prepareSelectedCanvas()
                    self.capture()
                    return
                }
                self.tutorial.didAddPracticeChain(id: chain.id, name: target.name)
            }
            wireProcessors()
            selectedID = chain.id
            prepareSelectedCanvas()
            capture()
        } catch { issue = "Could not add app chain: \(error)" }
    }

    func remove(_ id: UUID) {
        guard canRemoveChain(id) else { return }
        guard !isRecording, let chain = chains.first(where: { $0.id == id }), chain.target != nil else { return }
        capture()
        let previousSelection = selectedID
        do {
            try runtime.configure(chains.filter { $0.id != id }) { [weak self] succeeded in
                guard let self else { return }
                if succeeded { self.tutorial.advanceIf(.chainsClose) }
                else {
                    self.selectedID = previousSelection
                    self.prepareSelectedCanvas()
                    self.capture()
                }
            }
            wireProcessors()
            if selectedID == id { selectedID = chains.first(where: { $0.target == nil })!.id }
            prepareSelectedCanvas()
            capture()
        } catch { issue = "Could not remove app chain: \(error)" }
    }

    func removeAllAppChains() {
        guard suspendedChains.isEmpty, !tutorial.isActive else { return }
        guard !isRecording, chains.contains(where: { $0.target != nil }) else { return }
        capture()
        do {
            try runtime.configure(chains.filter { $0.target == nil })
            wireProcessors()
            selectedID = chains[0].id
            prepareSelectedCanvas()
            capture()
        } catch { issue = "Could not close app chains: \(error)" }
    }

    func loadPreset(_ preset: SavedPreset, chainID: UUID) {
        guard canLoadPreset(into: chainID) else { return }
        capture()
        do {
            try runtime.updateGraph(preset.graph, chainID: chainID)
            runtime.setPresetID(preset.id, chainID: chainID)
            runtime.processors[chainID]?.requestGraphLoad(
                preset.graph, mode: .visualOnly, reason: "menu bar preset")
            capture()
            tutorial.advanceIf(.chainsChoosePreset)
        } catch { issue = "Could not load preset: \(error)" }
    }

    func setPreset(_ id: UUID?, chainID: UUID) {
        runtime.setPresetID(id, chainID: chainID)
        capture()
    }

    func togglePower() {
        guard tutorial.step.allowsPowerControl || tutorial.step == .advancedIntro else { return }
        if runtime.state == .running || runtime.isTransitioning { runtime.stop() }
        else {
            capture()
            do { try runtime.start() } catch { issue = "Could not start chains: \(error)" }
        }
    }

    func toggleGlobalBypass() {
        guard suspendedChains.isEmpty, !tutorial.isActive else { return }
        runtime.captureDefinitions()
        runtime.setGlobalBypass(!runtime.globallyBypassed)
        for processor in runtime.processors.values { processor.globalBypassActive = runtime.globallyBypassed }
        capture()
    }

    func toggleEffects(_ id: UUID) {
        guard canToggleChain(id) else { return }
        guard let chain = chains.first(where: { $0.id == id }) else { return }
        runtime.setEffectsEnabled(!chain.effectsEnabled, chainID: id)
        capture()
        if tutorial.step == .chainsDisable && chain.effectsEnabled { tutorial.advance() }
        else if tutorial.step == .chainsEnable && !chain.effectsEnabled { tutorial.advance() }
    }

    func suspendSaving(for processor: AudioEngine, suspended: Bool) {
        guard let id = runtime.processors.first(where: { $0.value === processor })?.key else { return }
        if suspended {
            if !suspendedChains.contains(id) {
                runtime.captureDefinitions(excluding: suspendedChains)
                suspendedDefinitions[id] = chains.first { $0.id == id }
                suspendedChains.insert(id)
            }
        } else {
            suspendedChains.remove(id)
            suspendedDefinitions.removeValue(forKey: id)
        }
    }

    func capture() {
        guard !savingPaused, !chains.isEmpty else { return }
        runtime.captureDefinitions(excluding: suspendedChains)
        // Preset identity changes immediately in the live definition too. Preserve
        // the complete original definition while a tutorial uses a practice canvas.
        let savedChains = chains.map { suspendedDefinitions[$0.id] ?? $0 }
        store.schedule(appTutorialSnapshot ?? ChainWorkspaceDocument(chains: savedChains, selectedID: selectedID, globalBypass: runtime.globallyBypassed))
    }

    func refreshAndSave() {
        for processor in runtime.processors.values { processor.refreshPresetPluginState() }
        capture()
    }

    func shutdown() {
        refreshAndSave()
        store.flush()
        runtime.stop()
        runtime.stopRecording(waitForWrites: true)
    }

    private func prepareSelectedCanvas() {
        guard let processor = selectedProcessor, let graph = processor.currentGraphSnapshot else { return }
        processor.requestGraphLoad(graph, mode: .visualOnly, reason: "select independent chain")
    }

    private func wireProcessors() {
        for chain in chains {
            guard let processor = runtime.processors[chain.id] else { continue }
            processor.globalBypassActive = runtime.globallyBypassed
            processor.onPowerStart = { [weak self] in
                guard let self, self.runtime.state != .running, !self.runtime.isTransitioning else { return }
                self.togglePower()
            }
            processor.onPowerStop = { [weak self] in self?.runtime.stop() }
            processor.onEffectsToggle = { [weak self] in self?.toggleEffects(chain.id) }
        }
    }
}

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
                }, close: { menuBar.close() }))
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

struct ChainStrip: View {
    @ObservedObject var workspace: ChainWorkspace
    @State private var apps = AudioCaptureTarget.runningApps()
    @State private var removingAll = false
    @State private var hoveredID: UUID?
    @State private var hoveredCloseID: UUID?
    @State private var isAddHovered = false
    @State private var draggingID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragCompensation: CGFloat = 0
    @State private var tabWidths: [UUID: CGFloat] = [:]

    private var canCloseApps: Bool {
        !workspace.isRecording && !workspace.tutorial.isActive && workspace.chains.contains { $0.target != nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(workspace.chains) { chain in
                        tab(chain)
                    }
                }
                .coordinateSpace(name: "chain-tabs")
            }
            Menu {
                ForEach(apps.filter { app in !workspace.chains.contains { $0.target?.id == app.id } }) { app in
                    Button { workspace.add(app) } label: {
                        Label {
                            Text(app.name)
                        } icon: {
                            Image(nsImage: AppIconCache.shared.icon(for: app.bundlePath))
                                .renderingMode(.original)
                        }
                    }
                }
                if apps.allSatisfy({ app in workspace.chains.contains { $0.target?.id == app.id } }) {
                    Text("Open another app to add its chain")
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isAddHovered ? AppColors.neonPink : AppColors.textSecondary)
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(AppColors.neonPink)
                            .frame(width: 14, height: 1)
                            .opacity(isAddHovered ? 1 : 0)
                            .offset(y: -7)
                    }
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .onHover { hovering in
                isAddHovered = hovering && workspace.canAddChain
            }
            .accessibilityLabel("Add app chain")
            .tutorialTarget(.addAppChain)
            .padding(.trailing, 4)
            .disabled(!workspace.canAddChain)
        }
        .foregroundStyle(AppColors.textPrimary)
        .frame(height: 40)
        .tutorialTarget(.chainTabs)
        .background(AppColors.panelPurple)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColors.controlStrokeSoft).frame(height: 1)
                .allowsHitTesting(false)
        }
        .contextMenu {
            Button("Close All App Tabs", role: .destructive) { removingAll = true }
                .disabled(!canCloseApps)
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            let refreshed = AudioCaptureTarget.runningApps()
            if refreshed != apps { apps = refreshed }
        }
        .sonexisDialog("Close all app tabs?",
            message: "Their chains will be removed and all apps will use Default.",
            tone: .warning,
            isPresented: $removingAll,
            actions: [
                SonexisDialogAction("Cancel", role: .cancel) {},
                SonexisDialogAction("Close All App Tabs", role: .destructive) { workspace.removeAllAppChains() }
            ]
        )
    }

    private func tab(_ chain: AudioChainDefinition) -> some View {
        let selected = workspace.selectedID == chain.id
        let enabled = chain.effectsEnabled && !workspace.runtime.globallyBypassed
        let isCloseTutorialTarget = workspace.tutorial.step == .chainsClose &&
            workspace.tutorial.practiceChainID == chain.id
        return HStack(spacing: 0) {
            Button { workspace.select(chain.id) } label: {
                HStack(spacing: 7) {
                    if let target = chain.target {
                        Image(nsImage: AppIconCache.shared.icon(for: target.bundlePath))
                            .renderingMode(.original)
                            .resizable()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "speaker.wave.2")
                    }
                    Text(workspace.name(for: chain)).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 160)
                    if let target = chain.target, !apps.contains(where: { $0.id == target.id }) {
                        Image(systemName: "moon").font(.system(size: 10)).foregroundStyle(AppColors.textMuted)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? AppColors.textPrimary : AppColors.textSecondary)
                .padding(.leading, 14).padding(.trailing, chain.target == nil ? 14 : 6)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!workspace.canSelectChain(chain.id))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(enabled ? "Chain enabled" : "Chain disabled")
            if chain.target != nil {
                Button { workspace.remove(chain.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isCloseTutorialTarget ? AppColors.neonCyan :
                            (hoveredCloseID == chain.id ? AppColors.textPrimary : AppColors.textMuted))
                        .frame(width: 18, height: 18)
                        .background {
                            Circle().fill(hoveredCloseID == chain.id ? AppColors.error.opacity(0.78) : .clear)
                        }
                        .frame(width: 24, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .disabled(!workspace.canRemoveChain(chain.id))
                .accessibilityLabel("Close \(workspace.name(for: chain)) chain")
                .onHover { hovering in
                    hoveredCloseID = hovering ? chain.id : (hoveredCloseID == chain.id ? nil : hoveredCloseID)
                }
            }
        }
        .background {
            if isCloseTutorialTarget {
                Color.clear.tutorialTarget(.practiceChainTab)
            }
        }
        .background(selected ? AppColors.controlPurpleRaised.opacity(0.42) :
            (hoveredID == chain.id ? AppColors.controlPurple.opacity(0.62) : .clear))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppColors.controlStrokeSoft.opacity(0.62))
                .frame(width: 1, height: 22)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            if selected {
                Rectangle().fill(AppColors.neonPink).frame(height: 2).padding(.horizontal, 14)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { tabWidths[chain.id] = proxy.size.width }
                    .onChange(of: proxy.size.width) { tabWidths[chain.id] = $0 }
            }
        }
        .offset(x: draggingID == chain.id ? dragTranslation + dragCompensation : 0)
        .zIndex(draggingID == chain.id ? 10 : 0)
        .simultaneousGesture(tabDragGesture(for: chain))
        .onHover { hoveredID = $0 ? chain.id : (hoveredID == chain.id ? nil : hoveredID) }
        .contextMenu {
            Button(chain.effectsEnabled ? "Disable Chain" : "Enable Chain") { workspace.toggleEffects(chain.id) }
                .disabled(!workspace.canToggleChain(chain.id))
            if chain.target != nil {
                Button("Close Tab", role: .destructive) { workspace.remove(chain.id) }.disabled(!workspace.canRemoveChain(chain.id))
            }
            Divider()
            Button("Close All App Tabs", role: .destructive) { removingAll = true }.disabled(!canCloseApps)
        }
    }

    private func tabDragGesture(for chain: AudioChainDefinition) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("chain-tabs"))
            .onChanged { value in
                guard chain.target != nil, !workspace.tutorial.isActive else { return }
                if draggingID == nil {
                    draggingID = chain.id
                    dragTranslation = 0
                    dragCompensation = 0
                }
                guard draggingID == chain.id,
                      let currentIndex = workspace.chains.firstIndex(where: { $0.id == chain.id }) else { return }

                dragTranslation = value.translation.width
                let pointerX = value.location.x

                if currentIndex > 1 {
                    let previous = workspace.chains[currentIndex - 1]
                    if pointerX < tabMidX(previous.id) {
                        compensateForMove(chain.id, from: currentIndex, to: currentIndex - 1)
                        withAnimation(.easeOut(duration: 0.12)) {
                            workspace.moveAppChain(chain.id, toPositionOf: previous.id)
                        }
                        return
                    }
                }

                if currentIndex + 1 < workspace.chains.count {
                    let next = workspace.chains[currentIndex + 1]
                    if pointerX > tabMidX(next.id) {
                        compensateForMove(chain.id, from: currentIndex, to: currentIndex + 1)
                        withAnimation(.easeOut(duration: 0.12)) {
                            workspace.moveAppChain(chain.id, toPositionOf: next.id)
                        }
                    }
                }
            }
            .onEnded { _ in
                guard draggingID == chain.id else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    draggingID = nil
                    dragTranslation = 0
                    dragCompensation = 0
                }
            }
    }

    private func tabMidX(_ id: UUID) -> CGFloat {
        tabOriginX(id) + (tabWidths[id] ?? 0) / 2
    }

    private func tabOriginX(_ id: UUID) -> CGFloat {
        var origin: CGFloat = 0
        for chain in workspace.chains {
            if chain.id == id { break }
            origin += tabWidths[chain.id] ?? 0
        }
        return origin
    }

    private func compensateForMove(_ id: UUID, from sourceIndex: Int, to destinationIndex: Int) {
        let oldOrigin = tabOriginX(id)
        let destination = workspace.chains[destinationIndex]
        let newOrigin: CGFloat
        if sourceIndex < destinationIndex {
            newOrigin = tabOriginX(destination.id) + (tabWidths[destination.id] ?? 0) - (tabWidths[id] ?? 0)
        } else {
            newOrigin = tabOriginX(destination.id)
        }
        dragCompensation += oldOrigin - newOrigin
    }
}

struct ChainMenuBarPanel: View {
    @ObservedObject var workspace: ChainWorkspace
    let openChain: (UUID) -> Void
    let close: () -> Void
    @State private var apps = AudioCaptureTarget.runningApps()
    @State private var hoveredChainID: UUID?
    @State private var hoveredToggleID: UUID?
    @State private var isAddChainHovered = false
    @State private var isQuitHovered = false
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultThemeID
    private var palette: AppColorPalette { AppTheme.theme(for: themeID).palette }
    private var availableApps: [AudioCaptureTarget] {
        apps.filter { app in !workspace.chains.contains { $0.target?.id == app.id } }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image("SonexisMark")
                    .renderingMode(.template).resizable().scaledToFit().frame(width: 27, height: 27)
                    .foregroundStyle(palette.neonPink)
                Spacer()
                Button { workspace.togglePower() } label: {
                    Group {
                        if workspace.runtime.isTransitioning && workspace.runtime.state != .running {
                            ProgressView().controlSize(.small).frame(width: 24, height: 24)
                        } else {
                            Image(systemName: workspace.runtime.state == .running ? "power.circle.fill" : "power.circle")
                        }
                    }
                    .font(.system(size: 24))
                    .foregroundStyle(workspace.runtime.state == .running ? palette.success : palette.textMuted)
                    .shadow(color: workspace.runtime.state == .running ? palette.success.opacity(0.18) : .clear, radius: 8)
                }
                .accessibilityLabel("Power")
                .accessibilityValue(workspace.runtime.isTransitioning ? "Pending" : (workspace.runtime.state == .running ? "On" : "Off"))
                .disabled(!workspace.tutorial.step.allowsPowerControl)
            }
            .frame(height: 38)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.controlStrokeSoft.opacity(0.62)).frame(height: 1)
            }
            .overlay(alignment: .bottomLeading) {
                Rectangle().fill(palette.neonPink.opacity(0.72)).frame(width: 38, height: 1)
            }
            .padding(.bottom, 6)
            if let instruction = workspace.tutorial.menuInstruction {
                Text(instruction)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(palette.controlPurple.opacity(0.38))
                    .overlay {
                        Rectangle()
                            .stroke(palette.controlStrokeSoft.opacity(0.72), lineWidth: 1)
                    }
            }
            ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(workspace.chains.enumerated()), id: \.element.id) { index, chain in
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Button { openChain(chain.id) } label: {
                                    HStack(spacing: 8) {
                                        MenuBarChainIcon(chain: chain, palette: palette)
                                        Text(workspace.name(for: chain))
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .layoutPriority(1)
                                            .foregroundStyle(hoveredChainID == chain.id ? palette.textPrimary : palette.textSecondary)
                                            .overlay(alignment: .bottomLeading) {
                                                if hoveredChainID == chain.id {
                                                    Rectangle()
                                                        .fill(palette.neonPink)
                                                        .frame(height: 1)
                                                        .offset(y: 2)
                                                }
                                            }
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minWidth: 132, maxWidth: .infinity, alignment: .leading)
                                    .frame(height: 52)
                                    .contentShape(Rectangle())
                                }
                                .disabled(!workspace.canOpenChainFromMenu(chain.id))
                                .onHover { hovering in
                                    hoveredChainID = hovering ? chain.id : (hoveredChainID == chain.id ? nil : hoveredChainID)
                                }
                                .menuBarTutorialHighlight(
                                    workspace.tutorial.step == .chainsOpenEditor &&
                                    workspace.tutorial.practiceChainID == chain.id
                                )
                                ChainPresetMenu(workspace: workspace, presets: workspace.presets, chain: chain)
                                Button { workspace.toggleEffects(chain.id) } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundStyle(hoveredToggleID == chain.id ? palette.neonPink :
                                            (chain.effectsEnabled && !workspace.runtime.globallyBypassed ? palette.neonCyan : palette.textMuted))
                                        .frame(width: 24, height: 24)
                                        .contentShape(Rectangle())
                                }
                                .onHover { hovering in hoveredToggleID = hovering ? chain.id : nil }
                                .opacity(hoveredToggleID == chain.id || !chain.effectsEnabled ? 1 : 0.72)
                                .disabled(!workspace.canToggleChain(chain.id))
                                .menuBarTutorialHighlight(
                                    [.chainsDisable, .chainsEnable].contains(workspace.tutorial.step) &&
                                    workspace.tutorial.practiceChainID == chain.id
                                )
                                .accessibilityLabel(chain.effectsEnabled ? "Disable \(workspace.name(for: chain)) chain" : "Enable \(workspace.name(for: chain)) chain")
                            }
                            .padding(.horizontal, 4)
                            .contextMenu {
                                Button("Remove Chain", role: .destructive) {
                                    workspace.remove(chain.id)
                                }
                                .disabled(!workspace.canRemoveChain(chain.id))
                            }
                            if index < workspace.chains.count - 1 {
                                Rectangle().fill(palette.controlStrokeSoft.opacity(0.48)).frame(height: 1)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .id(chain.id)
                    }
                }
            }
            .frame(height: min(max(CGFloat(workspace.chains.count), 1) * 56, 224))
            .scrollIndicators(.visible)
                .onAppear {
                    if workspace.tutorial.isActive, let id = workspace.tutorial.practiceChainID {
                        scroll.scrollTo(id, anchor: .center)
                    }
                }
            }
            if workspace.chains.count > 4 {
                HStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Scroll for more")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(palette.textMuted)
                .frame(height: 18)
            }
            Rectangle().fill(palette.controlStrokeSoft.opacity(0.72)).frame(height: 1)
            Menu {
                ForEach(availableApps) { app in
                    Button { workspace.add(app) } label: {
                        Label {
                            Text(app.name)
                        } icon: {
                            Image(nsImage: AppIconCache.shared.icon(for: app.bundlePath))
                        }
                    }
                }
                if availableApps.isEmpty {
                    Text("Open another app to add it")
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add App")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(isAddChainHovered ? palette.textPrimary : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 44, alignment: .center)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(palette.neonPink)
                        .frame(width: 58, height: 1)
                        .opacity(isAddChainHovered ? 1 : 0.22)
                        .offset(y: -7)
                }
                .contentShape(Rectangle())
                .background {
                    MenuBarHoverReader { hovering in
                        isAddChainHovered = hovering && workspace.canAddChain
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(!workspace.canAddChain)
            .padding(.vertical, 8)
            Rectangle().fill(palette.controlStrokeSoft.opacity(0.72)).frame(height: 1)
            HStack {
                if workspace.tutorial.isActive && workspace.tutorial.isAppChainTour {
                    Button("Exit tutorial") { workspace.tutorial.skipTutorial(); close() }
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button {
                    close()
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .foregroundStyle(isQuitHovered ? palette.textPrimary : palette.textSecondary)
                        .frame(width: 54, height: 28)
                        .overlay {
                            if isQuitHovered {
                                Rectangle()
                                    .fill(palette.neonPink.opacity(0.85))
                                    .frame(width: 24, height: 1)
                                    .offset(y: 11)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isQuitHovered = hovering
                    }
                }
            }.foregroundStyle(palette.textSecondary)
        }
        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(palette.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 360)
        .background {
            ZStack {
                palette.panelPurple
                MenuBarPanelTexture(palette: palette)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.controlStrokeSoft.opacity(0.78), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(palette.neonPink.opacity(0.78))
                .frame(width: 46, height: 1)
                .padding(.leading, 12)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            AppIconCache.shared.preload(apps.map(\.bundlePath))
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            let refreshed = AudioCaptureTarget.runningApps()
            if refreshed != apps {
                apps = refreshed
                AppIconCache.shared.preload(refreshed.map(\.bundlePath))
            }
        }
    }
}

private struct MenuBarPanelTexture: View {
    let palette: AppColorPalette

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            let spacing: CGFloat = 28
            for x in stride(from: CGFloat(0), through: size.width, by: spacing) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat(0), through: size.height, by: spacing) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(palette.controlStrokeSoft.opacity(0.10)), lineWidth: 0.5)

            var upperWave = Path()
            upperWave.move(to: CGPoint(x: -12, y: size.height * 0.30))
            upperWave.addCurve(
                to: CGPoint(x: size.width + 12, y: size.height * 0.25),
                control1: CGPoint(x: size.width * 0.28, y: size.height * 0.20),
                control2: CGPoint(x: size.width * 0.64, y: size.height * 0.38)
            )
            context.stroke(upperWave, with: .color(palette.neonCyan.opacity(0.075)), lineWidth: 1)

            var lowerWave = Path()
            lowerWave.move(to: CGPoint(x: -12, y: size.height * 0.74))
            lowerWave.addCurve(
                to: CGPoint(x: size.width + 12, y: size.height * 0.79),
                control1: CGPoint(x: size.width * 0.34, y: size.height * 0.86),
                control2: CGPoint(x: size.width * 0.70, y: size.height * 0.66)
            )
            context.stroke(lowerWave, with: .color(palette.neonPink.opacity(0.065)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MenuBarChainIcon: View {
    let chain: AudioChainDefinition
    let palette: AppColorPalette

    var body: some View {
        ZStack {
            Rectangle()
                .fill(palette.controlPurple.opacity(0.42))
                .frame(width: 28, height: 28)
                .overlay {
                    Rectangle().stroke(palette.controlStrokeSoft.opacity(0.52), lineWidth: 1)
            }
            if let target = chain.target {
                Image(nsImage: AppIconCache.shared.icon(for: target.bundlePath))
                    .renderingMode(.original)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.neonCyan)
            }
        }
        .frame(width: 28, height: 28)
    }
}

private final class AppIconCache {
    static let shared = AppIconCache()
    private var icons: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    func preload(_ paths: [String]) {
        for path in Set(paths) where icons[path] == nil {
            icons[path] = NSWorkspace.shared.icon(forFile: path)
        }
    }
}

/// AppKit tracking remains stable when SwiftUI `Menu` temporarily moves focus
/// into its native menu window. It observes hover without intercepting clicks.
private struct MenuBarHoverReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var area: NSTrackingArea?
        private var isHovering = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let next = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(next)
            area = next
        }

        override func mouseEntered(with event: NSEvent) { setHovering(true) }
        override func mouseExited(with event: NSEvent) { setHovering(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func setHovering(_ hovering: Bool) {
            guard hovering != isHovering else { return }
            isHovering = hovering
            onChange?(hovering)
        }
    }
}


private struct ChainPresetMenu: View {
    @ObservedObject var workspace: ChainWorkspace
    @ObservedObject var presets: PresetManager
    let chain: AudioChainDefinition
    @State private var isHovered = false

    private var preset: SavedPreset? { presets.presets.first { $0.id == chain.presetID } }
    private var isTutorialTarget: Bool {
        workspace.tutorial.step == .chainsChoosePreset && workspace.tutorial.practiceChainID == chain.id
    }

    var body: some View {
        Menu {
            ForEach(presets.presets) { preset in
                Button {
                    workspace.loadPreset(preset, chainID: chain.id)
                } label: {
                    if chain.presetID == preset.id {
                        Label(preset.name, systemImage: "checkmark")
                    } else {
                        Text(preset.name)
                    }
                }
            }
            if presets.presets.isEmpty { Text("No saved presets") }
        } label: {
            HStack(spacing: 6) {
                Text(preset?.name ?? "Choose preset")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .overlay(alignment: .bottomLeading) {
                        Rectangle()
                            .fill(AppColors.neonPink)
                            .frame(height: 1)
                            .opacity(isHovered ? 1 : 0)
                            .offset(y: 2)
                    }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppColors.neonPink)
                    .allowsHitTesting(false)
                    .offset(x: isHovered ? 1 : 0)
            }
            .foregroundStyle(preset == nil && !isTutorialTarget ? AppColors.textMuted : AppColors.textPrimary)
            .padding(.horizontal, 4)
            .frame(width: 156, height: 30, alignment: .trailing)
            .background(isHovered ? AppColors.controlPurple.opacity(0.45) : Color.clear)
            .contentShape(Rectangle())
            .background {
                MenuBarHoverReader { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHovered = hovering
                    }
                }
            }
        }
        .buttonStyle(.plain).menuIndicator(.hidden)
        .disabled(!workspace.canLoadPreset(into: chain.id))
        .menuBarTutorialHighlight(isTutorialTarget)
        .accessibilityLabel("Preset for \(workspace.name(for: chain))")
    }
}

private extension View {
    func menuBarTutorialHighlight(_ isHighlighted: Bool) -> some View {
        overlay {
            if isHighlighted {
                Rectangle()
                    .stroke(AppColors.neonCyan.opacity(0.8), lineWidth: 1.25)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
    }
}
