import CoreAudio
import Foundation

private func tapInputIOProc(
    _ inDevice: AudioObjectID,
    _ inNow: UnsafePointer<AudioTimeStamp>,
    _ inInputData: UnsafePointer<AudioBufferList>,
    _ inInputTime: UnsafePointer<AudioTimeStamp>,
    _ outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _ inOutputTime: UnsafePointer<AudioTimeStamp>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let inClientData else { return noErr }
    let engine = Unmanaged<TapCaptureEngine>
        .fromOpaque(inClientData)
        .takeUnretainedValue()
    engine.captureCallback(inputData: inInputData)
    return noErr
}

struct TapCaptureConfiguration {
    let sourceDevice: AudioDeviceSummary
    let tapFormat: AudioStreamBasicDescription
}

final class TapCaptureEngine {
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var ringBuffer: RealtimeRingBuffer?

    private(set) var sourceDevice: AudioDeviceSummary?
    private(set) var tapFormat: AudioStreamBasicDescription?

    func prepare(
        sourceDevice defaultOutput: AudioDeviceSummary,
        outputStreamFormat: AudioStreamBasicDescription,
        ownProcessObjectID: AudioObjectID
    ) throws -> TapCaptureConfiguration {
        let tapDescription = CATapDescription(
            excludingProcesses: [ownProcessObjectID],
            deviceUID: defaultOutput.uid,
            stream: 0
        )
        tapDescription.name = "ProcessTapDSP System Output Tap"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = CATapMuteBehavior(rawValue: 2)!

        var createdTapID = kAudioObjectUnknown
        try checkOSStatus(
            AudioHardwareCreateProcessTap(tapDescription, &createdTapID),
            operation: "AudioHardwareCreateProcessTap"
        )
        tapID = createdTapID
        print("Created process tap: AudioObjectID \(tapID)")

        let installedTapDescription = try CoreAudioSupport.tapDescription(tapID)
        guard installedTapDescription.isExclusive,
              installedTapDescription.processes.contains(ownProcessObjectID) else {
            throw PrototypeError(
                message: "Process tap self-exclusion verification failed. Refusing to start playback to avoid recursive capture."
            )
        }
        guard installedTapDescription.deviceUID == defaultOutput.uid else {
            throw PrototypeError(
                message: "Process tap source UID mismatch. Expected \(defaultOutput.uid), got \(installedTapDescription.deviceUID ?? "nil")."
            )
        }
        print("Verified tap exclusion includes this process.")
        print("Tap source device: \(defaultOutput)")

        let createdTapFormat = try CoreAudioSupport.tapFormat(tapID)
        print("Tap format: \(createdTapFormat.formatSummary)")
        guard createdTapFormat.isPlaybackCompatible(with: outputStreamFormat) else {
            throw PrototypeError(
                message: "This PoC requires matching Float32 tap/output formats and does not perform sample-rate conversion. Tap: \(createdTapFormat.formatSummary). Output: \(outputStreamFormat.formatSummary)"
            )
        }

        let tapUID = try CoreAudioSupport.tapUID(tapID)
        aggregateDeviceID = try createPrivateAggregateDevice(tapUID: tapUID)
        print("Created private aggregate device: AudioDeviceID \(aggregateDeviceID)")

        sourceDevice = defaultOutput
        tapFormat = createdTapFormat

        return TapCaptureConfiguration(
            sourceDevice: defaultOutput,
            tapFormat: createdTapFormat
        )
    }

    func createIOProc(ringBuffer: RealtimeRingBuffer) throws {
        let clientData = Unmanaged.passUnretained(self).toOpaque()

        var createdIOProcID: AudioDeviceIOProcID?
        try checkOSStatus(
            AudioDeviceCreateIOProcID(
                aggregateDeviceID,
                tapInputIOProc,
                clientData,
                &createdIOProcID
            ),
            operation: "Create tap aggregate IOProc"
        )

        guard let createdIOProcID else {
            throw PrototypeError(message: "Create tap aggregate IOProc returned nil IOProcID")
        }

        self.ringBuffer = ringBuffer
        ioProcID = createdIOProcID
    }

    func start() throws {
        guard let ioProcID else {
            throw PrototypeError(message: "Tap aggregate IOProc was not created")
        }

        try checkOSStatus(
            AudioDeviceStart(aggregateDeviceID, ioProcID),
            operation: "Start tap aggregate IOProc"
        )
    }

    func stop(log: Bool) {
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            let status = AudioDeviceStop(aggregateDeviceID, ioProcID)
            if log { printCleanupResult("stopped tap aggregate IOProc", status: status) }
        } else if log {
            print("Cleanup: no tap aggregate IOProc to stop.")
        }
    }

    func destroyIOProc(log: Bool) {
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            let status = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            if log { printCleanupResult("destroyed tap aggregate IOProc ID", status: status) }
            self.ioProcID = nil
            ringBuffer = nil
        } else if log {
            print("Cleanup: no tap aggregate IOProc ID to destroy.")
        }
    }

    func destroyAggregateDevice(log: Bool) {
        if aggregateDeviceID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if log { printCleanupResult("destroyed private aggregate device", status: status) }
            aggregateDeviceID = kAudioObjectUnknown
        } else if log {
            print("Cleanup: no private aggregate device to destroy.")
        }
    }

    func destroyTap(log: Bool) {
        if tapID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyProcessTap(tapID)
            if log { printCleanupResult("destroyed Process Tap", status: status) }
            tapID = kAudioObjectUnknown
        } else if log {
            print("Cleanup: no Process Tap to destroy.")
        }
    }

    func teardown(log: Bool) {
        stop(log: log)
        destroyIOProc(log: log)
        destroyAggregateDevice(log: log)
        destroyTap(log: log)
        sourceDevice = nil
        tapFormat = nil
    }

    fileprivate func captureCallback(inputData: UnsafePointer<AudioBufferList>) {
        _ = ringBuffer?.write(inputData: inputData)
    }

    private func createPrivateAggregateDevice(tapUID: String) throws -> AudioDeviceID {
        let aggregateUID = "com.sonexis.prototype.ProcessTapDSP.aggregate.\(UUID().uuidString)"
        let tapEntry: [String: Any] = [
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: true
        ]
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ProcessTapDSP Private Aggregate",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [tapEntry],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]

        var deviceID = kAudioObjectUnknown
        try checkOSStatus(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &deviceID),
            operation: "AudioHardwareCreateAggregateDevice"
        )
        return deviceID
    }
}
