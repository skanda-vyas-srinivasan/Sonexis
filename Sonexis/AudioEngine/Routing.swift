import CoreAudio
import Foundation

extension AudioEngine {
    func startDeviceListMonitor() {
        guard deviceListMonitorListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.refreshOutputDevices()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.refreshOutputDevices()
            }
        }
        deviceListMonitorListener = listener

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            deviceListMonitorQueue,
            listener
        )
        if status != noErr {
            deviceListMonitorListener = nil
            startDeviceListMonitorTimer()
        }
    }

    func stopDeviceListMonitor() {
        if let listener = deviceListMonitorListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                deviceListMonitorQueue,
                listener
            )
            deviceListMonitorListener = nil
        }
        deviceListMonitorTimer?.cancel()
        deviceListMonitorTimer = nil
    }

    private func startDeviceListMonitorTimer() {
        guard deviceListMonitorTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.refreshOutputDevices()
            }
        }
        deviceListMonitorTimer = timer
        timer.resume()
    }

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
        if setupReady != true {
            DispatchQueue.main.async {
                self.setupReady = true
            }
        }
        return true
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

        var uid: CFString?
        status = withUnsafeMutablePointer(to: &uid) { uidPointer in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                uidPointer
            )
        }

        guard status == noErr, let uid else { return nil }
        return uid as String
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

        return deviceIDs.compactMap { AudioDevice(id: $0) }
    }

    func refreshOutputDevices() {
        let devices = getAllAudioDevices().filter { $0.hasOutput }
        outputDevices = devices

        if let defaultOutputID = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice),
           devices.contains(where: { $0.id == defaultOutputID }) {
            selectedOutputDeviceID = defaultOutputID
        } else if selectedOutputDeviceID == nil {
            selectedOutputDeviceID = devices.first?.id
        }
    }
}

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
        var status = AudioObjectGetPropertyDataSize(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return nil }

        var name: CFString?
        status = withUnsafeMutablePointer(to: &name) { namePointer in
            AudioObjectGetPropertyData(
                id,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                namePointer
            )
        }

        guard status == noErr, let name else { return nil }
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
