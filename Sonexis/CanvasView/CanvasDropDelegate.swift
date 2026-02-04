import SwiftUI

// MARK: - Canvas Drop Delegate

struct CanvasDropDelegate: DropDelegate {
    @Binding var effectChain: [BeginnerNode]
    @Binding var draggedEffectType: EffectType?
    @Binding var draggedPlugin: PluginDescriptor?
    let canvasSize: CGSize
    let graphMode: GraphMode
    let laneProvider: (CGPoint) -> GraphLane
    let onAdd: (BeginnerNode) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func performDrop(info: DropInfo) -> Bool {
        let lane = graphMode == .split ? laneProvider(info.location) : .left
        let location = clamp(info.location, to: canvasSize, lane: graphMode == .split ? lane : nil)
        if let plugin = draggedPlugin {
            let node = BeginnerNode(
                type: .plugin,
                position: location,
                lane: lane,
                plugin: plugin.toReference()
            )
            onAdd(node)
            draggedPlugin = nil
            return true
        }
        guard let effectType = draggedEffectType else { return false }
        onAdd(BeginnerNode(type: effectType, position: location, lane: lane))
        draggedEffectType = nil
        return true
    }

    private func clamp(_ point: CGPoint, to size: CGSize, lane: GraphLane?) -> CGPoint {
        let padding: CGFloat = 80
        let x: CGFloat
        if let lane {
            let midX = size.width * 0.5
            let minX = lane == .left ? 0 : midX
            let maxX = lane == .left ? midX : size.width
            x = min(max(point.x, minX + padding), max(maxX - padding, minX + padding))
        } else {
            x = min(max(point.x, padding), max(size.width - padding, padding))
        }
        let y = min(max(point.y, padding), max(size.height - padding, padding))
        return CGPoint(x: x, y: y)
    }
}
