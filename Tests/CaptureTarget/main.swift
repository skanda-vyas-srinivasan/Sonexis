import Foundation
import CoreAudio
@testable import Sonexis

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
let target = AudioCaptureTarget(bundleID: "com.example.music", name: "Music", bundlePath: "/Applications/Music.app")
expect(target.contains(bundleID: target.bundleID, bundlePath: nil), "Match stable bundle identity after relaunch")
expect(target.contains(bundleID: "com.example.helper", bundlePath: "/Applications/Music.app/Contents/Frameworks/Audio Helper.app"), "Include embedded audio helper")
expect(!target.contains(bundleID: "com.example.music.other", bundlePath: "/Applications/Other.app"), "Do not capture apps sharing a bundle prefix")
expect(!target.contains(bundleID: "other", bundlePath: "/Applications/Music.app.backup/Contents/Helper.app"), "Require exact app directory boundary")
let restored = try JSONDecoder().decode(AudioCaptureTarget.self, from: JSONEncoder().encode(target))
expect(restored == target, "Persist identity and name without process IDs")
let description = CATapDescription(excludingProcesses: [99], deviceUID: "offline-test", stream: 0)
TapCaptureEngine.configureSelection(description, selectedProcesses: nil, ownProcessID: 99)
expect(description.isExclusive && description.processes == [99], "All audio must exclude Sonexis")
TapCaptureEngine.configureSelection(description, selectedProcesses: [11, 99, 0, 11, 12], ownProcessID: 99)
expect(!description.isExclusive && description.processes == [11, 12], "Selected apps must never include self or invalid IDs")
TapCaptureEngine.configureSelection(description, selectedProcesses: [], ownProcessID: 99)
expect(!description.isExclusive && description.processes.isEmpty, "Closed/silent app must not become global audio")
TapCaptureEngine.configureSelection(description, selectedProcesses: [21], ownProcessID: 99)
expect(!description.isExclusive && description.processes == [21], "Relaunched app replaces old process IDs")
TapCaptureEngine.configureSelection(description, selectedProcesses: nil, ownProcessID: 99)
expect(description.isExclusive && description.processes == [99], "Switch back to All audio restores self exclusion")
expect(description.deviceUID == "offline-test", "Selection changes preserve output route")
print("PASS: app identity, embedded helpers, persistence, all/app/empty/relaunch selection, self-exclusion, route preservation")

for selection: [AudioObjectID]? in [nil, [], [11, 12]] {
    let fresh = TapCaptureEngine.makeDescription(sourceDeviceUID: "offline-route", ownProcessID: 99,
                                                 selectedProcesses: selection)
    expect(fresh.isExclusive == (selection == nil), "Fresh tap must start in requested inclusion mode")
    expect(fresh.processes == (selection ?? [99]), "Fresh tap must start with requested processes")
    expect(fresh.deviceUID == "offline-route", "Fresh tap must retain the selected output device")
}
print("PASS: fresh tap constructors for all audio, selected app, and absent app")

expect(target.contains(bundleID: "com.example.music.helper", bundlePath: nil,
                       executablePath: "/Applications/Music.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"),
       "Headless audio helper must match by executable when NSRunningApplication has no bundle")
expect(!target.contains(bundleID: "com.example.music.helper", bundlePath: nil,
                        executablePath: "/Applications/Other.app/Contents/MacOS/Helper"),
       "Helper bundle ID alone must not include another app")
expect(!target.contains(bundleID: "com.example.music.helper", bundlePath: nil, executablePath: nil),
       "Unavailable helper identity must not broaden capture")
print("PASS: headless audio helper executable fallback and unrelated helper exclusion")

let safari = AudioCaptureTarget(bundleID: "com.apple.Safari", name: "Safari", bundlePath: "/Applications/Safari.app")
expect(safari.containsOwnedHelper(isRegularApplication: false, responsibleBundleID: safari.bundleID),
       "Safari must include its owned headless helper outside its bundle")
expect(!safari.containsOwnedHelper(isRegularApplication: false, responsibleBundleID: "com.apple.mail"),
       "Safari must not capture another app's helper")
expect(!safari.containsOwnedHelper(isRegularApplication: false, responsibleBundleID: nil),
       "Unavailable ownership must not broaden capture")
expect(!safari.containsOwnedHelper(isRegularApplication: true, responsibleBundleID: safari.bundleID),
       "Launching another regular app must not assign its audio to Safari")
expect(target.containsOwnedHelper(isRegularApplication: false, responsibleBundleID: target.bundleID),
       "An arbitrary app must include its owned helper without an app or framework allowlist")
expect(!target.containsOwnedHelper(isRegularApplication: false, responsibleBundleID: target.bundleID + ".other"),
       "Ownership requires exact app identity")
expect(!target.containsOwnedHelper(isRegularApplication: false, responsibleBundleID: ""),
       "Empty owner identity must not broaden capture")
print("PASS: generic helper ownership, other-app exclusion, missing ownership, and regular-app exclusion")
