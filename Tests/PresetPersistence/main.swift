import Foundation

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("Sonexis-preset-tests-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let graph = GraphSnapshot(graphMode: .single, wiringMode: .automatic,
    nodes: [BeginnerNode(type: .bassBoost, position: .zero)], connections: [],
    startNodeID: UUID(), endNodeID: UUID())
var changed = graph
changed.nodes[0].parameters.bassBoostAmount = 0.9
let directory = root.appendingPathComponent("normal")
var failTarget: String?
let manager = PresetManager(directory: directory, writeData: { data, url in
    if url.lastPathComponent == failTarget { throw CocoaError(.fileWriteNoPermission) }
    try data.write(to: url, options: .atomic)
})
let saved = manager.savePreset(name: "Music", graph: graph)!
let primary = directory.appendingPathComponent("presets.json")
let baseline = try Data(contentsOf: primary)
expect(PresetManager(directory: directory).presets.first?.id == saved.id, "Save must survive reload")
failTarget = "presets.json"
expect(manager.savePreset(name: "Failed", graph: graph) == nil, "Failed creation must return nil")
expect(!manager.updatePreset(id: saved.id, graph: changed), "Failed update must return false")
expect(!manager.deletePreset(saved), "Failed deletion must return false")
expect(!manager.addPreset(SavedPreset(name: "Music", graph: changed), overwriteExistingNamed: "Music"), "Failed import must return false")
expect(manager.presets.count == 1 && manager.presets[0].id == saved.id, "Failures must preserve memory")
expect(manager.presets[0].graph.nodes[0].parameters == graph.nodes[0].parameters, "Failed update must preserve graph")
let afterFailures = try Data(contentsOf: primary)
expect(afterFailures == baseline, "Failures must preserve disk")
expect(manager.saveError != nil, "Failure must be surfaced")
failTarget = "presets.backup.json"
expect(!manager.updatePreset(id: saved.id, graph: changed), "Backup failure must abort primary write")
let afterBackupFailure = try Data(contentsOf: primary)
expect(afterBackupFailure == baseline, "Backup failure must preserve disk")
failTarget = nil
expect(manager.updatePreset(id: saved.id, graph: changed), "Retry must succeed")
expect(manager.saveError == nil, "Success must clear previous failure")
expect(!manager.updatePreset(id: UUID(), graph: graph), "Missing ID cannot report success")
let corrupt = Data("{ broken preset library".utf8)
try corrupt.write(to: primary)
let recovered = PresetManager(directory: directory)
expect(recovered.presets.first?.id == saved.id, "Must recover backup")
expect(recovered.presets[0].graph.nodes[0].parameters == graph.nodes[0].parameters, "Backup is last committed version")
expect(recovered.saveError?.contains("Recovered") == true, "Recovery must be disclosed")
let archives = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("presets-unreadable-") }
expect(archives.count == 1, "Corrupt original must be archived")
let archived = try Data(contentsOf: archives[0])
expect(archived == corrupt, "Archive must preserve exact bytes")
expect(recovered.savePreset(name: "After recovery", graph: graph) != nil, "Recovered library must be saveable")
expect(PresetManager(directory: directory).presets.count == 2, "Recovery save must survive reload")
let brokenDir = root.appendingPathComponent("no-backup")
try FileManager.default.createDirectory(at: brokenDir, withIntermediateDirectories: true)
let brokenPrimary = brokenDir.appendingPathComponent("presets.json")
try corrupt.write(to: brokenPrimary)
let blocked = PresetManager(directory: brokenDir)
expect(blocked.savePreset(name: "Unsafe", graph: graph) == nil, "No backup must block overwrite")
let retained = try Data(contentsOf: brokenPrimary)
expect(retained == corrupt, "Blocked save must retain original")
let archiveBlocked = PresetManager(directory: brokenDir, writeData: { _, _ in throw CocoaError(.fileWriteNoPermission) })
expect(archiveBlocked.savePreset(name: "Unsafe", graph: graph) == nil, "Failed preservation must block saving")
try FileManager.default.removeItem(at: primary)
let missing = PresetManager(directory: directory)
expect(!missing.presets.isEmpty && missing.saveError != nil, "Missing primary must recover backup visibly")
print("PASS: preset persistence creation/reload, transactional failures, retry, backup failure, corruption preservation/recovery, blocked unsafe writes, missing primary recovery")

