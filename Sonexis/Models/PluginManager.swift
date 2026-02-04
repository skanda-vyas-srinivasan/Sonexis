import AppKit
import AVFoundation
import AudioToolbox
import Foundation

final class PluginManager: ObservableObject {
    @Published private(set) var plugins: [PluginDescriptor] = []
    @Published private(set) var isScanning = false
    @Published var scanError: String?
    @Published private(set) var customFolders: [URL] = []

    private let debugLogAUScan = true
    private let customFoldersKey = "pluginCustomFolders"
    private let scanQueue = DispatchQueue(label: "Sonexis.PluginScan", qos: .userInitiated)

    init() {
        customFolders = loadCustomFolders()
        scanPlugins()
    }

    func scanPlugins() {
        guard !isScanning else { return }
        isScanning = true
        scanError = nil

        scanQueue.async { [weak self] in
            guard let self else { return }
            let auPlugins = self.scanAudioUnits()
            let vst3Plugins = self.scanVST3Bundles()
            let combined = (auPlugins + vst3Plugins)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                self.plugins = combined
                self.isScanning = false
            }
        }
    }

    func addCustomFolder(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !customFolders.contains(standardized) else { return }
        customFolders.append(standardized)
        persistCustomFolders()
        scanPlugins()
    }

    func removeCustomFolder(_ url: URL) {
        let standardized = url.standardizedFileURL
        customFolders.removeAll { $0 == standardized }
        persistCustomFolders()
        scanPlugins()
    }

    func promptAddFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add Plugin Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.addCustomFolder(url)
        }
    }

    private func loadCustomFolders() -> [URL] {
        guard let data = UserDefaults.standard.data(forKey: customFoldersKey) else { return [] }
        guard let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    private func persistCustomFolders() {
        let paths = customFolders.map { $0.path }
        if let data = try? JSONEncoder().encode(paths) {
            UserDefaults.standard.set(data, forKey: customFoldersKey)
        }
    }

    private func scanAudioUnits() -> [PluginDescriptor] {
        let manager = AVAudioUnitComponentManager.shared()
        let effectDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let musicEffectDesc = AudioComponentDescription(
            componentType: kAudioUnitType_MusicEffect,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        let components = manager.components(matching: effectDesc) + manager.components(matching: musicEffectDesc)
        var seen = Set<String>()
        var results: [PluginDescriptor] = []

        if debugLogAUScan {
            print("AU Scan: found \(components.count) components")
        }
        for component in components {
            let desc = component.audioComponentDescription
            if debugLogAUScan {
                let url = component.componentURL?.path ?? "(no url)"
                print("AU: name=\(component.name) type=\(desc.componentType) subtype=\(desc.componentSubType) manu=\(desc.componentManufacturer) url=\(url)")
            }
            let key = "\(desc.componentType)-\(desc.componentSubType)-\(desc.componentManufacturer)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let identifier = key
            results.append(PluginDescriptor(
                format: .au,
                identifier: identifier,
                name: component.name,
                vendor: component.manufacturerName,
                componentType: desc.componentType,
                componentSubType: desc.componentSubType,
                componentManufacturer: desc.componentManufacturer,
                location: component.componentURL
            ))
        }
        return results
    }

    private func scanVST3Bundles() -> [PluginDescriptor] {
        let standardPaths = [
            URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Audio/Plug-Ins/VST3")
        ]
        let allPaths = standardPaths + customFolders
        var plugins: [PluginDescriptor] = []
        var seen = Set<String>()

        for folder in allPaths {
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() != "vst3" {
                    continue
                }
                enumerator.skipDescendants()
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier ?? url.path
                if seen.contains(bundleID) { continue }
                seen.insert(bundleID)

                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let vendor = (bundle?.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String) ?? "Unknown Vendor"

                let descriptor = PluginDescriptor(
                    format: .vst3,
                    identifier: bundleID,
                    name: name,
                    vendor: vendor,
                    location: url
                )
                plugins.append(descriptor)
            }
        }

        return plugins
    }
}
