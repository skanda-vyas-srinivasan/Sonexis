import AppKit
import Combine
import SwiftUI

struct ChainWorkspaceDocument: Codable {
    var version = 1
    var chains: [AudioChainDefinition]
    var selectedID: UUID
    var globalBypass: Bool
}

/// Separate file from the old workspace: migration never overwrites its source.
final class ChainWorkspaceStore {
    let directory: URL
    private let queue = DispatchQueue(label: "Sonexis.ChainWorkspace", qos: .utility)
    private var pending: DispatchWorkItem?
    private var pendingData: Data?
    private var lastData: Data?
    private var blocked = false
    var onError: ((String) -> Void)?
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sonexis")
    }
    private var file: URL { directory.appendingPathComponent("chains.json") }
    private var backup: URL { directory.appendingPathComponent("chains.backup.json") }

    private func decode(_ data: Data) throws -> ChainWorkspaceDocument {
        var document = try JSONDecoder().decode(ChainWorkspaceDocument.self, from: data)
        guard document.version == 1 else { throw SonexisError(message: "Unsupported chain workspace version") }
        _ = try AudioChainRoutingPlan(chains: document.chains, resolve: { _ in [] })
        for index in document.chains.indices {
            document.chains[index].graph = try document.chains[index].graph.validatedForProcessing()
        }
        guard document.chains.contains(where: { $0.id == document.selectedID }) else {
            throw SonexisError(message: "Selected chain is missing")
        }
        return document
    }

    func load() throws -> ChainWorkspaceDocument? {
        guard FileManager.default.fileExists(atPath: file.path) || FileManager.default.fileExists(atPath: backup.path) else { return nil }
        do {
            let data = try Data(contentsOf: file)
            let document = try decode(data)
            lastData = data
            return document
        } catch {
            // A future version must never be overwritten with an older backup.
            if let data = try? Data(contentsOf: file),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = object["version"] as? Int, version != 1 {
                blocked = true
                throw error
            }
            do {
                let data = try Data(contentsOf: backup)
                let document = try decode(data)
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.copyItem(at: file, to: directory.appendingPathComponent("chains-recovery-\(UUID().uuidString).json"))
                }
                try data.write(to: file, options: .atomic)
                lastData = data
                return document
            } catch {
                blocked = true
                throw SonexisError(message: "Chain workspace could not be restored. Original files are preserved; autosave is paused.")
            }
        }
    }

    func schedule(_ document: ChainWorkspaceDocument) {
        guard !blocked else { return }
        let data: Data
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            data = try encoder.encode(document)
        } catch { onError?(String(describing: error)); return }
        pending?.cancel()
        pendingData = data
        let item = DispatchWorkItem { [weak self] in self?.write(data) }
        pending = item
        queue.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func write(_ data: Data) {
        guard data != lastData else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let lastData { try lastData.write(to: backup, options: .atomic) }
            try data.write(to: file, options: .atomic)
            lastData = data
        } catch {
            DispatchQueue.main.async { self.onError?("Could not save chains: \(error)") }
        }
    }

    func flush() {
        pending?.cancel()
        pending = nil
        let data = pendingData
        pendingData = nil
        queue.sync { if let data { write(data) } }
    }

}