// Saved-content comparison must ignore generated wire IDs but catch real edits.
let comparison = graph.presetComparisonData!
let roundTrip = try JSONDecoder().decode(GraphSnapshot.self, from: JSONEncoder().encode(graph))
expect(roundTrip.presetComparisonData == comparison, "Loaded preset must compare clean")
expect(changed.presetComparisonData != comparison, "Parameter edit must mark Modified")
var edit = graph
edit.nodes[0].isEnabled.toggle()
expect(edit.presetComparisonData != comparison, "Node bypass must mark Modified")
edit = graph
edit.nodes[0].position.x += 30
expect(edit.presetComparisonData == comparison, "Layout-only movement must stay clean")
edit = graph
edit.nodes.append(BeginnerNode(type: .clarity))
expect(edit.presetComparisonData != comparison, "Added node must mark Modified")
edit.nodes.removeLast()
expect(edit.presetComparisonData == comparison, "Undo to saved content must clear Modified")
edit = graph
edit.wiringMode = .manual
expect(edit.presetComparisonData != comparison, "Wiring mode must mark Modified")
var wired = graph
wired.autoGainOverrides = [
    BeginnerConnection(fromNodeId: graph.startNodeID, toNodeId: graph.nodes[0].id, gain: 0.4),
    BeginnerConnection(fromNodeId: graph.nodes[0].id, toNodeId: graph.endNodeID, gain: 0.8)
]
var regenerated = wired
regenerated.autoGainOverrides = wired.autoGainOverrides.reversed().map {
    BeginnerConnection(fromNodeId: $0.fromNodeId, toNodeId: $0.toNodeId, gain: $0.gain)
}
regenerated.leftStartNodeID = UUID()
regenerated.leftEndNodeID = UUID()
regenerated.hasNodeParameters = false
expect(regenerated.presetComparisonData == wired.presetComparisonData, "Transient wire IDs, ordering, unused terminals and migration flags must not mark Modified")
regenerated.autoGainOverrides[0].gain = 0.2
expect(regenerated.presetComparisonData != wired.presetComparisonData, "Wire gain must mark Modified")
let statusDir = root.appendingPathComponent("modified-status")
var rejectSave = false
let statusManager = PresetManager(directory: statusDir, writeData: { data, url in
    if rejectSave { throw CocoaError(.fileWriteNoPermission) }
    try data.write(to: url, options: .atomic)
})
let named = statusManager.savePreset(name: "Named", graph: graph)!
rejectSave = true
expect(!statusManager.updatePreset(id: named.id, graph: changed), "Fixture save should fail")
expect(statusManager.presets[0].graph.presetComparisonData != changed.presetComparisonData, "Failed save must remain Modified")
rejectSave = false
expect(statusManager.updatePreset(id: named.id, graph: changed), "Fixture save should succeed")
expect(statusManager.presets[0].graph.presetComparisonData == changed.presetComparisonData, "Successful save must clear Modified")
print("PASS: preset comparison reload, parameter/bypass/layout/add/undo/routing/gain edits, transient identity normalization, failed and successful saves")

var chain = graph
chain.nodes[0].position = CGPoint(x: 100, y: 100)
chain.nodes.append(BeginnerNode(type: .clarity, position: CGPoint(x: 200, y: 100)))
var moved = chain
moved.nodes[0].position = CGPoint(x: 120, y: 180)
expect(moved.presetComparisonData == chain.presetComparisonData, "Automatic layout without reorder must stay clean")
moved.nodes[0].position.x = 300
expect(moved.presetComparisonData != chain.presetComparisonData, "Automatic reorder must mark Modified")
chain.wiringMode = .manual
moved.wiringMode = .manual
expect(moved.presetComparisonData == chain.presetComparisonData, "Manual layout must stay clean even across another node")
moved.connections.append(BeginnerConnection(fromNodeId: moved.nodes[0].id, toNodeId: moved.nodes[1].id))
expect(moved.presetComparisonData != chain.presetComparisonData, "Manual wiring edit must mark Modified")
print("PASS: layout-only moves stay clean; automatic order and manual wiring changes mark Modified")

