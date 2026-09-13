import AppKit

extension AudioEngine {
    func openPluginEditor(for nodeId: UUID, fallbackView: NSView? = nil) {
        pluginHost.openEditor(for: nodeId, fallbackView: fallbackView)
    }

    func pluginParameters(for nodeId: UUID) -> [PluginParameter] {
        pluginHost.instance(for: nodeId)?.parameters() ?? []
    }

    func setPluginParameter(for nodeId: UUID, parameterId: String, value: Double) {
        pluginHost.instance(for: nodeId)?.setParameter(id: parameterId, value: value)
    }

    func pluginStateData(for nodeId: UUID) -> Data? {
        pluginHost.stateData(for: nodeId)
    }

    func isPluginReady(_ nodeId: UUID) -> Bool {
        pluginHost.isReady(nodeId: nodeId)
    }
}
