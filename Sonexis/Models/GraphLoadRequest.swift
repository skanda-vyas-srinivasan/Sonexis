import Foundation

enum GraphLoadMode {
    case visualOnly
    case audioAndVisual
}

struct GraphLoadRequest {
    let id = UUID()
    let snapshot: GraphSnapshot
    let mode: GraphLoadMode
    let reason: String
}