// Returning from Manual must not let retained edges override Automatic order.
var returnedToAutomatic = chain
returnedToAutomatic.wiringMode = .automatic
returnedToAutomatic.connections = [
    BeginnerConnection(fromNodeId: chain.startNodeID, toNodeId: chain.nodes[0].id),
    BeginnerConnection(fromNodeId: chain.nodes[0].id, toNodeId: chain.nodes[1].id),
    BeginnerConnection(fromNodeId: chain.nodes[1].id, toNodeId: chain.endNodeID)
]
var cleanAutomatic = returnedToAutomatic
cleanAutomatic.connections = []
expect(returnedToAutomatic.presetComparisonData == cleanAutomatic.presetComparisonData,
       "Retained manual edges must not affect Automatic preset status")
returnedToAutomatic.nodes.append(BeginnerNode(type: .enhancer, position: CGPoint(x: 150, y: 200)))
cleanAutomatic.nodes = returnedToAutomatic.nodes
expect(returnedToAutomatic.presetComparisonData == cleanAutomatic.presetComparisonData,
       "Added automatic nodes must follow position despite retained manual edges")
var reorderedAutomatic = returnedToAutomatic
reorderedAutomatic.nodes[2].position.x = 250
expect(reorderedAutomatic.presetComparisonData != returnedToAutomatic.presetComparisonData,
       "Retained manual edges must not hide an automatic order change")
print("PASS: Automatic ignores retained manual edges after mode round trip and node insertion")

let libraryDir = root.appendingPathComponent("library-actions")
var rejectLibraryWrite = false
let library = PresetManager(directory: libraryDir, writeData: { data, url in
    if rejectLibraryWrite { throw CocoaError(.fileWriteNoPermission) }
    try data.write(to: url, options: .atomic)
})
let first = library.savePreset(name: "First", graph: graph)!
let second = library.savePreset(name: "Second", graph: changed)!
expect(library.savePreset(name: "  second  ", graph: graph) == nil,
       "Save As must reject duplicate names case-insensitively after trimming")
expect(library.presets.count == 2, "Rejected duplicate Save As must not mutate the library")
expect(!library.renamePreset(id: first.id, name: "  "), "Blank rename must fail")
expect(!library.renamePreset(id: first.id, name: "SECOND"), "Duplicate rename must fail case-insensitively")
rejectLibraryWrite = true
expect(!library.renamePreset(id: first.id, name: "Renamed"), "Failed rename must be reported")
expect(library.presets.first(where: { $0.id == first.id })?.name == "First", "Failed rename must preserve original")
rejectLibraryWrite = false
expect(library.renamePreset(id: first.id, name: "  Renamed  "), "Rename must succeed")
let renamed = library.presets.first(where: { $0.id == first.id })!
expect(renamed.name == "Renamed" && renamed.createdDate == first.createdDate, "Rename must trim and preserve identity/date")
expect(renamed.graph.presetComparisonData == graph.presetComparisonData, "Rename must preserve saved graph")
expect(PresetManager(directory: libraryDir).presets.contains(where: { $0.id == first.id && $0.name == "Renamed" }), "Rename must survive reload")
expect(library.addPreset(SavedPreset(name: "Renamed", graph: changed), overwriteExistingNamed: "Renamed"), "Replacement import must succeed")
expect(library.presets.first?.id == first.id, "Replacement import must retain active preset identity")
expect(library.presets.first?.graph.presetComparisonData == changed.presetComparisonData, "Replacement must store imported graph")
expect(!library.addPreset(SavedPreset(name: "  RENAMED ", graph: graph)),
       "Direct import must reject duplicate names instead of relying on its caller")
let reusedID = SavedPreset(id: second.id, name: "Third", graph: graph, createdDate: second.createdDate)
expect(library.addPreset(reusedID), "Import with a duplicate ID and unique name must succeed")
expect(Set(library.presets.map(\.id)).count == library.presets.count, "Import IDs must remain unique")
expect(library.deletePreset(renamed), "Delete must succeed")
expect(!library.presets.contains(where: { $0.id == first.id }), "Deleted preset must leave library")
expect(!PresetManager(directory: libraryDir).presets.contains(where: { $0.id == first.id }), "Deletion must survive reload")
print("PASS: rename validation/failure/identity/reload, replacement import identity, duplicate import IDs, deletion/reload")

