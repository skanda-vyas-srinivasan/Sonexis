import Foundation

// MARK: - Effect Chain

struct EffectChain: Identifiable, Codable {
    var id: UUID
    var name: String
    var blocks: [EffectBlock]
    var createdDate: Date
    var modifiedDate: Date

    init(name: String = "New Chain") {
        self.id = UUID()
        self.name = name
        self.blocks = []
        self.createdDate = Date()
        self.modifiedDate = Date()
    }

    mutating func updateModifiedDate() {
        self.modifiedDate = Date()
    }
}

