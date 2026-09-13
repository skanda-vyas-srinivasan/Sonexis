import AppKit
import Combine
import SwiftUI
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
