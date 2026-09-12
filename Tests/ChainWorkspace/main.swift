import AppKit
import Combine
import Foundation
@testable import Sonexis
func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
func settle(_ workspace: ChainWorkspace) {
    let deadline = Date().addingTimeInterval(3)
    while workspace.runtime.isTransitioning && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    expect(!workspace.runtime.isTransitioning, "Workspace audio transition did not complete")
}
final class FakePipeline: AudioChainPipeline {
    func start() throws {}
    func stopImmediately(reason: String) {}
}
func runtime() -> MultiChainAudioEngine { MultiChainAudioEngine(resolve: { _ in [] }, makePipeline: { _,_ in FakePipeline() }) }
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sonexis-chain-workspace-\(UUID())")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let legacy = WorkspaceStore(directory: directory)
let original = ChainWorkspace.emptyChain(target:nil)
legacy.schedule(WorkspaceSnapshot(graph:original.graph,presetID:nil,inputTrimDB:-4,outputMakeupDB:2,outputCeilingEnabled:true,effectsEnabled:true))
legacy.flush()
let originalBytes = try Data(contentsOf:directory.appendingPathComponent("workspace.json"))
let workspace = ChainWorkspace(directory:directory,runtime:runtime())
expect(workspace.chains.count == 1 && workspace.didRestore, "Migrate the legacy workspace")
let freshDefaults = ChainWorkspace.emptyChain(target: nil)
expect(freshDefaults.inputTrimDB == -15 && freshDefaults.outputMakeupDB == 15 && !freshDefaults.outputCeilingEnabled,
       "New chains use the configured default gain staging")
expect(freshDefaults.effectsEnabled, "New chains start enabled")
let defaultID = workspace.selectedID
let appA=AudioCaptureTarget(bundleID:"test.a",name:"App A",bundlePath:"/A.app")
let appB=AudioCaptureTarget(bundleID:"test.b",name:"App B",bundlePath:"/B.app")
workspace.add(appA)
let aID=workspace.selectedID
let processorA=workspace.selectedProcessor!
var graph=processorA.currentGraphSnapshot!
graph.nodes=[BeginnerNode(type:.bassBoost)]
processorA.applyIndependentGraph(graph)
let presetID=UUID()
workspace.setPreset(presetID,chainID:aID)
workspace.add(appB)
let bID=workspace.selectedID
expect(workspace.chains.count == 3, "Add two independently addressable app chains")
expect(workspace.selectedProcessor!.currentGraphSnapshot!.nodes.isEmpty,"New app starts with its own empty graph")
let processorB = workspace.selectedProcessor!
workspace.moveAppChain(bID, toPositionOf: aID)
expect(workspace.chains.map(\.id) == [defaultID, bID, aID], "Drag-reorder moves app tabs while Default remains first")
expect(workspace.runtime.processors[aID] === processorA && workspace.runtime.processors[bID] === processorB,
       "Reordering tabs preserves the active audio processors")
workspace.moveAppChain(defaultID, toPositionOf: bID)
expect(workspace.chains.map(\.id) == [defaultID, bID, aID], "Default cannot be dragged")
workspace.select(aID)
expect(workspace.selectedProcessor === processorA && workspace.selectedProcessor!.currentGraphSnapshot!.nodes.count == 1,"Switching keeps original processor and graph")
expect(workspace.chains.first(where:{$0.id==aID})?.presetID == presetID,"Preset identity belongs to the chain")
workspace.togglePower(); settle(workspace)
expect(workspace.runtime.state == .running && workspace.runtime.processors.values.allSatisfy(\.isRunning),"Editor power starts every chain")
workspace.moveAppChain(aID, toPositionOf: bID)
expect(workspace.chains.map(\.id) == [defaultID, aID, bID] && workspace.runtime.state == .running,
       "Reordering tabs while running does not restart or stop audio")