let seedDir = root.appendingPathComponent("starter-seeding")
let seedMarker = "Sonexis.tests.starter.\(UUID().uuidString)"
defer { UserDefaults.standard.removeObject(forKey: seedMarker) }
let seedManager = PresetManager(directory: seedDir)
let starterA = SavedPreset(name: "Starter A", graph: graph)
let starterB = SavedPreset(name: "Starter B", graph: changed)
seedManager.installStarterPresetsIfNeeded([starterA, starterB], markerKey: seedMarker)
expect(seedManager.presets.contains(where: { $0.id == starterA.id }) &&
       seedManager.presets.contains(where: { $0.id == starterB.id }), "First launch must seed starter presets")
expect(seedManager.deletePreset(starterA), "Seeded presets remain editable and deletable")
seedManager.installStarterPresetsIfNeeded([starterA, starterB], markerKey: seedMarker)
expect(!seedManager.presets.contains(where: { $0.id == starterA.id }), "Deleted starter must not return")
expect(seedManager.presets.filter { $0.id == starterB.id }.count == 1, "Starter seeding must not duplicate presets")
print("PASS: starter presets seed once, remain editable, and stay deleted")

// Audio Units can emit equivalent fullState dictionaries in different byte orders.
let stateXMLA = Data("""
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>name</key><string>Harmony</string>
<key>parameters</key><dict><key>pitch</key><real>7</real><key>mix</key><real>0.5</real></dict>
<key>channels</key><array><integer>1</integer><integer>2</integer></array>
<key>enabled</key><true/><key>blob</key><data>AQID</data>
<key>created</key><date>2026-09-01T00:00:00Z</date>
</dict></plist>
""".utf8)
let stateXMLB = Data("""
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>created</key><date>2026-09-01T00:00:00Z</date>
<key>blob</key><data>AQID</data><key>enabled</key><true/>
<key>channels</key><array><integer>1</integer><integer>2</integer></array>
<key>parameters</key><dict><key>mix</key><real>0.5</real><key>pitch</key><real>7</real></dict>
<key>name</key><string>Harmony</string>
</dict></plist>
""".utf8)
var auGraph = graph
auGraph.nodes = [BeginnerNode(type: .plugin, position: .zero)]
auGraph.nodes[0].plugin = PluginReference(format: .au, identifier: "test.harmony", name: "Harmony", vendor: "Test", stateData: stateXMLA)
func graphWithAUState(_ state: Data) -> GraphSnapshot {
    var result = auGraph
    result.nodes[0].plugin?.stateData = state
    return result
}
let decodedState = try PropertyListSerialization.propertyList(from: stateXMLB, options: [], format: nil)
let binaryState = try PropertyListSerialization.data(fromPropertyList: decodedState, format: .binary, options: 0)
expect(stateXMLA != stateXMLB && binaryState != stateXMLA, "Fixtures use different encodings")
expect(auGraph.presetComparisonData == graphWithAUState(stateXMLB).presetComparisonData,
       "AU key order must not mark a freshly loaded preset Modified")
expect(auGraph.presetComparisonData == graphWithAUState(binaryState).presetComparisonData,
       "AU XML versus binary encoding must not mark Modified")
expect(auGraph.nodes[0].plugin?.stateData == stateXMLA, "Comparison must not rewrite saved AU state")
for (from, to) in [("<real>7</real>", "<real>12</real>"), ("<true/>", "<false/>"),
                   ("<data>AQID</data>", "<data>AQIE</data>"),
                   ("2026-09-01", "2026-09-02"),
                   ("<integer>1</integer><integer>2</integer>", "<integer>2</integer><integer>1</integer>")] {
    let edited = Data(String(decoding: stateXMLA, as: UTF8.self).replacingOccurrences(of: from, with: to).utf8)
    expect(auGraph.presetComparisonData != graphWithAUState(edited).presetComparisonData,
           "Actual AU state changes must still mark Modified: \(from)")
}
let opaqueA = graphWithAUState(Data([0x01, 0x02]))
let opaqueB = graphWithAUState(Data([0x01, 0x03]))
expect(opaqueA.presetComparisonData != opaqueB.presetComparisonData, "Opaque states keep byte-level change detection")
print("PASS: AU state comparison ignores serialization differences and preserves real edits and original state bytes")
