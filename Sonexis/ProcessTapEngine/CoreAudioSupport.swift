import CoreAudio
import Foundation

struct CoreAudioError: Error, CustomStringConvertible {
    let operation: String
    let status: OSStatus

    var description: String {
        "\(operation) failed: \(status.osStatusDescription)"
    }
}

struct PrototypeError: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

struct NoDefaultOutputDeviceError: Error, CustomStringConvertible {
    var description: String {
        "No default output device is available"
    }
}

func checkOSStatus(_ status: OSStatus, operation: String) throws {
    guard status == noErr else {
        throw CoreAudioError(operation: operation, status: status)
    }
}

func printCleanupResult(_ label: String, status: OSStatus) {
    if status == noErr {
        print("Cleanup: \(label).")
    } else {
        print("Cleanup warning: \(label) returned \(status.osStatusDescription).")
    }
}

extension OSStatus {
    var osStatusDescription: String {
        let code = fourCharacterCode
        if code.isEmpty {
            return "\(self)"
        }
        return "\(self) ('\(code)')"
    }

    private var fourCharacterCode: String {
        let value = UInt32(bitPattern: self).bigEndian
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]

        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else {
            return ""
        }
        return String(bytes: bytes, encoding: .macOSRoman) ?? ""
    }
}

enum CoreAudioSupport {
    static func readScalar<T>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T,
        operation: String
    ) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        var value = defaultValue
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &value) { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }
            return AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                baseAddress
            )
        }
        try checkOSStatus(status, operation: operation)
        return value
    }

    static func readAudioObjectIDArray(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        operation: String
    ) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
        try checkOSStatus(status, operation: "\(operation) size")

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var values = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        status = values.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }
            return AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                baseAddress
            )
        }
        try checkOSStatus(status, operation: operation)
        return values
    }

    static func readString(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        operation: String
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutableBytes(of: &value) { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }
            return AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                baseAddress
            )
        }
        try checkOSStatus(status, operation: operation)

        guard let value else {
            throw PrototypeError(message: "\(operation) returned nil")
        }
        return value.takeRetainedValue() as String
    }

    static func defaultOutputDevice() throws -> AudioDeviceID {
        let deviceID: AudioDeviceID = try readScalar(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            defaultValue: kAudioObjectUnknown,
            operation: "Read default output device"
        )

        guard deviceID != kAudioObjectUnknown else {
            throw NoDefaultOutputDeviceError()
        }
        return deviceID
    }

    static func deviceName(_ deviceID: AudioDeviceID) throws -> String {
        try readString(
            objectID: deviceID,
            selector: kAudioObjectPropertyName,
            operation: "Read device name"
        )
    }

    static func deviceUID(_ deviceID: AudioDeviceID) throws -> String {
        try readString(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            operation: "Read output device UID"
        )
    }

    static func deviceSummary(_ deviceID: AudioDeviceID) throws -> AudioDeviceSummary {
        let name = try deviceName(deviceID)
        let uid = try deviceUID(deviceID)
        return AudioDeviceSummary(id: deviceID, name: name, uid: uid)
    }

    static func outputStreamIDs(_ deviceID: AudioDeviceID) throws -> [AudioObjectID] {
        try readAudioObjectIDArray(
            objectID: deviceID,
            selector: kAudioDevicePropertyStreams,
            scope: kAudioDevicePropertyScopeOutput,
            operation: "Read output stream list"
        )
    }

    static func processObjectID(forPID pid: pid_t) throws -> AudioObjectID? {
        let processIDs = try readAudioObjectIDArray(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessObjectList,
            operation: "Read Core Audio process object list"
        )

        for processID in processIDs {
            let processPID: pid_t = try readScalar(
                objectID: processID,
                selector: kAudioProcessPropertyPID,
                defaultValue: 0,
                operation: "Read process PID"
            )
            if processPID == pid {
                return processID
            }
        }

        return nil
    }

    static func tapUID(_ tapID: AudioObjectID) throws -> String {
        try readString(
            objectID: tapID,
            selector: kAudioTapPropertyUID,
            operation: "Read process tap UID"
        )
    }

    static func tapFormat(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        try readScalar(
            objectID: tapID,
            selector: kAudioTapPropertyFormat,
            defaultValue: AudioStreamBasicDescription(),
            operation: "Read process tap format"
        )
    }

    static func tapDescription(_ tapID: AudioObjectID) throws -> CATapDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyDescription,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CATapDescription>?
        var size = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
        let status = withUnsafeMutableBytes(of: &value) { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }
            return AudioObjectGetPropertyData(
                tapID,
                &address,
                0,
                nil,
                &size,
                baseAddress
            )
        }
        try checkOSStatus(status, operation: "Read process tap description")

        guard let value else {
            throw PrototypeError(message: "Read process tap description returned nil")
        }
        return value.takeRetainedValue()
    }

    static func streamVirtualFormat(_ streamID: AudioObjectID) throws -> AudioStreamBasicDescription {
        try readScalar(
            objectID: streamID,
            selector: kAudioStreamPropertyVirtualFormat,
            defaultValue: AudioStreamBasicDescription(),
            operation: "Read output stream virtual format"
        )
    }
}

struct AudioDeviceSummary: CustomStringConvertible {
    let id: AudioDeviceID
    let name: String
    let uid: String

    var description: String {
        "\(name) [AudioObjectID \(id), UID \(uid)]"
    }
}

extension AudioStreamBasicDescription {
    var isFloat32LinearPCM: Bool {
        mFormatID == kAudioFormatLinearPCM &&
            (mFormatFlags & kAudioFormatFlagIsFloat) != 0 &&
            mBitsPerChannel == 32
    }

    var isNonInterleaved: Bool {
        (mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
    }

    func isPlaybackCompatible(with other: AudioStreamBasicDescription) -> Bool {
        isFloat32LinearPCM &&
            other.isFloat32LinearPCM &&
            mChannelsPerFrame == other.mChannelsPerFrame &&
            abs(mSampleRate - other.mSampleRate) < 1.0
    }

    var formatSummary: String {
        let flags = String(mFormatFlags, radix: 16)
        let layout = isNonInterleaved ? "non-interleaved" : "interleaved"
        return "sampleRate=\(mSampleRate), channels=\(mChannelsPerFrame), bytesPerFrame=\(mBytesPerFrame), bitsPerChannel=\(mBitsPerChannel), flags=0x\(flags), \(layout)"
    }
}