workspace.moveAppChain(bID, toPositionOf: aID)
workspace.selectedProcessor!.stop(); settle(workspace)
expect(workspace.runtime.state == .stopped,"Editor power stops every chain")
workspace.toggleEffects(aID)
workspace.toggleGlobalBypass()
workspace.toggleGlobalBypass()
expect(!processorA.processingEnabled && workspace.runtime.processors[bID]!.processingEnabled,"Global bypass restores individual states")
workspace.capture();workspace.store.flush()
let restored=ChainWorkspace(directory:directory,runtime:runtime())
expect(restored.selectedID==aID && restored.chains.count==3,"Restore selected chain and all graphs")
expect(restored.chains.map(\.id) == [defaultID, bID, aID], "Restore the saved tab order")
expect(restored.runtime.state == .stopped,"Relaunch never starts playback")
expect(restored.runtime.processors[aID]!.currentGraphSnapshot!.nodes.count==1,"Persist non-empty app graph")
expect(restored.runtime.processors[defaultID]!.processTapInputTrimDB == -4,"Preserve legacy gain settings")
let untouched = try Data(contentsOf:directory.appendingPathComponent("workspace.json"))
expect(untouched == originalBytes,"Migration leaves original workspace untouched")
workspace.select(bID);workspace.store.flush()
workspace.select(aID);workspace.store.flush()
RunLoop.main.run(until:Date().addingTimeInterval(0.7))
let latest = try ChainWorkspaceStore(directory:directory).load()!
expect(latest.selectedID==aID,"Delayed tasks cannot overwrite a newer flushed selection")
// Menu-bar actions must not replace the editor during a temporary tutorial.
workspace.suspendSaving(for: processorA, suspended: true)
let protectedGraph = processorA.currentGraphSnapshot!
let protectedPresetID = workspace.chains.first(where: { $0.id == aID })!.presetID
var practiceGraph = protectedGraph
practiceGraph.nodes = [BeginnerNode(type: .reverb)]
processorA.applyIndependentGraph(practiceGraph)
workspace.setPreset(UUID(), chainID: aID)
workspace.select(defaultID)
workspace.add(AudioCaptureTarget(bundleID: "test.tutorial", name: "Tutorial", bundlePath: "/Tutorial.app"))
workspace.remove(aID)
workspace.removeAllAppChains()
expect(workspace.selectedID == aID && workspace.chains.count == 3,
       "Tutorial blocks chain switches, additions and removals from other entry points")
workspace.loadPreset(SavedPreset(name: "During tutorial", graph: practiceGraph), chainID: aID)
workspace.capture()
workspace.store.flush()
let duringTutorial = try ChainWorkspaceStore(directory: directory).load()!
expect(duringTutorial.chains.first(where: { $0.id == aID })!.graph.presetComparisonData == protectedGraph.presetComparisonData,
       "Practice edits cannot overwrite the saved chain")
expect(duringTutorial.chains.first(where: { $0.id == aID })!.presetID == protectedPresetID,
       "Practice preset identity cannot overwrite the saved preset association")
processorA.applyIndependentGraph(protectedGraph)
workspace.setPreset(protectedPresetID, chainID: aID)
workspace.suspendSaving(for: processorA, suspended: false)
workspace.select(bID)
expect(workspace.selectedID == bID, "Normal selection resumes after tutorial restore")
workspace.select(aID)
print("PASS: tutorial isolates practice edits and blocks menu-bar chain mutations until restored")

workspace.remove(bID)
expect(workspace.chains.count==2 && workspace.runtime.processors[bID]==nil,"Remove app chain")
workspace.remove(defaultID)
expect(workspace.chains.contains(where:{$0.id==defaultID}),"Default chain cannot be deleted")
workspace.capture();workspace.store.flush()
try Data("broken".utf8).write(to:directory.appendingPathComponent("chains.json"))
let recovered = try ChainWorkspaceStore(directory:directory).load()
expect(recovered != nil,"Recover corrupt primary from backup")
let recoveryFiles = try FileManager.default.contentsOfDirectory(atPath:directory.path)
expect(recoveryFiles.contains(where:{$0.hasPrefix("chains-recovery-")}),"Archive corrupt primary")
print("PASS: workspace migration, two app chains, edit/switch preservation, chain presets, global controls, restart persistence, flush ordering, removal and recovery")

