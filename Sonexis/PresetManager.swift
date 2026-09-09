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
        let activeEffects = chain.activeEffects.filter { !$0.type.isRetired }
        let nodes: [BeginnerNode] = activeEffects.enumerated().map { index, snapshot in
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
        case .enhancer:
            params.enhancerAmount = values.enhancerAmount ?? params.enhancerAmount
        case .bassBoost:
            params.bassBoostAmount = values.bassBoostAmount ?? params.bassBoostAmount
        case .pitchShift:
            params.nightcoreIntensity = values.nightcoreIntensity ?? params.nightcoreIntensity
        case .clarity:
            params.clarityAmount = values.clarityAmount ?? params.clarityAmount
        case .deMud:
            params.deMudStrength = values.deMudStrength ?? params.deMudStrength
        case .simpleEQ, .appleThreeBandEQ:
            params.eqBass = values.eqBass ?? params.eqBass
            params.eqMids = values.eqMids ?? params.eqMids
            params.eqTreble = values.eqTreble ?? params.eqTreble
        case .tenBandEQ:
            if let gains = values.tenBandGains, gains.count == params.tenBandGains.count {
                params.tenBandGains = gains
            }
        case .compressor:
            params.compressorStrength = values.compressorStrength ?? params.compressorStrength
            params.compressorThresholdDB = values.compressorThresholdDB ?? params.compressorThresholdDB
            params.compressorRatio = values.compressorRatio ?? params.compressorRatio
            params.compressorAttackMS = values.compressorAttackMS ?? params.compressorAttackMS
            params.compressorReleaseMS = values.compressorReleaseMS ?? params.compressorReleaseMS
            params.compressorMakeupDB = values.compressorMakeupDB ?? params.compressorMakeupDB
            params.compressorMix = values.compressorMix ?? params.compressorMix
        case .reverb:
            params.reverbMix = values.reverbMix ?? params.reverbMix
            params.reverbSize = values.reverbSize ?? params.reverbSize
        case .stereoWidth:
            params.stereoWidthAmount = values.stereoWidthAmount ?? params.stereoWidthAmount
        case .delay:
            params.delayTime = values.delayTime ?? params.delayTime
            params.delayFeedback = values.delayFeedback ?? params.delayFeedback
            params.delayMix = values.delayMix ?? params.delayMix
        case .amp:
            params.ampInputGain = values.ampInputGain ?? params.ampInputGain
            params.ampDrive = values.ampDrive ?? params.ampDrive
            params.ampOutputGain = values.ampOutputGain ?? params.ampOutputGain
            params.ampMix = values.ampMix ?? params.ampMix
        case .distortion:
            params.distortionDrive = values.distortionDrive ?? params.distortionDrive
            params.distortionMix = values.distortionMix ?? params.distortionMix
        case .tremolo:
            params.tremoloRate = values.tremoloRate ?? params.tremoloRate
            params.tremoloDepth = values.tremoloDepth ?? params.tremoloDepth
        case .autoPan:
            params.autoPanRate = values.autoPanRate ?? params.autoPanRate
            params.autoPanDepth = values.autoPanDepth ?? params.autoPanDepth
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
        case .nightDrive:
            params.nightDriveIntensity = values.nightDriveIntensity ?? params.nightDriveIntensity
            params.nightDriveWidth = values.nightDriveWidth ?? params.nightDriveWidth
        case .chromePunch:
            params.chromePunchPunch = values.chromePunchPunch ?? params.chromePunchPunch
            params.chromePunchBody = values.chromePunchBody ?? params.chromePunchBody
        case .midnightGlow:
            params.midnightGlowGlow = values.midnightGlowGlow ?? params.midnightGlowGlow
            params.midnightGlowWarmth = values.midnightGlowWarmth ?? params.midnightGlowWarmth
        case .afterglow:
            params.afterglowAir = values.afterglowAir ?? params.afterglowAir
            params.afterglowSpace = values.afterglowSpace ?? params.afterglowSpace
        case .plugin:
            break
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
        // Enhancer
        var enhancerAmount: Double?

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
        var compressorThresholdDB: Double?
        var compressorRatio: Double?
        var compressorAttackMS: Double?
        var compressorReleaseMS: Double?
        var compressorMakeupDB: Double?
        var compressorMix: Double?


        // Reverb
        var reverbMix: Double?
        var reverbSize: Double?

        // Stereo Width
        var stereoWidthAmount: Double?

        // Delay
        var delayTime: Double?
        var delayFeedback: Double?
        var delayMix: Double?

        // Amp
        var ampInputGain: Double?
        var ampDrive: Double?
        var ampOutputGain: Double?
        var ampMix: Double?

        // Distortion
        var distortionDrive: Double?
        var distortionMix: Double?

        // Tremolo
        var tremoloRate: Double?
        var tremoloDepth: Double?

        // Auto Pan
        var autoPanRate: Double?
        var autoPanDepth: Double?

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

        // Signature effects
        var nightDriveIntensity: Double?
        var nightDriveWidth: Double?
        var chromePunchPunch: Double?
        var chromePunchBody: Double?
        var midnightGlowGlow: Double?
        var midnightGlowWarmth: Double?
        var afterglowAir: Double?
        var afterglowSpace: Double?
    }
}

