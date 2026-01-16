import Foundation

// MARK: - Project

struct Project: Codable {
    var id: UUID
    var name: String
    var chains: [EffectChain]
    var activeChainId: UUID?
    var userPresets: [Preset]
    var settings: ProjectSettings

    init(name: String = "Untitled Project") {
        self.id = UUID()
        self.name = name
        self.chains = [EffectChain(name: "Default Chain")]
        self.activeChainId = chains.first?.id
        self.userPresets = []
        self.settings = ProjectSettings()
    }
}

struct ProjectSettings: Codable {
    var masterVolume: Float
    var processingEnabled: Bool
    var autoGainEnabled: Bool

    init() {
        self.masterVolume = 1.0
        self.processingEnabled = false
        self.autoGainEnabled = true
    }
}