restored.togglePower(); settle(restored)
let defaultProcessor = restored.runtime.processors[defaultID]!
let defaultGraph = defaultProcessor.currentGraphSnapshot
restored.removeAllAppChains(); settle(restored)
expect(restored.chains.count == 1 && restored.selectedID == defaultID, "Close all returns to Default")
expect(restored.runtime.processors[defaultID] === defaultProcessor, "Close all preserves Default processor")
expect(defaultProcessor.currentGraphSnapshot?.nodes.count == defaultGraph?.nodes.count, "Close all preserves Default graph")
expect(restored.runtime.state == .running, "Close all keeps Default playback running")
expect(restored.runtime.processors[aID] == nil && restored.runtime.processors[bID] == nil, "Close all releases app processors")
restored.store.flush()
let cleared = try ChainWorkspaceStore(directory: directory).load()!
expect(cleared.chains.count == 1 && cleared.selectedID == defaultID, "Closed app tabs stay removed after relaunch")
restored.removeAllAppChains(); settle(restored)
expect(restored.chains.count == 1, "Closing all with only Default is harmless")
restored.shutdown()
print("PASS: close all app chains preserves Default, playback, selection, and persistence")

workspace.add(appB)
let menuTargetID = workspace.selectedID
workspace.select(defaultID)
let preservedDefault = workspace.selectedProcessor!
let preservedGraph = preservedDefault.currentGraphSnapshot!.presetComparisonData
let menuPreset = workspace.presets.savePreset(name: "Menu test", graph: graph)!
workspace.togglePower(); settle(workspace)
workspace.loadPreset(menuPreset, chainID: menuTargetID)
expect(workspace.selectedID == defaultID, "Menu preset does not change editor selection")
expect(workspace.selectedProcessor === preservedDefault && preservedDefault.currentGraphSnapshot!.presetComparisonData == preservedGraph, "Menu preset leaves other chain graph and processor untouched")
expect(workspace.chains.first(where: { $0.id == menuTargetID })?.presetID == menuPreset.id, "Menu preset updates target identity")
expect(workspace.runtime.processors[menuTargetID]!.currentGraphSnapshot!.presetComparisonData == graph.presetComparisonData, "Menu preset updates audio without target canvas being open")
expect(workspace.runtime.state == .running, "Menu preset preserves running state")
workspace.store.flush()
let menuSaved = try ChainWorkspaceStore(directory: directory).load()!
expect(menuSaved.chains.first(where: { $0.id == menuTargetID })?.presetID == menuPreset.id, "Menu preset persists")
let libraryBeforeUnlink = try Data(contentsOf: directory.appendingPathComponent("presets.json"))
let unlinkedProcessor = workspace.runtime.processors[menuTargetID]!
let graphBeforeUnlink = unlinkedProcessor.currentGraphSnapshot!.presetComparisonData
workspace.setPreset(nil, chainID: menuTargetID)
expect(workspace.chains.first(where: { $0.id == menuTargetID })?.presetID == nil,
       "Unlink removes the preset association")
expect(workspace.runtime.processors[menuTargetID] === unlinkedProcessor
       && unlinkedProcessor.currentGraphSnapshot!.presetComparisonData == graphBeforeUnlink
       && workspace.runtime.state == .running,
       "Unlink preserves the graph, settings, processor, and playback")
expect(workspace.selectedID == defaultID && preservedDefault.currentGraphSnapshot!.presetComparisonData == preservedGraph,
       "Unlink leaves other chains alone")
workspace.store.flush()
let unlinkedSaved = try ChainWorkspaceStore(directory: directory).load()!
expect(unlinkedSaved.chains.first(where: { $0.id == menuTargetID })?.presetID == nil,
       "The chain stays unnamed after relaunch")
