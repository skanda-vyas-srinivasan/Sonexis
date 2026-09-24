import Foundation
@testable import Sonexis

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Sonexis-bitcrusher-\(UUID())")
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func checkParameters(_ preset: SavedPreset, depth: Double, downsample: Double) {
    let parameters = preset.graph.nodes[0].parameters
    expect(parameters.bitcrusherBitDepth == depth, "Unexpected loaded bit depth")
    expect(parameters.bitcrusherDownsample == downsample, "Unexpected loaded downsample")
}

// Load the exact crash fixtures through both import formats and disk libraries.
for (index, field) in ["bitcrusherBitDepth", "bitcrusherDownsample"].enumerated() {
    let data = try Data(contentsOf: root.appendingPathComponent("Tests/ReleaseAudit/malformed-\(field).json"))
    let raw = try decodePresetImportData(data)
    checkParameters(raw, depth: index == 0 ? 16 : 8, downsample: index == 1 ? 20 : 4)
    let wrapper = Data("{\"version\":1,\"exportedAt\":\"2026-09-10T00:00:00Z\",\"preset\":\(String(decoding: data, as: UTF8.self))}".utf8)
    checkParameters(try decodePresetImportData(wrapper), depth: index == 0 ? 16 : 8, downsample: index == 1 ? 20 : 4)

    let directory = temporary.appendingPathComponent(field)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var library = Data("[".utf8); library.append(data); library.append(Data("]".utf8))
    try library.write(to: directory.appendingPathComponent("presets.json"))
    let manager = PresetManager(directory: directory)
    expect(manager.presets.count == 1 && manager.saveError == nil, "Invalid numeric values must not discard the library")
    checkParameters(manager.presets[0], depth: index == 0 ? 16 : 8, downsample: index == 1 ? 20 : 4)
    let reloaded = try JSONDecoder().decode(SavedPreset.self, from: JSONEncoder().encode(raw))
    expect(reloaded.graph.presetComparisonData == raw.graph.presetComparisonData, "Normalized preset must stay clean on round-trip")
}

for (value, depth, downsample) in [(-1e100, 4.0, 1.0), (8.5, 8.5, 8.5)] {
    let json = Data("{\"name\":\"Numeric values\",\"graph\":{\"nodes\":[{\"type\":\"Bitcrusher\",\"parameters\":{\"bitcrusherBitDepth\":\(value),\"bitcrusherDownsample\":\(value)}}]}}".utf8)
    checkParameters(try decodePresetImportData(json), depth: depth, downsample: downsample)
}
let legacy = Data("{\"name\":\"Legacy\",\"chain\":{\"activeEffects\":[{\"type\":\"Bitcrusher\",\"isEnabled\":true,\"parameters\":{\"bitcrusherBitDepth\":1e100,\"bitcrusherDownsample\":-1e100}}]}}".utf8)
checkParameters(try decodePresetImportData(legacy), depth: 16, downsample: 1)
print("PASS: original crash fixtures, wrapped imports, persisted library, legacy migration, negative and fractional values, clean round-trip")

// Bypass decoding entirely to verify the DSP guard, including the legacy global
// controls. Compare actual samples with an independently specified safe value.
func render(depth: Double, downsample: Double, node: Bool, enabled: Bool = true) -> [Float] {
    let engine = AudioEngine(observeSystemLifecycle: false)
    var effect = BeginnerNode(type: .bitcrusher, isEnabled: enabled)
    effect.parameters.bitcrusherBitDepth = depth
    effect.parameters.bitcrusherDownsample = downsample
    if node { engine.updateEffectChain([effect]) }
    engine.bitcrusherEnabled = enabled
    engine.bitcrusherBitDepth = depth
    engine.bitcrusherDownsample = downsample
    engine.publishProcessingState()
    let snapshot = engine.currentProcessingSnapshot()
    var levels: [UUID: Float] = [:]
    var result: [Float] = []
    for block in 0..<4 {
        var audio = (0..<2).map { channel in
            (0..<1024).map { frame in Float(0.2 * sin(Double(frame + block * 1024) * (channel == 0 ? 0.13 : 0.17))) }
        }
        engine.graphProcessor.applyEffect(.bitcrusher, to: &audio, sampleRate: 48_000, channelCount: 2,
            frameLength: 1024, nodeId: node ? effect.id : nil, levelSnapshot: &levels, snapshot: snapshot)
        result.append(contentsOf: audio.flatMap { $0 })
    }
    expect(result.allSatisfy { $0.isFinite }, "Bitcrusher produced non-finite samples")
    expect(result.contains { abs($0) > 0.01 }, "Bitcrusher silently dropped audio")
    return result
}

let cases: [(Double, Double, Double, Double)] = [
    (1e100, 4, 16, 4), (8, 1e100, 8, 20),
    (-1e100, -1e100, 4, 1), (.greatestFiniteMagnitude, .greatestFiniteMagnitude, 16, 20),
    (.nan, .nan, 8, 4), (.infinity, -.infinity, 8, 4),
    (4, 1, 4, 1), (16, 20, 16, 20), (8.9, 4.9, 8, 4)
]
for node in [true, false] {
    for (depth, downsample, expectedDepth, expectedDownsample) in cases {
        expect(render(depth: depth, downsample: downsample, node: node)
            == render(depth: expectedDepth, downsample: expectedDownsample, node: node),
            "DSP output differs from bounded reference")
    }
    expect(render(depth: .nan, downsample: .infinity, node: node, enabled: false)
        == render(depth: 8, downsample: 4, node: node, enabled: false), "Disabled effect must remain safe")
}
print("PASS: node and global DSP output matches safe reference for extreme, non-finite, boundary, fractional and disabled cases")
