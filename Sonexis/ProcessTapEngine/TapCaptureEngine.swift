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
    var processSelectionDidChange: (() -> Void)?
    private var captureTarget: AudioCaptureTarget?
    private var ownProcessID: AudioObjectID = kAudioObjectUnknown
    private var processRefreshTimer: Timer?
    private var selectedProcessIDs: [AudioObjectID] = []
    private var lastRefreshError: String?
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var ringBuffer: RealtimeRingBuffer?

    private(set) var sourceDevice: AudioDeviceSummary?
    private(set) var tapFormat: AudioStreamBasicDescription?

    func prepare(
        sourceDevice defaultOutput: AudioDeviceSummary,
        outputStreamFormat: AudioStreamBasicDescription,
        ownProcessObjectID: AudioObjectID,
        captureTarget: AudioCaptureTarget? = nil,
        fixedSelection: ProcessTapSelection? = nil
    ) throws -> TapCaptureConfiguration {
        self.ownProcessID = ownProcessObjectID
        self.captureTarget = captureTarget
        let selectedIDs = try fixedSelection?.safeProcessIDs(ownProcessID: ownProcessObjectID)
            ?? captureTarget?.processObjectIDs(excluding: ownProcessObjectID) ?? [ownProcessObjectID]
        let isExclusive = fixedSelection?.isExclusive ?? (captureTarget == nil)
        let tapDescription = Self.makeDescription(sourceDeviceUID: defaultOutput.uid,
            ownProcessID: ownProcessObjectID, selectedProcesses: isExclusive ? nil : selectedIDs)
        if fixedSelection != nil {
            tapDescription.isExclusive = isExclusive
            tapDescription.processes = selectedIDs
        }
        selectedProcessIDs = selectedIDs
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
        guard installedTapDescription.isExclusive == isExclusive,
              Set(installedTapDescription.processes) == Set(selectedIDs),
              isExclusive || !installedTapDescription.processes.contains(ownProcessObjectID) else {
            throw PrototypeError(
                message: "Process tap self-exclusion verification failed. Refusing to start playback to avoid recursive capture."
            )
        }
        guard installedTapDescription.deviceUID == defaultOutput.uid else {
            throw PrototypeError(
                message: "Process tap source UID mismatch. Expected \(defaultOutput.uid), got \(installedTapDescription.deviceUID ?? "nil")."
            )
        }
        print("Verified tap source selection excludes Sonexis playback.")
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

        processRefreshTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, fixedSelection == nil, self.captureTarget != nil else { return }
            do {
                let ids = try self.captureTarget?.processObjectIDs(excluding: self.ownProcessID) ?? []
                if ids != self.selectedProcessIDs { self.processSelectionDidChange?() }
                self.lastRefreshError = nil
            } catch {
                let message = String(describing: error)
                if self.lastRefreshError != message { print("Audio source refresh failed: \(message)") }
                self.lastRefreshError = message
            }
        }

        if let processRefreshTimer { RunLoop.main.add(processRefreshTimer, forMode: .common) }

        return TapCaptureConfiguration(
            sourceDevice: defaultOutput,
            tapFormat: createdTapFormat
        )
    }

    // nil means all audio; an empty list means a selected app has no audio
    // processes. Never turn that empty selection into a global tap.
    static func configureSelection(_ description: CATapDescription,
                                   selectedProcesses: [AudioObjectID]?, ownProcessID: AudioObjectID) {
        description.isExclusive = selectedProcesses == nil
        description.processes = selectedProcesses.map {
            Array(Set($0.filter { $0 != ownProcessID && $0 != kAudioObjectUnknown })).sorted()
        } ?? [ownProcessID]
    }

    static func makeDescription(sourceDeviceUID: String, ownProcessID: AudioObjectID,
                                selectedProcesses: [AudioObjectID]?) -> CATapDescription {
        let description: CATapDescription
        if let selectedProcesses {
            description = CATapDescription(processes: selectedProcesses.filter { $0 != ownProcessID },
                                           deviceUID: sourceDeviceUID, stream: 0)
        } else {
            description = CATapDescription(excludingProcesses: [ownProcessID],
                                           deviceUID: sourceDeviceUID, stream: 0)
        }
        configureSelection(description, selectedProcesses: selectedProcesses, ownProcessID: ownProcessID)
        return description
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
        processRefreshTimer?.invalidate()
        processRefreshTimer = nil
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
