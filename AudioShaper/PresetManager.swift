import Foundation
import Combine

// MARK: - Saved Preset Model

struct SavedPreset: Identifiable, Codable {
    let id: UUID
    let name: String
    let chain: EffectChainSnapshot
    let createdDate: Date

    init(id: UUID = UUID(), name: String, chain: EffectChainSnapshot) {
        self.id = id
        self.name = name
        self.chain = chain
        self.createdDate = Date()
    }
}

// MARK: - Effect Chain Snapshot

struct EffectChainSnapshot: Codable {
    var activeEffects: [EffectSnapshot]

    struct EffectSnapshot: Codable {
        let type: EffectType
        let isEnabled: Bool
        let parameters: EffectParameters
    }

    struct EffectParameters: Codable {
        // Bass Boost
        var bassBoostAmount: Double?

        // Nightcore
        var nightcoreIntensity: Double?

        // Clarity
        var clarityAmount: Double?

        // De-Mud
        var deMudStrength: Double?

        // Simple EQ
        var eqBass: Double?
        var eqMids: Double?
        var eqTreble: Double?

        // 10-Band EQ
        var tenBandGains: [Double]?

        // Compressor
        var compressorStrength: Double?

        // Reverb
        var reverbMix: Double?
        var reverbSize: Double?

        // Stereo Width
        var stereoWidthAmount: Double?
    }
}

// MARK: - Preset Manager

class PresetManager: ObservableObject {
    @Published var presets: [SavedPreset] = []
    @Published var graphPresets: [SavedGraphPreset] = []

    private let presetsFileURL: URL
    private let graphsFileURL: URL

    init() {
        // Store presets in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let audioShaperDir = appSupport.appendingPathComponent("AudioShaper", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: audioShaperDir, withIntermediateDirectories: true)

        presetsFileURL = audioShaperDir.appendingPathComponent("presets.json")
        graphsFileURL = audioShaperDir.appendingPathComponent("graphs.json")

        // Load presets
        loadPresets()
        loadGraphPresets()
    }

    func savePreset(name: String, chain: EffectChainSnapshot) {
        let preset = SavedPreset(name: name, chain: chain)
        presets.append(preset)
        persistPresets()
    }

    func deletePreset(_ preset: SavedPreset) {
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    func saveGraphPreset(name: String, snapshot: GraphSnapshot) {
        let preset = SavedGraphPreset(name: name, graph: snapshot)
        graphPresets.append(preset)
        persistGraphPresets()
    }

    func deleteGraphPreset(_ preset: SavedGraphPreset) {
        graphPresets.removeAll { $0.id == preset.id }
        persistGraphPresets()
    }

    private func persistPresets() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(presets)
            try data.write(to: presetsFileURL, options: .atomic)
            print("✅ Presets saved to: \(presetsFileURL.path)")
        } catch {
            print("❌ Failed to save presets: \(error)")
        }
    }

    private func persistGraphPresets() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(graphPresets)
            try data.write(to: graphsFileURL, options: .atomic)
            print("✅ Graph presets saved to: \(graphsFileURL.path)")
        } catch {
            print("❌ Failed to save graph presets: \(error)")
        }
    }

    private func loadPresets() {
        do {
            guard FileManager.default.fileExists(atPath: presetsFileURL.path) else {
                print("ℹ️ No presets file found, starting fresh")
                return
            }

            let data = try Data(contentsOf: presetsFileURL)
            let decoder = JSONDecoder()
            presets = try decoder.decode([SavedPreset].self, from: data)
            print("✅ Loaded \(presets.count) presets from: \(presetsFileURL.path)")
        } catch {
            print("❌ Failed to load presets: \(error)")
            presets = []
        }
    }

    private func loadGraphPresets() {
        do {
            guard FileManager.default.fileExists(atPath: graphsFileURL.path) else {
                print("ℹ️ No graph presets file found, starting fresh")
                return
            }

            let data = try Data(contentsOf: graphsFileURL)
            let decoder = JSONDecoder()
            graphPresets = try decoder.decode([SavedGraphPreset].self, from: data)
            print("✅ Loaded \(graphPresets.count) graph presets from: \(graphsFileURL.path)")
        } catch {
            print("❌ Failed to load graph presets: \(error)")
            graphPresets = []
        }
    }
}

// MARK: - Saved Graph Preset

struct SavedGraphPreset: Identifiable, Codable {
    let id: UUID
    let name: String
    let graph: GraphSnapshot
    let createdDate: Date

    init(id: UUID = UUID(), name: String, graph: GraphSnapshot) {
        self.id = id
        self.name = name
        self.graph = graph
        self.createdDate = Date()
    }
}