// MARK: - Preset Manager

class PresetManager: ObservableObject {
    private static let starterSeedKey = "Sonexis.StarterPresets.v1Installed"
    @Published private(set) var presets: [SavedPreset] = []
    @Published var saveError: String?

    private let presetsFileURL: URL
    private let backupURL: URL
    private let writeData: (Data, URL) throws -> Void
    private var storageBlocked = false

    init(directory: URL? = nil,
         writeData: @escaping (Data, URL) throws -> Void = { data, url in
             try data.write(to: url, options: .atomic)
         }) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let base = directory ?? appSupport?.appendingPathComponent("Sonexis", isDirectory: true)
        // Never silently claim durable saves using temporary storage.
        let resolved = base ?? FileManager.default.temporaryDirectory.appendingPathComponent("Sonexis-unavailable")
        presetsFileURL = resolved.appendingPathComponent("presets.json")
        backupURL = resolved.appendingPathComponent("presets.backup.json")
        self.writeData = writeData
        guard base != nil else {
            storageBlocked = true
            saveError = "Preset storage is unavailable. Your current chain is still open but has not been saved."
            return
        }
        do {
            try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
            loadPresets()
            if let url = Bundle.main.url(forResource: "StarterPresets", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let starters = try? JSONDecoder().decode([SavedPreset].self, from: data) {
                installStarterPresetsIfNeeded(starters, markerKey: Self.starterSeedKey)
            }
        } catch {
            storageBlocked = true
            saveError = "Unable to open preset storage: \(error.localizedDescription). Existing files have not been changed."
        }
    }

    func installStarterPresetsIfNeeded(_ starters: [SavedPreset], markerKey: String) {
        guard !storageBlocked, !UserDefaults.standard.bool(forKey: markerKey), !starters.isEmpty else { return }
        var candidate = presets.filter { $0.name != "Skanda's Dream Space" }
        var changed = candidate.count != presets.count

        for starter in starters.reversed() {
            if let index = candidate.firstIndex(where: { $0.id == starter.id }) {
                let existing = candidate[index]
                candidate[index] = SavedPreset(id: existing.id, name: starter.name,
                    graph: starter.graph, createdDate: existing.createdDate)
                changed = true
            } else if !candidate.contains(where: {
                $0.name.caseInsensitiveCompare(starter.name) == .orderedSame
            }) {
                candidate.insert(starter, at: 0)
                changed = true
            }
        }

        guard !changed || persistPresets(candidate) else { return }
        UserDefaults.standard.set(true, forKey: markerKey)
    }

    @discardableResult
    func savePreset(name: String, graph: GraphSnapshot) -> SavedPreset? {
        let preset = SavedPreset(name: name, graph: graph)
        return persistPresets([preset] + presets) ? preset : nil
    }

    @discardableResult
    func deletePreset(_ preset: SavedPreset) -> Bool {
        persistPresets(presets.filter { $0.id != preset.id })
    }

