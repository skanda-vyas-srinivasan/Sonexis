import CoreAudio
import Foundation

private func outputIOProc(
    _ inDevice: AudioObjectID,
    _ inNow: UnsafePointer<AudioTimeStamp>,
    _ inInputData: UnsafePointer<AudioBufferList>,
    _ inInputTime: UnsafePointer<AudioTimeStamp>,
    _ outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _ inOutputTime: UnsafePointer<AudioTimeStamp>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let inClientData else { return noErr }
    let engine = Unmanaged<AudioOutputEngine>
        .fromOpaque(inClientData)
        .takeUnretainedValue()
    engine.outputCallback(outputData: outOutputData)
    return noErr
}

final class AudioOutputEngine {
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var ringBuffer: RealtimeRingBuffer?

    private(set) var deviceSummary: AudioDeviceSummary?

    var activeDeviceID: AudioDeviceID {
        deviceID
    }

    func createIOProc(
        deviceID: AudioDeviceID,
        deviceSummary: AudioDeviceSummary,
        ringBuffer: RealtimeRingBuffer
    ) throws {
        let clientData = Unmanaged.passUnretained(self).toOpaque()

        var createdIOProcID: AudioDeviceIOProcID?
        try checkOSStatus(
            AudioDeviceCreateIOProcID(
                deviceID,
                outputIOProc,
                clientData,
                &createdIOProcID
            ),
            operation: "Create default output IOProc"
        )

        guard let createdIOProcID else {
            throw PrototypeError(message: "Create default output IOProc returned nil IOProcID")
        }

        self.deviceID = deviceID
        self.deviceSummary = deviceSummary
        self.ringBuffer = ringBuffer
        ioProcID = createdIOProcID
    }

    func start() throws {
        guard let ioProcID else {
            throw PrototypeError(message: "Default output IOProc was not created")
        }

        try checkOSStatus(
            AudioDeviceStart(deviceID, ioProcID),
            operation: "Start default output IOProc"
        )
    }

    func stop(log: Bool) {
        if deviceID != kAudioObjectUnknown, let ioProcID {
            let status = AudioDeviceStop(deviceID, ioProcID)
            if log { printCleanupResult("stopped playback output IOProc", status: status) }
        } else if log {
            print("Cleanup: no playback output IOProc to stop.")
        }
    }

    func destroyIOProc(log: Bool) {
        if deviceID != kAudioObjectUnknown, let ioProcID {
            let status = AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            if log { printCleanupResult("destroyed playback output IOProc ID", status: status) }
            self.ioProcID = nil
            ringBuffer = nil
        } else if log {
            print("Cleanup: no playback output IOProc ID to destroy.")
        }
    }

    func teardown(log: Bool) {
        stop(log: log)
        destroyIOProc(log: log)
        deviceID = kAudioObjectUnknown
        deviceSummary = nil
    }

    fileprivate func outputCallback(outputData: UnsafeMutablePointer<AudioBufferList>) {
        _ = ringBuffer?.read(outputData: outputData)
    }
}
