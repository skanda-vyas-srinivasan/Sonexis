import Foundation

func expect(_ value: @autoclosure () throws -> Bool, _ message: String) {
    do { if try !value() { fatalError(message) } }
    catch { fatalError("\(message): \(error)") }
}
func encoded(_ snapshot: WorkspaceSnapshot) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(snapshot)
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("sonexis-workspace-tests-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
func directory(_ name: String) throws -> URL {
    let url = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
var node = BeginnerNode(type: .delay, position: CGPoint(x: 341.5, y: -27.25))
node.parameters.delayMix = 0.37
let graph = GraphSnapshot(graphMode: .single, wiringMode: .manual, nodes: [node], connections: [], startNodeID: UUID(), endNodeID: UUID())
let first = WorkspaceSnapshot(graph: graph, presetID: UUID(), inputTrimDB: -8, outputMakeupDB: 7, outputCeilingEnabled: true, effectsEnabled: false)
var second = first
second.graph.nodes[0].position.x = 777
second.graph.nodes[0].parameters.delayMix = 0.82

// Full state, layout, preset identity and effective modified comparison survive.
let normal = try directory("normal")
let presetsURL = normal.appendingPathComponent("presets.json")
let sentinel = Data("named presets remain independent".utf8)
try sentinel.write(to: presetsURL)
var writes = 0
let store = WorkspaceStore(directory: normal, writeData: { data, url in
    writes += 1
    try data.write(to: url, options: .atomic)
})
expect(store.restore() == nil && !store.recoveryRequired, "Clean first launch failed")
store.schedule(first); store.flush()
let restored = WorkspaceStore(directory: normal).restore()!
expect(try encoded(restored) == encoded(first), "Workspace round-trip lost data")
expect(restored.graph.presetComparisonData == first.graph.presetComparisonData, "Unmodified preset became modified")
store.schedule(second); store.flush()
let modified = WorkspaceStore(directory: normal).restore()!
expect(modified.graph.presetComparisonData != first.graph.presetComparisonData, "Unsaved audio edits lost Modified status")
expect(modified.presetID == first.presetID && modified.graph.nodes[0].position.x == 777, "Identity/layout lost")
expect(try Data(contentsOf: presetsURL) == sentinel, "Autosave changed named presets")
let before = writes
store.schedule(second); store.flush()
expect(writes == before, "Unchanged workspace rewrote disk")

// Debounce coalesces edits; immediate quit flushes the newest snapshot.
for _ in 0..<10 { store.schedule(first) }
store.schedule(second); store.flush()
expect(writes == before, "Quit flush wrote an obsolete edit")
store.schedule(first)
RunLoop.main.run(until: Date().addingTimeInterval(0.7))
store.flush()
expect(try encoded(WorkspaceStore(directory: normal).restore()!) == encoded(first), "Debounced save did not persist")

// Corruption recovers the previous valid workspace and archives the bad bytes.
let primary = normal.appendingPathComponent("workspace.json")
let corrupt = Data("{broken workspace".utf8)
try corrupt.write(to: primary)
let recovery = WorkspaceStore(directory: normal)
let recovered = recovery.restore()!
expect(try encoded(recovered) == encoded(second), "Wrong backup recovered")
expect(!recovery.recoveryRequired && recovery.issue != nil, "Recovery was not explained")
let archives = try FileManager.default.contentsOfDirectory(at: normal.appendingPathComponent("Workspace Recovery"), includingPropertiesForKeys: nil)
expect(try archives.contains { try Data(contentsOf: $0) == corrupt }, "Corrupt original was not preserved")
expect(WorkspaceStore(directory: normal).restore() != nil, "Recovered primary was not repaired")

// Unknown versions never silently fall back to stale backups or overwrite data.
var future = second; future.version = 99
let futureData = try encoded(future)
try futureData.write(to: primary)
let newer = WorkspaceStore(directory: normal)
expect(newer.restore() == nil && newer.recoveryRequired, "Unknown version accepted")
newer.schedule(first); newer.flush()
expect(try Data(contentsOf: primary) == futureData, "Unknown workspace overwritten")
expect(newer.startFresh(), "Explicit fresh start failed")
newer.schedule(first); newer.flush()
expect(WorkspaceStore(directory: normal).restore() != nil, "Fresh start could not save")
let preserved = try FileManager.default.contentsOfDirectory(at: normal.appendingPathComponent("Workspace Recovery"), includingPropertiesForKeys: nil)
expect(try preserved.contains { try Data(contentsOf: $0) == futureData }, "Fresh start destroyed newer data")

// Bad graphs and truncated JSON cannot silently restore an empty canvas.
for (name, data) in [("truncated", Data("{\"version\":1,\"graph\":{}}".utf8)), ("corrupt", corrupt)] {
    let dir = try directory(name)
    let file = dir.appendingPathComponent("workspace.json")
    try data.write(to: file)
    let bad = WorkspaceStore(directory: dir)
    expect(bad.restore() == nil && bad.recoveryRequired, "Invalid data accepted")
    bad.schedule(first); bad.flush()
    expect(try Data(contentsOf: file) == data, "Invalid source overwritten")
}
var duplicate = first; duplicate.graph.nodes.append(node)
let invalidDir = try directory("duplicate")
try encoded(duplicate).write(to: invalidDir.appendingPathComponent("workspace.json"))
let invalid = WorkspaceStore(directory: invalidDir)
expect(invalid.restore() == nil && invalid.recoveryRequired, "Duplicate node IDs accepted")

// A failed write leaves the last successful primary usable and can be retried.
let failureDir = try directory("write-failure")
var fail = false
let failing = WorkspaceStore(directory: failureDir, writeData: { data, url in
    if fail && url.lastPathComponent == "workspace.json" { throw CocoaError(.fileWriteOutOfSpace) }
    try data.write(to: url, options: .atomic)
})
_ = failing.restore()
failing.schedule(first); failing.flush()
fail = true
failing.schedule(second); failing.flush()
expect(failing.issue != nil, "Disk failure not surfaced")
expect(try encoded(WorkspaceStore(directory: failureDir).restore()!) == encoded(first), "Disk failure lost last good workspace")
fail = false
failing.schedule(second); failing.flush()
expect(try encoded(WorkspaceStore(directory: failureDir).restore()!) == encoded(second), "Write retry failed")

// Anonymous unsaved chains and an explicitly empty workspace restore too.
var anonymous = first; anonymous.presetID = nil
failing.schedule(anonymous); failing.flush()
expect(WorkspaceStore(directory: failureDir).restore()!.presetID == nil, "Anonymous chain gained a preset name")
anonymous.graph.nodes = []
failing.schedule(anonymous); failing.flush()
expect(WorkspaceStore(directory: failureDir).restore()!.graph.nodes.isEmpty, "Empty workspace resurrected deleted nodes")

// Split/manual topology, gain overrides and opaque AU state remain intact.
var split = first
split.graph.graphMode = .split
split.graph.leftStartNodeID = UUID(); split.graph.leftEndNodeID = UUID()
split.graph.rightStartNodeID = UUID(); split.graph.rightEndNodeID = UUID()
let pluginData = Data([0, 1, 255, 13, 42])
var plugin = BeginnerNode(type: .plugin, lane: .right)
plugin.plugin = PluginDescriptor(format: .au, identifier: "test.unit", name: "Test", vendor: "Tests").toReference(stateData: pluginData)
split.graph.nodes.append(plugin)
split.graph.connections = [BeginnerConnection(fromNodeId: split.graph.rightStartNodeID!, toNodeId: plugin.id, gain: 0.7)]
split.graph.autoGainOverrides = [BeginnerConnection(fromNodeId: node.id, toNodeId: split.graph.leftEndNodeID!, gain: 0.25)]
failing.schedule(split); failing.flush()
expect(try encoded(WorkspaceStore(directory: failureDir).restore()!) == encoded(split), "Split/plugin data lost")

// If originals cannot be archived, the fresh-start action must remain blocked.
let archiveDir = try directory("archive-failure")
let archiveFile = archiveDir.appendingPathComponent("workspace.json")
try corrupt.write(to: archiveFile)
try Data("not a directory".utf8).write(to: archiveDir.appendingPathComponent("Workspace Recovery"))
let archiveFailure = WorkspaceStore(directory: archiveDir)
_ = archiveFailure.restore()
expect(!archiveFailure.startFresh() && archiveFailure.recoveryRequired, "Failed archival unblocked autosave")
expect(try Data(contentsOf: archiveFile) == corrupt, "Failed archival lost original")
print("PASS: workspace/layout/settings/identity round-trip, Modified comparison, preset isolation, dedup/debounce/quit flush, corruption/backup recovery, future schema preservation, explicit fresh start, invalid graphs, disk failure/retry, anonymous/empty workspaces, split/plugin state, archival failure")
