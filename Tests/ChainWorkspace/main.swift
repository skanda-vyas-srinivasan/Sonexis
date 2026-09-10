import AppKit
import Foundation
@testable import Sonexis
func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
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
workspace.select(aID)
expect(workspace.selectedProcessor === processorA && workspace.selectedProcessor!.currentGraphSnapshot!.nodes.count == 1,"Switching keeps original processor and graph")
expect(workspace.chains.first(where:{$0.id==aID})?.presetID == presetID,"Preset identity belongs to the chain")
workspace.togglePower()
expect(workspace.runtime.state == .running && workspace.runtime.processors.values.allSatisfy(\.isRunning),"Editor power starts every chain")
workspace.selectedProcessor!.stop()
expect(workspace.runtime.state == .stopped,"Editor power stops every chain")
workspace.toggleEffects(aID)
workspace.toggleGlobalBypass()
workspace.toggleGlobalBypass()
expect(!processorA.processingEnabled && workspace.runtime.processors[bID]!.processingEnabled,"Global bypass restores individual states")
workspace.capture();workspace.store.flush()
let restored=ChainWorkspace(directory:directory,runtime:runtime())
expect(restored.selectedID==aID && restored.chains.count==3,"Restore selected chain and all graphs")
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

restored.togglePower()
let defaultProcessor = restored.runtime.processors[defaultID]!
let defaultGraph = defaultProcessor.currentGraphSnapshot
restored.removeAllAppChains()
expect(restored.chains.count == 1 && restored.selectedID == defaultID, "Close all returns to Default")
expect(restored.runtime.processors[defaultID] === defaultProcessor, "Close all preserves Default processor")
expect(defaultProcessor.currentGraphSnapshot?.nodes.count == defaultGraph?.nodes.count, "Close all preserves Default graph")
expect(restored.runtime.state == .running, "Close all keeps Default playback running")
expect(restored.runtime.processors[aID] == nil && restored.runtime.processors[bID] == nil, "Close all releases app processors")
restored.store.flush()
let cleared = try ChainWorkspaceStore(directory: directory).load()!
expect(cleared.chains.count == 1 && cleared.selectedID == defaultID, "Closed app tabs stay removed after relaunch")
restored.removeAllAppChains()
expect(restored.chains.count == 1, "Closing all with only Default is harmless")
restored.shutdown()
print("PASS: close all app chains preserves Default, playback, selection, and persistence")

workspace.add(appB)
let menuTargetID = workspace.selectedID
workspace.select(defaultID)
let preservedDefault = workspace.selectedProcessor!
let preservedGraph = preservedDefault.currentGraphSnapshot!.presetComparisonData
let menuPreset = workspace.presets.savePreset(name: "Menu test", graph: graph)!
workspace.togglePower()
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
lesson.togglePower()
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
lesson.add(practiceApp)
expect(lesson.tutorial.step == .chainsAdd && lesson.chains.count == originalDocument.chains.count,
       "Failed add does not advance or create a partial practice chain")
rejectPractice = false
lesson.add(practiceApp)
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
lesson.remove(practiceChain)
expect(lesson.tutorial.step == .chainsComplete, "Closing the practice chain completes the exercise")
lesson.refreshAndSave()
lesson.store.flush()
let duringLesson = try ChainWorkspaceStore(directory: lessonDirectory).load()!
let duringLessonBytes = try encoder.encode(duringLesson)
expect(duringLessonBytes == originalDocumentBytes,
       "Practice actions never overwrite original chains, selection, preset identity, or gains")
rejectRestore = true
lesson.tutorial.finishTutorial()
expect(lesson.tutorial.isActive, "Failed restore leaves the lesson active so restoration can be retried")
rejectRestore = false
lesson.tutorial.finishTutorial()
expect(!lesson.tutorial.isActive && lesson.selectedID == originalSelection,
       "Finish restores original selection")
expect(lesson.runtime.state == .running && lesson.selectedProcessor!.processTapInputTrimDB == -21
       && lesson.selectedProcessor!.processTapOutputMakeupDB == 6,
       "Finish restores running state and the original gains")
expect(lesson.selectedProcessor!.currentGraphSnapshot!.presetComparisonData == originalLessonGraph.presetComparisonData,
       "Finish restores unsaved graph edits")
lesson.tutorial.startChains()
lesson.tutorial.nextButtonTapped()
lesson.add(practiceApp)
lesson.tutorial.skipTutorial()
expect(!lesson.tutorial.isActive && lesson.selectedID == originalSelection
       && lesson.chains.count == originalDocument.chains.count, "Early exit removes practice work and restores original chains")
lesson.tutorial.startChains()
lesson.tutorial.nextButtonTapped()
lesson.add(practiceApp)
let continuingPractice = lesson.selectedID
lesson.tutorial.step = .chainsClose
lesson.remove(continuingPractice)
rejectRestore = true
lesson.tutorial.continueToNextLesson()
expect(lesson.tutorial.step == .chainsComplete && lesson.tutorial.pendingNextLesson == nil,
       "Continue must not open Manual wiring if original chains cannot be restored")
rejectRestore = false
lesson.tutorial.continueToNextLesson()
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
lesson.tutorial.skipTutorial()
lesson.shutdown()
print("PASS: real app tutorial actions, failed-operation gating, shared progress, persistence isolation, finish and early-exit restoration")
