import Foundation
import Combine
import CoreGraphics

// MARK: - Saved Preset Model

struct SavedPreset: Identifiable, Codable {
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

    init(id: UUID, name: String, graph: GraphSnapshot, createdDate: Date) {
        self.id = id
        self.name = name
        self.graph = graph
        self.createdDate = createdDate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case graph
        case createdDate
        case chain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.createdDate = try container.decodeIfPresent(Date.self, forKey: .createdDate) ?? Date()

        if let graph = try container.decodeIfPresent(GraphSnapshot.self, forKey: .graph) {
            self.graph = graph
        } else if let chain = try container.decodeIfPresent(EffectChainSnapshot.self, forKey: .chain) {
            self.graph = Self.graphFromChain(chain)
        } else {
            self.graph = GraphSnapshot(
                graphMode: .single,
                wiringMode: .automatic,
                nodes: [],
                connections: [],
                startNodeID: UUID(),
                endNodeID: UUID(),
                hasNodeParameters: true
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(graph, forKey: .graph)
        try container.encode(createdDate, forKey: .createdDate)
    }

    private static func graphFromChain(_ chain: EffectChainSnapshot) -> GraphSnapshot {
        let startID = UUID()
        let endID = UUID()
        let baseY: CGFloat = 300
        let startX: CGFloat = 220
        let spacing: CGFloat = 160
        let nodes: [BeginnerNode] = chain.activeEffects.enumerated().map { index, snapshot in
            var node = BeginnerNode(
                type: snapshot.type,
                position: CGPoint(x: startX + spacing * CGFloat(index), y: baseY),
                lane: .left,
                isEnabled: snapshot.isEnabled,
                parameters: parametersFromSnapshot(snapshot)
            )
            return node
        }

        return GraphSnapshot(
            graphMode: .single,
            wiringMode: .automatic,
            nodes: nodes,
            connections: [],
            startNodeID: startID,
            endNodeID: endID,
            hasNodeParameters: true
        )
    }

    private static func parametersFromSnapshot(_ snapshot: EffectChainSnapshot.EffectSnapshot) -> NodeEffectParameters {
        var params = NodeEffectParameters.defaults()
        let values = snapshot.parameters
        switch snapshot.type {
        case .bassBoost:
            params.bassBoostAmount = values.bassBoostAmount ?? params.bassBoostAmount
        case .pitchShift:
            params.nightcoreIntensity = values.nightcoreIntensity ?? params.nightcoreIntensity
        case .clarity:
            params.clarityAmount = values.clarityAmount ?? params.clarityAmount
        case .deMud:
            params.deMudStrength = values.deMudStrength ?? params.deMudStrength
        case .simpleEQ:
            params.eqBass = values.eqBass ?? params.eqBass
            params.eqMids = values.eqMids ?? params.eqMids
            params.eqTreble = values.eqTreble ?? params.eqTreble
        case .tenBandEQ:
            if let gains = values.tenBandGains, gains.count == params.tenBandGains.count {
                params.tenBandGains = gains
            }
        case .compressor:
            params.compressorStrength = values.compressorStrength ?? params.compressorStrength
        case .reverb:
            params.reverbMix = values.reverbMix ?? params.reverbMix
            params.reverbSize = values.reverbSize ?? params.reverbSize
        case .stereoWidth:
            params.stereoWidthAmount = values.stereoWidthAmount ?? params.stereoWidthAmount
        case .delay:
            params.delayTime = values.delayTime ?? params.delayTime
            params.delayFeedback = values.delayFeedback ?? params.delayFeedback
            params.delayMix = values.delayMix ?? params.delayMix
        case .distortion:
            params.distortionDrive = values.distortionDrive ?? params.distortionDrive
            params.distortionMix = values.distortionMix ?? params.distortionMix
        case .tremolo:
            params.tremoloRate = values.tremoloRate ?? params.tremoloRate
            params.tremoloDepth = values.tremoloDepth ?? params.tremoloDepth
        case .chorus:
            params.chorusRate = values.chorusRate ?? params.chorusRate
            params.chorusDepth = values.chorusDepth ?? params.chorusDepth
            params.chorusMix = values.chorusMix ?? params.chorusMix
        case .phaser:
            params.phaserRate = values.phaserRate ?? params.phaserRate
            params.phaserDepth = values.phaserDepth ?? params.phaserDepth
        case .flanger:
            params.flangerRate = values.flangerRate ?? params.flangerRate
            params.flangerDepth = values.flangerDepth ?? params.flangerDepth
            params.flangerFeedback = values.flangerFeedback ?? params.flangerFeedback
            params.flangerMix = values.flangerMix ?? params.flangerMix
        case .bitcrusher:
            params.bitcrusherBitDepth = values.bitcrusherBitDepth ?? params.bitcrusherBitDepth
            params.bitcrusherDownsample = values.bitcrusherDownsample ?? params.bitcrusherDownsample
            params.bitcrusherMix = values.bitcrusherMix ?? params.bitcrusherMix
        case .tapeSaturation:
            params.tapeSaturationDrive = values.tapeSaturationDrive ?? params.tapeSaturationDrive
            params.tapeSaturationMix = values.tapeSaturationMix ?? params.tapeSaturationMix
        case .resampling:
            params.resampleRate = values.resampleRate ?? params.resampleRate
            params.resampleCrossfade = values.resampleCrossfade ?? params.resampleCrossfade
        case .rubberBandPitch:
            params.rubberBandPitchSemitones = values.rubberBandPitchSemitones ?? params.rubberBandPitchSemitones
        }
        return params
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

        // Delay
        var delayTime: Double?
        var delayFeedback: Double?
        var delayMix: Double?

        // Distortion
        var distortionDrive: Double?
        var distortionMix: Double?

        // Tremolo
        var tremoloRate: Double?
        var tremoloDepth: Double?

        // Chorus
        var chorusRate: Double?
        var chorusDepth: Double?
        var chorusMix: Double?

        // Phaser
        var phaserRate: Double?
        var phaserDepth: Double?

        // Flanger
        var flangerRate: Double?
        var flangerDepth: Double?
        var flangerFeedback: Double?
        var flangerMix: Double?

        // Bitcrusher
        var bitcrusherBitDepth: Double?
        var bitcrusherDownsample: Double?
        var bitcrusherMix: Double?

        // Tape Saturation
        var tapeSaturationDrive: Double?
        var tapeSaturationMix: Double?

        // Resampling
        var resampleRate: Double?
        var resampleCrossfade: Double?

        // Rubber Band
        var rubberBandPitchSemitones: Double?
    }
}

// MARK: - Preset Manager

class PresetManager: ObservableObject {
    @Published var presets: [SavedPreset] = []
    @Published var saveError: String?

    private let presetsFileURL: URL

    init() {
        // Store presets in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let legacyDir = appSupport.appendingPathComponent("AudioShaper", isDirectory: true)
        let layaDir = appSupport.appendingPathComponent("Sonexis", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: layaDir, withIntermediateDirectories: true)

        let legacyPresetsURL = legacyDir.appendingPathComponent("presets.json")
        let newPresetsURL = layaDir.appendingPathComponent("presets.json")

        if !FileManager.default.fileExists(atPath: newPresetsURL.path),
           FileManager.default.fileExists(atPath: legacyPresetsURL.path) {
            try? FileManager.default.moveItem(at: legacyPresetsURL, to: newPresetsURL)
        }

        presetsFileURL = newPresetsURL

        // Load presets
        loadPresets()
    }

    @discardableResult
    func savePreset(name: String, graph: GraphSnapshot) -> SavedPreset {
        let preset = SavedPreset(name: name, graph: graph)
        presets.insert(preset, at: 0)
        persistPresets()
        return preset
    }

    func deletePreset(_ preset: SavedPreset) {
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    func updatePreset(id: UUID, graph: GraphSnapshot) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        let existing = presets[index]
        presets[index] = SavedPreset(id: existing.id, name: existing.name, graph: graph, createdDate: existing.createdDate)
        persistPresets()
    }

    private func persistPresets() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(presets)
            try data.write(to: presetsFileURL, options: .atomic)
        } catch {
            saveError = "Failed to save preset: \(error.localizedDescription)"
        }
    }

    private func loadPresets() {
        do {
            guard FileManager.default.fileExists(atPath: presetsFileURL.path) else {
                // No presets file found.
                return
            }

            let data = try Data(contentsOf: presetsFileURL)
            let decoder = JSONDecoder()
            presets = try decoder.decode([SavedPreset].self, from: data)
            presets.sort { $0.createdDate > $1.createdDate }
        } catch {
            // Reset to empty if corrupted
            presets = []
        }
    }
}