let libraryAfterUnlink = try Data(contentsOf: directory.appendingPathComponent("presets.json"))
expect(libraryAfterUnlink == libraryBeforeUnlink, "Unlink never deletes or modifies the saved preset")
workspace.shutdown()
print("PASS: menu preset targets one chain without selecting it or restarting playback")

// The app lesson uses real workspace actions, but its temporary chain never replaces
// the user's saved workspace. Exercise finish, early exit, and failed operations.
let lessonDirectory = directory.appendingPathComponent("app-tutorial")
var rejectPractice = false
var rejectRestore = false
let lessonRuntime = MultiChainAudioEngine(resolve: { target in
    if (rejectPractice && target.bundleID == "test.practice") || (rejectRestore && target.bundleID == "test.original") {
        throw PrototypeError(message: "test route unavailable")
    }
    return []
}, makePipeline: { _, _ in FakePipeline() })
let lesson = ChainWorkspace(directory: lessonDirectory, runtime: lessonRuntime)
let originalApp = AudioCaptureTarget(bundleID: "test.original", name: "Original App", bundlePath: "/Original.app")
let practiceApp = AudioCaptureTarget(bundleID: "test.practice", name: "Practice App", bundlePath: "/Practice.app")
lesson.add(originalApp)
let originalSelection = lesson.selectedID
let originalProcessor = lesson.selectedProcessor!
var originalLessonGraph = originalProcessor.currentGraphSnapshot!
originalLessonGraph.nodes = [BeginnerNode(type: .clarity)]
originalProcessor.applyIndependentGraph(originalLessonGraph)
originalProcessor.processTapInputTrimDB = -21
originalProcessor.processTapOutputMakeupDB = 6
lesson.setPreset(UUID(), chainID: originalSelection)
lesson.togglePower(); settle(lesson)
lesson.refreshAndSave()
lesson.store.flush()
let originalDocument = try ChainWorkspaceStore(directory: lessonDirectory).load()!
let encoder = JSONEncoder()
encoder.outputFormatting = .sortedKeys
let originalDocumentBytes = try encoder.encode(originalDocument)

lesson.tutorial.startChains()
expect(lesson.tutorial.step == .chainsIntro, "App lesson starts after capturing original work")
lesson.tutorial.nextButtonTapped()
rejectPractice = true
lesson.add(practiceApp); settle(lesson)
expect(lesson.tutorial.step == .chainsAdd && lesson.chains.count == originalDocument.chains.count,
       "Failed add does not advance or create a partial practice chain")
rejectPractice = false
lesson.add(practiceApp); settle(lesson)
let practiceChain = lesson.selectedID
expect(lesson.tutorial.step == .chainsOverrides && lesson.tutorial.practiceChainID == practiceChain,
       "Successful add enters the effect exercise")
let defaultLessonID = lesson.chains.first(where: { $0.target == nil })!.id
lesson.select(defaultLessonID)
lesson.remove(originalSelection)
lesson.removeAllAppChains()
expect(lesson.selectedID == practiceChain && lesson.chains.count == originalDocument.chains.count + 1,
       "Unrelated selection/removal cannot derail the exercise")
var practiceLessonGraph = lesson.selectedProcessor!.currentGraphSnapshot!
practiceLessonGraph.nodes = [BeginnerNode(type: .bassBoost)]
lesson.selectedProcessor!.applyIndependentGraph(practiceLessonGraph)
lesson.tutorial.advanceIf(.chainsOverrides)
expect(lesson.tutorial.step == .chainsMenuBar, "Adding the effect goes directly to the menu bar")
let practicePreset = SavedPreset(name: "Existing preset", graph: practiceLessonGraph)
lesson.select(defaultLessonID)
expect(lesson.selectedID == practiceChain && lesson.tutorial.step == .chainsMenuBar,
       "The menu exercise stays on the practice app without a tab-switch detour")