    @discardableResult
    func updatePreset(id: UUID, graph: GraphSnapshot) -> Bool {
        guard let index = presets.firstIndex(where: { $0.id == id }) else {
            saveError = "This preset no longer exists. Use Save As to save your current chain."
            return false
        }
        var candidate = presets
        let existing = candidate[index]
        candidate[index] = SavedPreset(id: existing.id, name: existing.name, graph: graph, createdDate: existing.createdDate)
        return persistPresets(candidate)
    }

    @discardableResult
    func renamePreset(id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveError = "Enter a preset name."
            return false
        }
        guard let index = presets.firstIndex(where: { $0.id == id }) else {
            saveError = "This preset no longer exists."
            return false
        }
        guard !presets.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            saveError = "A preset with that name already exists. Choose a different name."
            return false
        }
        var candidate = presets
        let existing = candidate[index]
        candidate[index] = SavedPreset(id: existing.id, name: trimmed,
            graph: existing.graph, createdDate: existing.createdDate)
        return persistPresets(candidate)
    }

    @discardableResult
    func addPreset(_ preset: SavedPreset, overwriteExistingNamed name: String? = nil) -> Bool {
        var candidate = presets
        var finalPreset = preset
        if let name, let existing = candidate.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            candidate.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            // Retain library identity so replacing an active preset does not orphan it.
            finalPreset = SavedPreset(id: existing.id, name: preset.name,
                graph: preset.graph, createdDate: existing.createdDate)
        }
        if candidate.contains(where: { $0.id == finalPreset.id }) {
            finalPreset = SavedPreset(id: UUID(), name: finalPreset.name, graph: finalPreset.graph, createdDate: finalPreset.createdDate)
        }
        candidate.insert(finalPreset, at: 0)
        return persistPresets(candidate)
    }

    private func persistPresets(_ candidate: [SavedPreset]) -> Bool {
        guard !storageBlocked else {
            saveError = "Saving is paused because preset storage could not be safely read or preserved. Your current chain is still open. Fix the storage problem and reopen Sonexis before saving."
            return false
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(candidate)
            // Preserve the last committed library before replacing it. On first save,
            // create a recovery copy of the new library instead of an empty backup.
            let previous = try encoder.encode(presets.isEmpty && !FileManager.default.fileExists(atPath: presetsFileURL.path) ? candidate : presets)
            try writeData(previous, backupURL)
            try writeData(data, presetsFileURL)
            presets = candidate
            saveError = nil
            return true
        } catch {
            saveError = "Preset changes were not saved: \(error.localizedDescription). Your current chain is still open; try saving again."
            return false
        }
    }

    private func loadPresets() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: presetsFileURL.path) else {
            if fm.fileExists(atPath: backupURL.path) {
                recoverBackup(originalMessage: "The preset library is missing.")
            }
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: presetsFileURL)
        } catch {
            storageBlocked = true
            saveError = "The preset library could not be read: \(error.localizedDescription). Saving is paused to protect it."
            return
        }
        do {
            presets = try JSONDecoder().decode([SavedPreset].self, from: data)
            presets.sort { $0.createdDate > $1.createdDate }
        } catch {
            // Preserve the exact original bytes before any future save can replace them.
            let archive = presetsFileURL.deletingLastPathComponent()
                .appendingPathComponent("presets-unreadable-\(UUID().uuidString).json")
            do {
                try writeData(data, archive)
            } catch {
                storageBlocked = true
                saveError = "The preset library is unreadable and could not be preserved. Saving is paused to protect the original file."
                return
            }
            recoverBackup(originalMessage: "The unreadable library was preserved as \(archive.lastPathComponent).")
        }
    }

    private func recoverBackup(originalMessage: String) {
        do {
            let data = try Data(contentsOf: backupURL)
            presets = try JSONDecoder().decode([SavedPreset].self, from: data)
            presets.sort { $0.createdDate > $1.createdDate }
            saveError = "\(originalMessage) Recovered the last backup; the most recent changes may be missing. The recovered library will be written when you next save."
        } catch {
            storageBlocked = true
            saveError = "\(originalMessage) No readable backup is available. Saving is paused to prevent replacing recoverable data. Restore presets.json from a valid copy in Application Support/Sonexis, then reopen Sonexis. Your current chain remains available."
        }
    }
}
