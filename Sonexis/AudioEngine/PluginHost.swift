import AppKit
import Foundation

final class PluginHost {
    private var editorIDs: [UUID: UUID] = [:]
    private var instances: [UUID: PluginInstance] = [:]
    private var references: [UUID: PluginReference] = [:]
    private let lock = NSLock()
    private let debugLifecycle = true
    var onPluginReady: ((UUID) -> Void)?

    deinit {
        let ids = Array(editorIDs.values)
        DispatchQueue.main.async {
            for id in ids { PluginEditorWindowController.shared.closeWindow(for: id) }
        }
    }

    func sync(nodes: [BeginnerNode]) {
        let nodeIDs = Set(nodes.map(\.id))
        let removedEditors = editorIDs.filter { !nodeIDs.contains($0.key) }
        for (nodeID, editorID) in removedEditors {
            editorIDs.removeValue(forKey: nodeID)
            DispatchQueue.main.async { PluginEditorWindowController.shared.closeWindow(for: editorID) }
        }
        lock.lock()
        defer { lock.unlock() }
        let pluginNodes = nodes.filter { $0.type == .plugin && $0.plugin != nil }
        let nextReferences = Dictionary(
            uniqueKeysWithValues: pluginNodes.compactMap { node -> (UUID, PluginReference)? in
                guard let reference = node.plugin else { return nil }
                return (node.id, reference)
            }
        )
        let nodeIds = Set(nextReferences.keys)

        if references == nextReferences && nodeIds.allSatisfy({ instances[$0] != nil }) {
            if debugLifecycle, !nodeIds.isEmpty {
                print("PluginHost sync skipped: unchanged plugin nodes=\(nodeIds.count)")
            }
            return
        }

        let removedIds = Set(references.keys).subtracting(nodeIds)
        if debugLifecycle, !removedIds.isEmpty {
            print("PluginHost removing plugin instances: \(removedIds.map(\.uuidString).joined(separator: ", "))")
        }

        instances = instances.filter { nodeIds.contains($0.key) }
        references = references.filter { nodeIds.contains($0.key) }

        for node in pluginNodes {
            guard let reference = node.plugin else { continue }
            if let existingRef = references[node.id], existingRef == reference {
                continue
            }
            references[node.id] = reference
            if debugLifecycle {
                print("PluginHost creating plugin instance: node=\(node.id), name=\(reference.name)")
            }
            let instance = makeInstance(for: reference)
            if let auInstance = instance as? AUPluginInstance {
                auInstance.onReady = { [weak self] in
                    self?.onPluginReady?(node.id)
                }
            }
            instances[node.id] = instance
        }
    }

    func instance(for nodeId: UUID) -> PluginInstance? {
        lock.lock()
        defer { lock.unlock() }
        return instances[nodeId]
    }

    func isReady(nodeId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return instances[nodeId]?.isReady ?? false
    }

    func stateData(for nodeId: UUID) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return instances[nodeId]?.stateData()
    }

    func openEditor(for nodeId: UUID, fallbackView: NSView?) {
        let editorID = editorIDs[nodeId] ?? UUID()
        editorIDs[nodeId] = editorID
        if PluginEditorWindowController.shared.showExistingWindow(for: editorID) {
            return
        }
        lock.lock()
        let instance = instances[nodeId]
        lock.unlock()
        guard let instance else { return }
        if let auInstance = instance as? AUPluginInstance {
            if auInstance.reference.hasCustomView == false, let fallbackView {
                PluginEditorWindowController.shared.openWindow(for: editorID, title: instance.displayName, contentView: fallbackView)
                return
            }
            auInstance.requestEditor { view, controller in
                if let controller {
                    PluginEditorWindowController.shared.openWindow(for: editorID, title: instance.displayName, contentController: controller)
                    return
                }
                if let editorView = view ?? fallbackView {
                    PluginEditorWindowController.shared.openWindow(for: editorID, title: instance.displayName, contentView: editorView)
                    return
                }
                if let fallbackView {
                    PluginEditorWindowController.shared.openWindow(for: editorID, title: instance.displayName, contentView: fallbackView)
                }
            }
            return
        }

        if let editorView = instance.editorView() ?? fallbackView {
            PluginEditorWindowController.shared.openWindow(for: editorID, title: instance.displayName, contentView: editorView)
        }
    }

    private func makeInstance(for reference: PluginReference) -> PluginInstance {
        switch reference.format {
        case .au:
            return AUPluginInstance(reference: reference)
        case .vst3:
            return VST3PluginInstance(reference: reference)
        }
    }
}