expect(lesson.selectedProcessor!.currentGraphSnapshot!.nodes.count == 1, "Practice effects remain available")
lesson.tutorial.didOpenMenuBar(hasPresets: true) // Called only after the menu panel opens.
lesson.loadPreset(practicePreset, chainID: originalSelection)
expect(lesson.tutorial.step == .chainsChoosePreset, "Loading the wrong chain is blocked")
lesson.loadPreset(practicePreset, chainID: practiceChain)
expect(lesson.tutorial.step == .chainsDisable, "Actual preset load advances")
lesson.toggleEffects(practiceChain)
expect(lesson.tutorial.step == .chainsEnable && !lesson.selectedProcessor!.processingEnabled,
       "Actual disable advances and changes the practice processor")
lesson.toggleEffects(practiceChain)
expect(lesson.tutorial.step == .chainsOpenEditor && lesson.selectedProcessor!.processingEnabled,
       "Actual enable advances and restores processing")
lesson.tutorial.didOpenEditor(chainID: practiceChain)
expect(lesson.canSelectChain(practiceChain) && lesson.canRemoveChain(practiceChain),
       "The practice tab and close control are enabled for the close exercise")
expect(!lesson.canSelectChain(defaultLessonID) && !lesson.canRemoveChain(originalSelection),
       "The close exercise cannot alter other chains")
lesson.select(practiceChain)
expect(lesson.tutorial.step == .chainsClose, "Clicking the tab title cannot skip closing it")
lesson.remove(practiceChain); settle(lesson)
expect(lesson.tutorial.step == .chainsComplete, "Closing the practice chain completes the exercise")
lesson.refreshAndSave()
lesson.store.flush()
let duringLesson = try ChainWorkspaceStore(directory: lessonDirectory).load()!
let duringLessonBytes = try encoder.encode(duringLesson)
expect(duringLessonBytes == originalDocumentBytes,
       "Practice actions never overwrite original chains, selection, preset identity, or gains")
lesson.tutorial.finishTutorial(); settle(lesson)
expect(!lesson.tutorial.isActive && lesson.selectedID == originalSelection,
       "Finish restores original selection")
expect(lesson.runtime.state == .running && lesson.selectedProcessor!.processTapInputTrimDB == -21
       && lesson.selectedProcessor!.processTapOutputMakeupDB == 6,
       "Finish restores running state and the original gains")
expect(lesson.selectedProcessor!.currentGraphSnapshot!.presetComparisonData == originalLessonGraph.presetComparisonData,
       "Finish restores unsaved graph edits")
lesson.tutorial.startChains()
lesson.tutorial.nextButtonTapped()
lesson.add(practiceApp); settle(lesson)
lesson.tutorial.skipTutorial(); settle(lesson)
expect(!lesson.tutorial.isActive && lesson.selectedID == originalSelection
       && lesson.chains.count == originalDocument.chains.count, "Early exit removes practice work and restores original chains")
lesson.tutorial.startChains()
lesson.tutorial.nextButtonTapped()
lesson.add(practiceApp); settle(lesson)
let continuingPractice = lesson.selectedID
lesson.tutorial.step = .chainsClose
lesson.remove(continuingPractice); settle(lesson)
lesson.tutorial.continueToNextLesson(); settle(lesson)
expect(!lesson.tutorial.isActive && lesson.tutorial.pendingNextLesson == .manualWiring
       && lesson.selectedID == originalSelection && lesson.chains.count == originalDocument.chains.count,
       "Continue restores the app workspace before queuing Manual wiring")
expect(lesson.selectedProcessor!.currentGraphSnapshot!.presetComparisonData == originalLessonGraph.presetComparisonData,
       "The next lesson receives the original graph rather than the practice chain")
let continuedDocument = try ChainWorkspaceStore(directory: lessonDirectory).load()!
let continuedDocumentBytes = try encoder.encode(continuedDocument)
expect(continuedDocumentBytes == originalDocumentBytes,
       "Continuing preserves the saved workspace")
