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

    private let presetsFileURL: URL

    init() {
        // Store presets in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let audioShaperDir = appSupport.appendingPathComponent("AudioShaper", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: audioShaperDir, withIntermediateDirectories: true)

        presetsFileURL = audioShaperDir.appendingPathComponent("presets.json")

        // Load presets
        loadPresets()
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
}
