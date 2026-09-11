import CoreAudio
import Foundation

func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
               defaultValue: T) throws -> T {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                             mElement: kAudioObjectPropertyElementMain)
    var value = defaultValue
    var size = UInt32(MemoryLayout<T>.size)
    let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    return value
}

func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout.size(ofValue: value))
    let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    guard status == noErr, let value else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    return value.takeRetainedValue() as String
}

func objectIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                             mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size)
    guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    var values = [AudioObjectID](repeating: kAudioObjectUnknown,
                                count: Int(size) / MemoryLayout<AudioObjectID>.size)
    status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &values)
    guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    return values
}

let system = AudioObjectID(kAudioObjectSystemObject)
let output: AudioDeviceID = try scalar(system, kAudioHardwarePropertyDefaultOutputDevice, defaultValue: kAudioObjectUnknown)
let name = try string(output, kAudioObjectPropertyName)
let uid = try string(output, kAudioDevicePropertyDeviceUID)
let rate: Float64 = try scalar(output, kAudioDevicePropertyNominalSampleRate, defaultValue: 0)
let alive: UInt32 = try scalar(output, kAudioDevicePropertyDeviceIsAlive, defaultValue: 0)
let result: [String: Any] = ["id": output, "name": name, "uid": uid,
                             "nominalSampleRate": rate, "alive": alive != 0,
                             "availableOutputs": try objectIDs(system, kAudioHardwarePropertyDevices).compactMap { device -> [String: Any]? in
                                 guard let streams = try? objectIDs(device, kAudioDevicePropertyStreams,
                                                                    scope: kAudioDevicePropertyScopeOutput),
                                       !streams.isEmpty,
                                       let name = try? string(device, kAudioObjectPropertyName) else { return nil }
                                 return ["id": device, "name": name]
                             }]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)