lesson.tutorial.startPendingLesson()
expect(lesson.tutorial.step == .advancedIntro && lesson.tutorial.pendingNextLesson == nil,
       "Manual wiring starts after restoration")
lesson.tutorial.skipTutorial(); settle(lesson)
// A failed asynchronous restart cannot roll the restored user document back
// to the tutorial's temporary app chain.
lesson.tutorial.startChains()
lesson.tutorial.nextButtonTapped()
lesson.add(practiceApp); settle(lesson)
rejectRestore = true
lesson.tutorial.skipTutorial(); settle(lesson)
expect(!lesson.tutorial.isActive && lesson.selectedID == originalSelection
       && lesson.chains.count == originalDocument.chains.count,
       "Audio failure must not undo restoration or retain practice chains")
if case .failed = lesson.runtime.state {} else { fatalError("Restored document must report failed audio restart") }
expect(lesson.selectedProcessor!.currentGraphSnapshot!.presetComparisonData == originalLessonGraph.presetComparisonData,
       "Audio failure must preserve the restored original graph")
let failedRestartDocument = try ChainWorkspaceStore(directory: lessonDirectory).load()!
let failedRestartBytes = try encoder.encode(failedRestartDocument)
expect(failedRestartBytes == originalDocumentBytes,
       "Failed audio restart must preserve the saved user document")
rejectRestore = false
lesson.selectedProcessor!.start(); settle(lesson)
expect(lesson.runtime.state == .running, "User can retry after failed restoration restart")
lesson.shutdown()
print("PASS: real app tutorial actions, failed-operation gating, shared progress, persistence isolation, finish and early-exit restoration")

// Power is available from either surface throughout App Chains. Each exit must
// restore the state from before the lesson, even if the user toggles it inside.
for initiallyRunning in [false, true] {
    for exitKind in ["finish", "skip", "continue"] {
        let powerDirectory = directory.appendingPathComponent("power-\(initiallyRunning)-\(exitKind)")
        let powerLesson = ChainWorkspace(directory: powerDirectory, runtime: runtime())
        if initiallyRunning { powerLesson.togglePower(); settle(powerLesson) }
        powerLesson.refreshAndSave(); powerLesson.store.flush()
        let saved = try Data(contentsOf: powerDirectory.appendingPathComponent("chains.json"))
        powerLesson.tutorial.startChains()
        expect(powerLesson.tutorial.step == .chainsIntro, "Power lesson entered")
        for step: TutorialStep in [.chainsIntro, .chainsAdd, .chainsOverrides, .chainsMenuBar,
                                   .chainsChoosePreset, .chainsDisable, .chainsEnable,
                                   .chainsOpenEditor, .chainsClose, .chainsBackground, .chainsComplete] {
            powerLesson.tutorial.step = step
            expect(step.allowsPowerControl, "Both Power surfaces must be unlocked at \(step)")
            powerLesson.togglePower(); settle(powerLesson)
            expect(powerLesson.runtime.state == (initiallyRunning ? .stopped : .running), "Menu Power must toggle during \(step)")
            expect(powerLesson.tutorial.step == step, "Power must not advance the lesson")
            if initiallyRunning { powerLesson.selectedProcessor!.start() }
            else { powerLesson.selectedProcessor!.stop() }
            settle(powerLesson)
            expect(powerLesson.runtime.state == (initiallyRunning ? .running : .stopped), "Editor Power must restore the toggle during \(step)")
        }
        // Leave power opposite to the entry state so restoration is observable.
        powerLesson.togglePower(); settle(powerLesson)
        switch exitKind {
        case "finish": powerLesson.tutorial.finishTutorial()
        case "skip": powerLesson.tutorial.skipTutorial()
        default: powerLesson.tutorial.continueToNextLesson()
        }
        settle(powerLesson)
        expect(!powerLesson.tutorial.isActive, "Exit completes")
        expect(powerLesson.runtime.state == (initiallyRunning ? .running : .stopped), "\(exitKind) restores entry Power state")
        powerLesson.store.flush()
        let after = try Data(contentsOf: powerDirectory.appendingPathComponent("chains.json"))
        expect(after == saved, "Power tutorial must preserve saved chains")
        powerLesson.shutdown()
    }
}
print("PASS: App Chains Power on both action paths at every step; finish/skip/continue restore stopped and running entry states")

