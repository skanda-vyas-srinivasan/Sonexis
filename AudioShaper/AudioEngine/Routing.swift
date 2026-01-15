import AVFoundation
import CoreAudio
import Foundation

extension AudioEngine {
    func systemDefaultInputDeviceName() -> String? {
        guard let deviceID = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice),
              let device = AudioDevice(id: deviceID) else {
            return nil
        }
        return device.name
    }

    func systemDefaultOutputDeviceName() -> String? {
        guard let deviceID = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice),
              let device = AudioDevice(id: deviceID) else {
            return nil
        }
        return device.name
    }

    func systemDefaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else { return nil }
        return deviceID
    }

    @discardableResult
    func refreshSetupStatus() -> Bool {
        let inputName = systemDefaultInputDeviceName()
        let outputName = systemDefaultOutputDeviceName()
        let ready = (inputName?.localizedCaseInsensitiveContains("BlackHole") == true) &&
            (outputName?.localizedCaseInsensitiveContains("BlackHole") == true)
        if setupReady != ready {
            DispatchQueue.main.async {
                self.setupReady = ready
            }
        }
        return ready
    }

    func findBlackHoleDeviceID() -> AudioDeviceID? {
        if let device = findDevice(matching: "BlackHole") {
            return device.id
        }
        return nil
    }

    func setSystemDefaultInputDevice(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Check if property is settable
        var isSettable: DarwinBoolean = false
        var status = AudioObjectIsPropertySettable(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            &isSettable
        )

        if status != noErr || !isSettable.boolValue {
            return false
        }

        var deviceIDCopy = deviceID
        status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceIDCopy
        )

        return status == noErr
    }

    func setSystemDefaultOutputDevice(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Check if property is settable
        var isSettable: DarwinBoolean = false
        var status = AudioObjectIsPropertySettable(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            &isSettable
        )

        if status != noErr || !isSettable.boolValue {
            return false
        }

        var deviceIDCopy = deviceID
        status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceIDCopy
        )

        return status == noErr
    }

    @discardableResult
    func switchSystemAudioToBlackHole() async -> Bool {
        guard let blackHoleID = findBlackHoleDeviceID() else {
            return false
        }

        // Save current devices before switching
        originalInputDeviceID = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        originalOutputDeviceID = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)

        let inputSuccess = setSystemDefaultInputDevice(deviceID: blackHoleID)
        let outputSuccess = setSystemDefaultOutputDevice(deviceID: blackHoleID)

        // Let the system process the changes without blocking UI
        try? await Task.sleep(nanoseconds: 500_000_000)

        return inputSuccess && outputSuccess
    }

    @discardableResult
    func restoreOriginalAudioDevices() async -> Bool {
        var success = true

        if let originalInput = originalInputDeviceID {
            success = setSystemDefaultInputDevice(deviceID: originalInput) && success
        }

        if let originalOutput = originalOutputDeviceID {
            success = setSystemDefaultOutputDevice(deviceID: originalOutput) && success
        }

        // Let the system process the changes without blocking UI
        try? await Task.sleep(nanoseconds: 500_000_000)

        return success
    }

    func startSetupMonitor() {
        guard setupMonitorTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let ready = self.refreshSetupStatus()
            if !ready && self.isRunning {
                DispatchQueue.main.async {
                    self.errorMessage = "Audio routing was changed. Stopped to restore your original audio setup."
                    self.stop()
                }
            }
        }
        setupMonitorTimer = timer
        timer.resume()
    }

    func stopSetupMonitor() {
        setupMonitorTimer?.cancel()
        setupMonitorTimer = nil
    }

    func findDevice(matching name: String) -> AudioDevice? {
        let devices = getAllAudioDevices()
        return devices.first { $0.name.contains(name) }
    }

    func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return nil }

        var uid: CFString = "" as CFString
        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uid
        )

        guard status == noErr else { return nil }
        return uid as String
    }

    func getOutputDeviceVolume(deviceID: AudioDeviceID) -> Float {
        var volume: Float = 1.0
        var size = UInt32(MemoryLayout<Float>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &volume
        )

        if status == noErr {
            return volume
        }

        // Fallback to reading first channel volume when virtual master isn't supported.
        var channelAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )

        status = AudioObjectGetPropertyData(
            deviceID,
            &channelAddress,
            0,
            nil,
            &size,
            &volume
        )

        return status == noErr ? volume : 1.0
    }

    func setOutputDeviceVolume(deviceID: AudioDeviceID, volume: Float) {
        var vol = volume
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float>.size),
            &vol
        )

        if status == noErr {
            // Debug output removed.
            return
        }

        // Fallback to per-channel volume when virtual master isn't supported.
        for channel in 1...2 {
            var channelAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(channel)
            )
            var channelVol = volume
            status = AudioObjectSetPropertyData(
                deviceID,
                &channelAddress,
                0,
                nil,
                UInt32(MemoryLayout<Float>.size),
                &channelVol
            )
        }

        if status == noErr {
            // Debug output removed.
        } else {
            // Debug output removed.
        }
    }

    func findRealOutputDevice() -> AudioDevice? {
        let devices = getAllAudioDevices()

        // Filter to output devices only
        let outputDevices = devices.filter { $0.hasOutput }

        // Exclude virtual devices (BlackHole, Multi-Output, Aggregate)
        let realDevices = outputDevices.filter { device in
            !device.name.contains("BlackHole") &&
            !device.name.contains("Multi-Output") &&
            !device.name.contains("Aggregate")
        }

        // Prefer built-in devices (MacBook speakers, headphone jack)
        if let builtIn = realDevices.first(where: { $0.name.contains("Built-in") || $0.name.contains("MacBook") }) {
            return builtIn
        }

        // Otherwise return first real device
        return realDevices.first
    }

    func getAllAudioDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            AudioDevice(id: deviceID)
        }
    }

    func refreshOutputDevices() {
        let devices = getAllAudioDevices().filter { $0.hasOutput }
        outputDevices = devices

        if selectedOutputDeviceID == nil {
            selectedOutputDeviceID = findRealOutputDevice()?.id
        }
    }
}

// MARK: - Audio Device Helper

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let hasInput: Bool
    let hasOutput: Bool

    init?(id: AudioDeviceID) {
        self.id = id
        self.name = AudioDevice.getDeviceName(id: id) ?? "Unknown Device"
        self.hasInput = AudioDevice.deviceHasStreams(id: id, scope: kAudioDevicePropertyScopeInput)
        self.hasOutput = AudioDevice.deviceHasStreams(id: id, scope: kAudioDevicePropertyScopeOutput)
    }

    private static func getDeviceName(id: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0

        // First get the size
        var status = AudioObjectGetPropertyDataSize(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            return nil
        }

        // Now get the actual data
        var name: CFString = "" as CFString
        status = AudioObjectGetPropertyData(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr else {
            return nil
        }

        return name as String
    }

    private static func deviceHasStreams(id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }
}

// MARK: - AUAudioUnit Extension for Device Selection

extension AUAudioUnit {
    func setDeviceID(_ deviceID: AudioDeviceID) throws {
        let deviceIDValue = deviceID as NSNumber
        setValue(deviceIDValue, forKey: "deviceID")
    }
}
