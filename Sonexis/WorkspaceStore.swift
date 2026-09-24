import Combine
import Foundation

/// Recovery data is independent of the named preset library. Running/recording
/// state is deliberately absent: restoring a workspace never starts audio.
struct WorkspaceSnapshot: Codable {
    var version = 1
    var graph: GraphSnapshot
    var presetID: UUID?
    var inputTrimDB: Double
    var outputMakeupDB: Double
    var outputCeilingEnabled: Bool
    var effectsEnabled: Bool
}

final class WorkspaceStore: ObservableObject {
    @Published var issue: String?
    @Published private(set) var recoveryRequired = false
    let directory: URL
    private let fileURL: URL
    private let backupURL: URL
    private let queue = DispatchQueue(label: "Sonexis.WorkspaceStorage", qos: .utility)
    private let writeData: (Data, URL) throws -> Void
    // Main-thread debounce state.
    private var pending: WorkspaceSnapshot?
    private var scheduledWrite: DispatchWorkItem?
    // Access only on queue.
    private var blocked = false
    private var lastGoodData: Data?

    init(directory: URL? = nil,
         writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("Sonexis", isDirectory: true)
        fileURL = self.directory.appendingPathComponent("workspace.json")
        backupURL = self.directory.appendingPathComponent("workspace.backup.json")
        self.writeData = writeData
    }

    private enum RecoveryError: LocalizedError {
        case unsupportedVersion, invalidGraph
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return "This workspace was saved by a different version of Sonexis."
            case .invalidGraph: return "The workspace graph is incomplete or invalid."
            }
        }
    }

    private func decode(_ data: Data) throws -> WorkspaceSnapshot {
        struct Header: Decodable { let version: Int }
        guard try JSONDecoder().decode(Header.self, from: data).version == 1 else {
            throw RecoveryError.unsupportedVersion
        }
        // GraphSnapshot intentionally accepts old preset fields. Workspace v1
        // must be complete so truncated objects cannot become an empty canvas.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let graph = object?["graph"] as? [String: Any],
              ["graphMode", "wiringMode", "autoConnectEnd", "nodes", "connections",
               "autoGainOverrides", "startNodeID", "endNodeID", "hasNodeParameters"]
                .allSatisfy({ graph[$0] != nil }) else { throw RecoveryError.invalidGraph }
        var result = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
        let nodes = result.graph.nodes
        var ids = nodes.map(\.id) + [result.graph.startNodeID, result.graph.endNodeID]
        ids += [result.graph.leftStartNodeID, result.graph.leftEndNodeID,
                result.graph.rightStartNodeID, result.graph.rightEndNodeID].compactMap { $0 }
        let gains = result.graph.autoGainOverrides.map { "\($0.fromNodeId):\($0.toNodeId)" }
        guard Set(ids).count == ids.count, Set(gains).count == gains.count,
              nodes.allSatisfy({ $0.position.x.isFinite && $0.position.y.isFinite }) else {
            throw RecoveryError.invalidGraph
        }
        result.graph = try result.graph.validatedForProcessing()
        return result
    }

    func restore() -> WorkspaceSnapshot? {
        let result: (WorkspaceSnapshot?, String?, Bool) = queue.sync {
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let data = try Data(contentsOf: fileURL)
                    let snapshot = try decode(data)
                    lastGoodData = data
                    blocked = false
                    return (snapshot, nil, false)
                }
                if !FileManager.default.fileExists(atPath: backupURL.path) {
                    blocked = false
                    return (nil, nil, false)
                }
            } catch RecoveryError.unsupportedVersion {
                blocked = true
                return (nil, "This workspace needs a different version of Sonexis. The original files are preserved and autosave is paused.", true)
            } catch {
                // Try the previous complete workspace below.
            }
            do {
                let data = try Data(contentsOf: backupURL)
                let snapshot = try decode(data)
                try archive(fileURL)
                try writeData(data, fileURL)
                lastGoodData = data
                blocked = false
                return (snapshot, "Recovered the previous workspace from its backup. The unreadable original, if present, was preserved in the recovery folder. Recent edits may be missing.", false)
            } catch {
                blocked = true
                return (nil, "Your workspace could not be restored. Its files are preserved and autosave is paused. You can retry after restoring a valid workspace.json, or start fresh while keeping recovery copies.", true)
            }
        }
        issue = result.1
        recoveryRequired = result.2
        return result.0
    }

    /// Repeated unchanged captures do not touch disk. Debouncing stays on the
    /// main queue; encoding and atomic writes run on the storage queue.
    func schedule(_ snapshot: WorkspaceSnapshot) {
        guard !recoveryRequired else { return }
        pending = snapshot
        scheduledWrite?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.submitPending() }
        scheduledWrite = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    private func submitPending() {
        scheduledWrite = nil
        guard let snapshot = pending else { return }
        pending = nil
        queue.async { [self] in
            let error = persist(snapshot)
            DispatchQueue.main.async { [weak self] in
                if let error { self?.issue = error }
            }
        }
    }

    /// Finish the latest edit on normal quit/window close without waiting for
    /// the debounce timer. Never called from the audio worker.
    func flush() {
        scheduledWrite?.cancel()
        scheduledWrite = nil
        let snapshot = pending
        pending = nil
        let error = queue.sync { snapshot.map { persist($0) } ?? nil }
        if let error { issue = error }
    }

    private func persist(_ snapshot: WorkspaceSnapshot) -> String? {
        guard !blocked else { return nil }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            _ = try decode(data)
            guard data != lastGoodData else { return nil }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let lastGoodData { try writeData(lastGoodData, backupURL) }
            try writeData(data, fileURL)
            lastGoodData = data
            return nil
        } catch {
            return "Workspace autosave failed: \(error.localizedDescription) Your last successful recovery copy is preserved. Named presets are unaffected."
        }
    }

    private func archive(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let recovery = directory.appendingPathComponent("Workspace Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url,
            to: recovery.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)"))
    }

    /// User-selected recovery action: archive both originals before starting
    /// a separate workspace. If preservation fails, saving remains blocked.
    func startFresh() -> Bool {
        let error: String? = queue.sync {
            do {
                try archive(fileURL)
                try archive(backupURL)
                for url in [fileURL, backupURL] where FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                lastGoodData = nil
                blocked = false
                return nil
            } catch { return "Could not preserve the recovery files: \(error.localizedDescription) Autosave remains paused." }
        }
        if let error { issue = error; return false }
        recoveryRequired = false
        issue = nil
        return true
    }
}