let pendingLesson = ChainWorkspace(directory: directory.appendingPathComponent("pending-lesson"), runtime: runtime())
pendingLesson.togglePower()
pendingLesson.tutorial.startChains()
expect(!pendingLesson.tutorial.isActive, "Do not snapshot an unresolved Power transition")
settle(pendingLesson)
pendingLesson.tutorial.startChains()
expect(pendingLesson.tutorial.step == .chainsIntro, "Lesson can start after Power settles")
pendingLesson.tutorial.skipTutorial(); settle(pendingLesson)
expect(pendingLesson.runtime.state == .running, "Settled entry state is restored")
pendingLesson.shutdown()

final class TutorialStartPipeline: AudioChainPipeline {
    let shouldFail: () -> Bool
    init(shouldFail: @escaping () -> Bool) { self.shouldFail = shouldFail }
    func start() throws { if shouldFail() { throw PrototypeError(message: "test start failure") } }
    func stopImmediately(reason: String) {}
}
var failTutorialStart = true
let retryRuntime = MultiChainAudioEngine(resolve: { _ in [] }, makePipeline: { _, _ in
    TutorialStartPipeline(shouldFail: { failTutorialStart })
})
let retryLesson = ChainWorkspace(directory: directory.appendingPathComponent("retry-lesson"), runtime: retryRuntime)
retryLesson.tutorial.startChains()
retryLesson.togglePower(); settle(retryLesson)
if case .failed = retryRuntime.state {} else { fatalError("Start failure must be reported") }
expect(retryLesson.tutorial.step == .chainsIntro && retryLesson.tutorial.step.allowsPowerControl,
       "Failed startup must leave Power available without advancing")
failTutorialStart = false
retryLesson.selectedProcessor!.start(); settle(retryLesson)
expect(retryRuntime.state == .running, "Editor Power retries the failed start")
retryLesson.tutorial.skipTutorial(); settle(retryLesson)
expect(retryRuntime.state == .stopped, "Retry followed by Skip restores originally stopped state")
retryLesson.shutdown()
expect(!TutorialStep.buildAddBass.allowsPowerControl && !TutorialStep.advancedIntro.allowsPowerControl,
       "Other tutorial Power locks stay unchanged")
print("PASS: pending entry waits for settled state; failed tutorial start remains retryable; other lesson locks unchanged")

// Exercise the tab model under repeated UI-style mutations. Reordering must
// remain visual-only: processors, graphs, Default ownership and persistence
// cannot drift as tabs move around.
let tabStressDirectory = directory.appendingPathComponent("tab-stress")
let tabStress = ChainWorkspace(directory: tabStressDirectory, runtime: runtime())
let tabDefaultID = tabStress.selectedID
let stressTargets = (0..<10).map { index in
    AudioCaptureTarget(
        bundleID: "test.tab.\(index)",
        name: "Stress App \(index)",
        bundlePath: "/StressApp\(index).app"
    )
}
for (index, target) in stressTargets.enumerated() {
    tabStress.add(target)
    let processor = tabStress.selectedProcessor!
    var stressGraph = processor.currentGraphSnapshot!
    stressGraph.nodes = [BeginnerNode(type: index.isMultiple(of: 2) ? .clarity : .bassBoost)]
    processor.applyIndependentGraph(stressGraph)
    tabStress.capture()
}
expect(tabStress.chains.count == 11 && tabStress.chains.first?.id == tabDefaultID,
       "Rapid tab additions preserve exactly one leading Default")
