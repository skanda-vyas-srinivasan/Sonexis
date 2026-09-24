import AppKit
import Combine
import CoreAudio
import SwiftUI

struct AudioCaptureTarget: Codable, Equatable, Identifiable {
    let bundleID: String
    let name: String
    let bundlePath: String
    var id: String { bundleID }
    static let storageKey = "Sonexis.AudioCaptureTarget"

    static func restore() -> AudioCaptureTarget? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let target = try? JSONDecoder().decode(Self.self, from: data),
              target.bundleID != Bundle.main.bundleIdentifier else { return nil }
        return target
    }

    static func runningApps() -> [Self] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let id = app.bundleIdentifier, let url = app.bundleURL,
                  seen.insert(id).inserted else { return nil }
            return Self(bundleID: id, name: app.localizedName ?? id, bundlePath: url.path)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func contains(bundleID processBundleID: String, bundlePath processPath: String?, executablePath: String? = nil) -> Bool {
        if processBundleID == bundleID { return true }
        // Include embedded audio helpers, without matching unrelated bundle-ID prefixes.
        let embeddedPrefix = bundlePath + "/Contents/"
        return [processPath, executablePath].compactMap { $0 }.contains { $0.hasPrefix(embeddedPrefix) }
    }

    func containsOwnedHelper(isRegularApplication: Bool, responsibleBundleID: String?) -> Bool {
        // Responsibility also follows app launches. A separately launchable app
        // must retain its own audio even when another app launched it.
        guard !isRegularApplication, let responsibleBundleID,
              !responsibleBundleID.isEmpty else { return false }
        return responsibleBundleID == bundleID
    }

    func processObjectIDs(excluding ownID: AudioObjectID) throws -> [AudioObjectID] {
        let objects = try CoreAudioSupport.readAudioObjectIDArray(
            objectID: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyProcessObjectList,
            operation: "Read audio processes")
        return objects.filter { object in
            guard object != ownID,
                  let pid: pid_t = try? CoreAudioSupport.readScalar(objectID: object,
                    selector: kAudioProcessPropertyPID, defaultValue: pid_t(0), operation: "Read audio process PID"),
                  pid != ProcessInfo.processInfo.processIdentifier else { return false }
            let app = NSRunningApplication(processIdentifier: pid)
            let id = (try? CoreAudioSupport.readString(objectID: object,
                selector: kAudioProcessPropertyBundleID, operation: "Read audio process bundle")) ?? app?.bundleIdentifier ?? ""
            if contains(bundleID: id, bundlePath: app?.bundleURL?.path) { return true }
            // Headless/sandboxed audio helpers may not be represented by
            // NSRunningApplication. Resolve their executable without trusting
            // a bundle-ID prefix, which could include a different app.
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = proc_pidpath(pid, &path, UInt32(path.count))
            let executable = length > 0 ? String(cString: path) : nil
            if contains(bundleID: id, bundlePath: nil, executablePath: executable) { return true }
            guard app?.activationPolicy != .regular else { return false }
            return containsOwnedHelper(isRegularApplication: false,
                responsibleBundleID: ProcessResponsibility.bundleID(for: pid))
        }.sorted()
    }
}

/// Shared helpers can live outside their client app's bundle and have launchd
/// as their Unix parent. This optional private macOS SPI identifies the
/// responsible application. Resolve dynamically: unavailable/failed attribution
/// must never broaden an app's capture to unrelated processes.
private enum ProcessResponsibility {
    typealias Lookup = @convention(c) (pid_t) -> pid_t
    private static let lookup: Lookup? = {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: Lookup.self)
    }()

    static func bundleID(for pid: pid_t) -> String? {
        guard let lookup else { return nil }
        let owner = lookup(pid)
        guard owner > 1, owner != pid, owner != ProcessInfo.processInfo.processIdentifier else { return nil }
        return NSRunningApplication(processIdentifier: owner)?.bundleIdentifier
    }
}

extension AudioEngine {
    func selectCaptureTarget(_ target: AudioCaptureTarget?) {
        guard target != captureTarget else { return }
        do {
            try processTapEngine?.setCaptureTarget(target)
            captureTarget = target
            if let target {
                UserDefaults.standard.set(try JSONEncoder().encode(target), forKey: AudioCaptureTarget.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AudioCaptureTarget.storageKey)
            }
            inputDeviceName = target?.name ?? "System Audio"
            errorMessage = nil
        } catch {
            errorMessage = "Could not change audio source: \(error)"
        }
    }
}

struct CaptureTargetMenu: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var apps = AudioCaptureTarget.runningApps()
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Menu {
            Button {
                audioEngine.selectCaptureTarget(nil)
            } label: {
                if audioEngine.captureTarget == nil { Label("All audio", systemImage: "checkmark") }
                else { Text("All audio") }
            }
            Divider()
            if let selected = audioEngine.captureTarget, !apps.contains(where: { $0.id == selected.id }) {
                Text("\(selected.name) — not running")
            }
            ForEach(apps) { app in
                Button {
                    audioEngine.selectCaptureTarget(app)
                } label: {
                    if audioEngine.captureTarget?.id == app.id { Label(app.name, systemImage: "checkmark") }
                    else { Text(app.name) }
                }
            }
            if apps.isEmpty { Text("Open an app to select it") }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apply effects to").font(.system(size: 9)).foregroundStyle(AppColors.textMuted)
                    Text(audioEngine.captureTarget?.name ?? "All audio")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(AppColors.neonPink)
            }
            .frame(width: 140, height: 32)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onReceive(refresh) { _ in apps = AudioCaptureTarget.runningApps() }
    }
}
