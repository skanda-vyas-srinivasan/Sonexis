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
let menuPreset = SavedPreset(name: "Menu test", graph: graph)
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
workspace.shutdown()
print("PASS: menu preset targets one chain without selecting it or restarting playback")

let historyDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("sonexis-chain-history-\(UUID())")
try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: historyDirectory) }
let history = ChainWorkspace(directory: historyDirectory, runtime: runtime())
let historyDefaultID = history.selectedID
history.add(appA)
let historyAppID = history.selectedID
expect(history.canUndo, "Adding a chain creates a workspace undo step")
history.undo()
expect(history.chains.count == 1 && history.selectedID == historyDefaultID && history.canRedo,
       "Undo removes an added chain and restores selection")
history.redo()
expect(history.chains.contains(where: { $0.id == historyAppID }), "Redo restores the added chain")

history.select(historyAppID)
let historyProcessor = history.selectedProcessor!
history.recordUndoState()
historyProcessor.processTapInputTrimDB = -3
history.capture()
history.undo()
expect(history.selectedProcessor!.processTapInputTrimDB == -15, "Undo restores chain gain settings")
history.redo()
expect(history.selectedProcessor!.processTapInputTrimDB == -3, "Redo restores chain gain settings")

let graphBeforeEdit = history.selectedProcessor!.currentGraphSnapshot!
var graphAfterEdit = graphBeforeEdit
graphAfterEdit.nodes = [BeginnerNode(type: .clarity)]
history.recordUndoState(graphOverride: graphBeforeEdit)
history.selectedProcessor!.applyIndependentGraph(graphAfterEdit)
history.capture()
history.undo()
expect(history.selectedProcessor!.currentGraphSnapshot!.nodes.isEmpty, "Undo restores a graph edit")
history.redo()
expect(history.selectedProcessor!.currentGraphSnapshot!.nodes.count == 1, "Redo restores a graph edit")

history.remove(historyAppID)
expect(!history.chains.contains(where: { $0.id == historyAppID }), "Close removes the app chain")
history.undo()
expect(history.chains.contains(where: { $0.id == historyAppID }), "Undo restores a closed app chain")
history.shutdown()
print("PASS: unified workspace undo covers chain lifecycle, gain settings, graphs, selection restoration, and redo")