let stressIDs = tabStress.chains.compactMap { $0.target == nil ? nil : $0.id }
let stressProcessors = Dictionary(uniqueKeysWithValues: stressIDs.compactMap { id in
    tabStress.runtime.processors[id].map { (id, $0) }
})

for iteration in 0..<120 {
    let moving = stressIDs[iteration % stressIDs.count]
    let destination = stressIDs[(iteration * 7 + 3) % stressIDs.count]
    if moving != destination { tabStress.moveAppChain(moving, toPositionOf: destination) }
    tabStress.select(stressIDs[(iteration * 3) % stressIDs.count])
    if iteration.isMultiple(of: 5) { tabStress.toggleEffects(stressIDs[(iteration * 3) % stressIDs.count]) }
    expect(tabStress.chains.first?.id == tabDefaultID, "Tab stress moved Default away from the first position")
    expect(Set(tabStress.chains.map(\.id)) == Set([tabDefaultID] + stressIDs),
           "Tab stress duplicated or lost a chain")
    for id in stressIDs {
        expect(tabStress.runtime.processors[id] === stressProcessors[id],
               "Tab reorder replaced an active processor")
    }
}

let countBeforeDuplicate = tabStress.chains.count
let duplicateTarget = AudioCaptureTarget(
    bundleID: stressTargets[4].bundleID,
    name: "Renamed duplicate",
    bundlePath: "/DifferentPath.app"
)
tabStress.add(duplicateTarget)
expect(tabStress.chains.count == countBeforeDuplicate,
       "Adding an existing application created a duplicate tab")
expect(tabStress.selectedID == stressIDs[4],
       "Adding an existing application should focus its existing tab")

tabStress.capture()
tabStress.store.flush()
let orderBeforeRestart = tabStress.chains.map(\.id)
let restoredTabStress = ChainWorkspace(directory: tabStressDirectory, runtime: runtime())
expect(restoredTabStress.chains.map(\.id) == orderBeforeRestart,
       "Rapidly reordered tabs did not preserve their final order")
for chain in restoredTabStress.chains where chain.target != nil {
    expect(restoredTabStress.runtime.processors[chain.id]?.currentGraphSnapshot?.nodes.count == 1,
           "A tab lost its graph across restart")
}

for id in restoredTabStress.chains.compactMap({ $0.target == nil ? nil : $0.id }).prefix(5) {
    restoredTabStress.remove(id)
}
expect(restoredTabStress.chains.count == 6 && restoredTabStress.chains.first?.id == tabDefaultID,
       "Repeated tab removal damaged Default or removed the wrong count")
restoredTabStress.removeAllAppChains()
expect(restoredTabStress.chains.count == 1 && restoredTabStress.selectedID == tabDefaultID,
       "Close All did not converge to the original Default after tab stress")
restoredTabStress.store.flush()
let finalTabDocument = try ChainWorkspaceStore(directory: tabStressDirectory).load()!
expect(finalTabDocument.chains.count == 1 && finalTabDocument.selectedID == tabDefaultID,
       "Tab stress result did not persist")
tabStress.shutdown()
restoredTabStress.shutdown()
print("PASS: 120 tab reorder/select/toggle cycles, duplicate add, restart, repeated removal and Close All")

let refreshRuntime = runtime()
let refreshChain = ChainWorkspace.emptyChain(target: nil)
try refreshRuntime.configure([refreshChain])
refreshRuntime.captureDefinitions()
var refreshNotifications = 0
let refreshObservation = refreshRuntime.objectWillChange.sink { refreshNotifications += 1 }
refreshRuntime.captureDefinitions()
expect(refreshNotifications == 0, "An unchanged autosave capture republished the menu-bar chain list")
refreshRuntime.processors[refreshChain.id]!.processTapInputTrimDB = -12
refreshRuntime.captureDefinitions()
expect(refreshNotifications == 1, "A real captured chain change was not published exactly once")
withExtendedLifetime(refreshObservation) {}
print("PASS: unchanged autosave capture does not redraw the menu bar; real changes still publish")
