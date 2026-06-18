import AppKit
import CoreAudio
import Foundation

private let startupPrerollTargetFrames: UInt32 = 1_024
private let startupPrerollPollInterval: TimeInterval = 0.005
private let startupPartialPrerollTimeout: TimeInterval = 0.35
private let rampSettleDuration: TimeInterval = 0.03
private let wakeRebuildDelay: TimeInterval = 1.0
private let rebuildRetryDelay: TimeInterval = 1.5
private let rebuildRetryLimit = 4

final class ProcessTapDSPApp {
    private let dspProcessor: DSPProcessor

    private var tapCaptureEngine: TapCaptureEngine?
    private var audioOutputEngine: AudioOutputEngine?
    private var ringBuffer: RealtimeRingBuffer?

    private var statusTimer: DispatchSourceTimer?
    private var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?
    private var activeDeviceAliveListenerBlock: AudioObjectPropertyListenerBlock?
    private var activeDeviceAliveListenerDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var routeChangeWorkItem: DispatchWorkItem?
    private var recoveryWorkItem: DispatchWorkItem?
    private var smoothTeardownWorkItem: DispatchWorkItem?
    private var startupPrerollTimer: DispatchSourceTimer?
    private var sleepWakeObservers: [NSObjectProtocol] = []

    private var activeSampleRate: Double = 48_000.0
    private var lastWrittenFrames: UInt64 = 0
    private var lastReadFrames: UInt64 = 0
    private var statusTick: UInt64 = 0
    private var isStopped = true
    private var isSuspendedForSleep = false

    init(configuration: DSPConfiguration = .productBaseline) {
        self.dspProcessor = DSPProcessor(configuration: configuration)
    }

    func start() throws {
        isStopped = false
        isSuspendedForSleep = false
        try installDefaultOutputListener()
        installSleepWakeObservers()
        try rebuildPipeline(reason: "initial start")
    }

    func stop(reason: String = "shutdown", completion: @escaping () -> Void = {}) {
        print("")
        print("Stopping ProcessTapDSP: \(reason)")

        if isStopped {
            print("Shutdown skipped: app is already stopped.")
            completion()
            return
        }

        isStopped = true
        if routeChangeWorkItem != nil {
            routeChangeWorkItem?.cancel()
            print("Cleanup: canceled pending route-change rebuild.")
        }
        routeChangeWorkItem = nil
        if recoveryWorkItem != nil {
            recoveryWorkItem?.cancel()
            print("Cleanup: canceled pending recovery rebuild.")
        }
        recoveryWorkItem = nil
        removeSleepWakeObservers(log: true)
        removeDefaultOutputListener(log: true)
        smoothTeardownPipeline(log: true, reason: reason, rampDuration: dspProcessor.shutdownRampDuration) {
            print("Shutdown complete. Normal system audio should be restored.")
            completion()
        }
    }

    func stopImmediately(reason: String = "immediate shutdown") {
        print("")
        print("Immediately stopping ProcessTapDSP: \(reason)")

        if isStopped {
            print("Immediate shutdown skipped: app is already stopped.")
            return
        }

        isStopped = true
        routeChangeWorkItem?.cancel()
        routeChangeWorkItem = nil
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
        smoothTeardownWorkItem?.cancel()
        smoothTeardownWorkItem = nil
        removeSleepWakeObservers(log: true)
        removeDefaultOutputListener(log: true)
        teardownPipeline(log: true, reason: reason)
        print("Immediate shutdown complete. Normal system audio should be restored.")
    }

    private func rebuildPipeline(reason: String) throws {
        print("")
        print("Rebuilding audio pipeline: \(reason)")
        printRouteDiagnostics(context: "before rebuild")

        do {
            teardownPipeline(log: reason != "initial start", reason: "rebuild cleanup")
            try buildPipeline()
            printRouteDiagnostics(context: "after rebuild")
            print("Started Process Tap -> \(dspProcessor.processingDescription) -> default output playback.")
            print("Play system audio in another app. Press Control-C to stop.")
        } catch {
            teardownPipeline(log: true, reason: "rebuild failure cleanup")
            throw error
        }
    }

    private func buildPipeline() throws {
        let defaultOutputDeviceID = try CoreAudioSupport.defaultOutputDevice()
        let defaultOutput = try CoreAudioSupport.deviceSummary(defaultOutputDeviceID)
        let streamIDs = try CoreAudioSupport.outputStreamIDs(defaultOutputDeviceID)

        guard !streamIDs.isEmpty else {
            throw PrototypeError(message: "The default output device has no output streams")
        }

        guard let ownProcessObjectID = try CoreAudioSupport.processObjectID(forPID: getpid()) else {
            throw PrototypeError(
                message: "This process is not present in the HAL process-object list. Playback mode refuses to start without self-exclusion because that can create recursive capture."
            )
        }

        print("Excluding this process from the tap: AudioObjectID \(ownProcessObjectID)")
        print("Current default output device: \(defaultOutput)")
        print("Using output stream index 0 of \(streamIDs.count)")

        let outputStreamFormat = try CoreAudioSupport.streamVirtualFormat(streamIDs[0])
        print("Default output stream format: \(outputStreamFormat.formatSummary)")

        let tapEngine = TapCaptureEngine()
        tapCaptureEngine = tapEngine
        let tapConfiguration = try tapEngine.prepare(
            sourceDevice: defaultOutput,
            outputStreamFormat: outputStreamFormat,
            ownProcessObjectID: ownProcessObjectID
        )

        let tapFormat = tapConfiguration.tapFormat
        activeSampleRate = tapFormat.mSampleRate

        let channelCount = tapFormat.mChannelsPerFrame
        guard channelCount > 0 else {
            throw PrototypeError(message: "Tap reported zero channels")
        }

        let ringCapacityFrames = max(UInt32(tapFormat.mSampleRate * 2.0), 4_096)
        let createdRingBuffer = try RealtimeRingBuffer(
            capacityFrames: ringCapacityFrames,
            channels: channelCount
        )
        dspProcessor.configureInitialGain(on: createdRingBuffer)
        dspProcessor.configurePitchShift(on: createdRingBuffer)
        createdRingBuffer.setReadEnabled(false)
        ringBuffer = createdRingBuffer
        print("Created realtime ring buffer: \(ringCapacityFrames) frames, \(channelCount) channels")
        print("Initial gain: \(dspProcessor.unityGain); hardcoded target gain: \(dspProcessor.processingGain)")
        print("Pitch shift: enabled=\(dspProcessor.pitchShiftEnabled), semitones=\(dspProcessor.pitchShiftSemitones)")
        print("Startup preroll target: \(startupPrerollTargetFrames) frames")

        let outputEngine = AudioOutputEngine()
        audioOutputEngine = outputEngine
        try outputEngine.createIOProc(
            deviceID: defaultOutputDeviceID,
            deviceSummary: defaultOutput,
            ringBuffer: createdRingBuffer
        )
        try tapEngine.createIOProc(ringBuffer: createdRingBuffer)
        try installActiveDeviceAliveListener(deviceID: defaultOutputDeviceID)
        try startIO()
        scheduleStartupPreroll(context: "pipeline start")
        startStatusTimer()
    }

    private func startIO() throws {
        guard let tapCaptureEngine, let audioOutputEngine else {
            throw PrototypeError(message: "IO engines were not created")
        }

        try audioOutputEngine.start()

        do {
            try tapCaptureEngine.start()
        } catch {
            audioOutputEngine.stop(log: false)
            throw error
        }
    }

    private func scheduleStartupPreroll(context: String) {
        guard ringBuffer != nil else { return }

        startupPrerollTimer?.cancel()
        var firstFillTime: DispatchTime?
        let partialTimeoutNanoseconds = UInt64(startupPartialPrerollTimeout * 1_000_000_000.0)

        print(
            "Startup: holding processed output until ring fill reaches \(startupPrerollTargetFrames) frames; partial fill accepted \(Int(startupPartialPrerollTimeout * 1000.0)) ms after capture begins."
        )

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: startupPrerollPollInterval)
        timer.setEventHandler { [weak self] in
            guard let self, !self.isStopped, let ringBuffer = self.ringBuffer else { return }

            let fill = ringBuffer.fillFrames
            let now = DispatchTime.now()

            if fill >= startupPrerollTargetFrames {
                self.finishStartupPreroll(context: context, reason: "ring fill \(fill) frames")
            } else if fill > 0 {
                if firstFillTime == nil {
                    firstFillTime = now
                }

                if let firstFillTime,
                   now.uptimeNanoseconds - firstFillTime.uptimeNanoseconds >= partialTimeoutNanoseconds {
                    self.finishStartupPreroll(context: context, reason: "partial ring fill \(fill) frames")
                }
            }
        }
        startupPrerollTimer = timer
        timer.resume()
    }

    private func finishStartupPreroll(context: String, reason: String) {
        guard let ringBuffer else { return }

        startupPrerollTimer?.cancel()
        startupPrerollTimer = nil
        ringBuffer.setReadEnabled(true)
        print("Startup: releasing processed output after \(reason).")
        requestProcessingGainRamp(context: context)
    }

    private func cancelStartupPreroll(enableRead: Bool, log: Bool) {
        let hadTimer = startupPrerollTimer != nil
        startupPrerollTimer?.cancel()
        startupPrerollTimer = nil

        if enableRead, let ringBuffer {
            ringBuffer.setReadEnabled(true)
        }

        if log, hadTimer {
            print("Cleanup: canceled startup preroll gate.")
        }
    }

    private func requestProcessingGainRamp(context: String) {
        guard let ringBuffer else { return }

        let milliseconds = Int((dspProcessor.startupRampDuration * 1000.0).rounded())
        print("Gain: ramping processed path to \(dspProcessor.processingGain) over \(milliseconds) ms (\(context)).")
        dspProcessor.requestProcessingGainRamp(on: ringBuffer, sampleRate: activeSampleRate)
    }

    private func smoothTeardownPipeline(
        log: Bool,
        reason: String,
        rampDuration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        cancelStartupPreroll(enableRead: true, log: log)
        smoothTeardownWorkItem?.cancel()
        smoothTeardownWorkItem = nil

        guard let ringBuffer else {
            teardownPipeline(log: log, reason: reason)
            completion()
            return
        }

        if log {
            let milliseconds = Int((rampDuration * 1000.0).rounded())
            print("Cleanup: ramping processed gain to unity over \(milliseconds) ms before releasing Process Tap.")
        }
        dspProcessor.requestUnityGainRamp(
            on: ringBuffer,
            sampleRate: activeSampleRate,
            duration: rampDuration
        )

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                completion()
                return
            }
            self.smoothTeardownWorkItem = nil
            self.teardownPipeline(log: log, reason: reason)
            completion()
        }
        smoothTeardownWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + rampDuration + rampSettleDuration,
            execute: workItem
        )
    }

    private func teardownPipeline(log: Bool = false, reason: String = "pipeline teardown") {
        if log {
            print("Cleanup: tearing down audio pipeline (\(reason)).")
        }

        cancelStartupPreroll(enableRead: false, log: log)
        removeActiveDeviceAliveListener(log: log)

        if statusTimer != nil {
            statusTimer?.cancel()
            if log { print("Cleanup: canceled status timer.") }
        }
        statusTimer = nil

        tapCaptureEngine?.stop(log: log)
        audioOutputEngine?.stop(log: log)
        tapCaptureEngine?.destroyIOProc(log: log)
        audioOutputEngine?.destroyIOProc(log: log)
        tapCaptureEngine?.destroyAggregateDevice(log: log)
        tapCaptureEngine?.destroyTap(log: log)

        tapCaptureEngine = nil
        audioOutputEngine = nil

        if let ringBuffer {
            ringBuffer.destroy()
            self.ringBuffer = nil
            if log { print("Cleanup: freed realtime ring buffer.") }
        } else if log {
            print("Cleanup: no realtime ring buffer to free.")
        }

        activeSampleRate = 48_000.0
        lastWrittenFrames = 0
        lastReadFrames = 0
        statusTick = 0
    }

    private func installDefaultOutputListener() throws {
        guard defaultOutputListenerBlock == nil else { return }

        var address = defaultOutputDeviceAddress()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleRouteRebuild(reason: "default output changed")
        }

        try checkOSStatus(
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            ),
            operation: "Install default output device listener"
        )

        defaultOutputListenerBlock = block
    }

    private func removeDefaultOutputListener(log: Bool = false) {
        guard let defaultOutputListenerBlock else { return }

        var address = defaultOutputDeviceAddress()
        let status = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            defaultOutputListenerBlock
        )
        if log { printCleanupResult("removed default-output route listener", status: status) }
        self.defaultOutputListenerBlock = nil
    }

    private func installActiveDeviceAliveListener(deviceID: AudioDeviceID) throws {
        removeActiveDeviceAliveListener(log: false)

        var address = activeDeviceAliveAddress()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleRouteRebuild(reason: "active output device availability changed")
        }

        try checkOSStatus(
            AudioObjectAddPropertyListenerBlock(
                deviceID,
                &address,
                DispatchQueue.main,
                block
            ),
            operation: "Install active output device alive listener"
        )

        activeDeviceAliveListenerBlock = block
        activeDeviceAliveListenerDeviceID = deviceID
    }

    private func removeActiveDeviceAliveListener(log: Bool = false) {
        guard let activeDeviceAliveListenerBlock,
              activeDeviceAliveListenerDeviceID != kAudioObjectUnknown else {
            return
        }

        var address = activeDeviceAliveAddress()
        let status = AudioObjectRemovePropertyListenerBlock(
            activeDeviceAliveListenerDeviceID,
            &address,
            DispatchQueue.main,
            activeDeviceAliveListenerBlock
        )
        if log { printCleanupResult("removed active output device alive listener", status: status) }
        self.activeDeviceAliveListenerBlock = nil
        activeDeviceAliveListenerDeviceID = kAudioObjectUnknown
    }

    private func installSleepWakeObservers() {
        guard sleepWakeObservers.isEmpty else { return }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        let willSleep = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWillSleep()
        }
        let didWake = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemDidWake()
        }
        sleepWakeObservers = [willSleep, didWake]
        print("Installed sleep/wake observers.")
    }

    private func removeSleepWakeObservers(log: Bool = false) {
        guard !sleepWakeObservers.isEmpty else { return }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in sleepWakeObservers {
            notificationCenter.removeObserver(observer)
        }
        sleepWakeObservers.removeAll()
        if log { print("Cleanup: removed sleep/wake observers.") }
    }

    private func handleSystemWillSleep() {
        guard !isStopped else { return }

        routeChangeWorkItem?.cancel()
        routeChangeWorkItem = nil
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
        isSuspendedForSleep = true

        print("")
        print("System sleep notification received.")
        printRouteDiagnostics(context: "before sleep")

        smoothTeardownPipeline(log: true, reason: "system sleep", rampDuration: dspProcessor.routeChangeRampDuration) {
            print("Sleep: audio pipeline stopped. It will rebuild after wake.")
        }
    }

    private func handleSystemDidWake() {
        guard !isStopped else { return }

        isSuspendedForSleep = false
        print("")
        print("System wake notification received.")
        scheduleRecoveryRebuild(reason: "system wake", delay: wakeRebuildDelay, attemptsRemaining: rebuildRetryLimit)
    }

    private func scheduleRouteRebuild(reason: String) {
        guard !isStopped, !isSuspendedForSleep else { return }

        routeChangeWorkItem?.cancel()
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil

        let workItem = DispatchWorkItem { [weak self] in
            self?.handleRouteChange(reason: reason)
        }
        routeChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func handleRouteChange(reason: String) {
        guard !isStopped, !isSuspendedForSleep else { return }
        routeChangeWorkItem = nil

        print("")
        print("Route change detected: \(reason).")
        printRouteDiagnostics(context: "route-change notification")

        smoothTeardownPipeline(log: true, reason: "route-change rebuild", rampDuration: dspProcessor.routeChangeRampDuration) { [weak self] in
            guard let self, !self.isStopped, !self.isSuspendedForSleep else { return }

            do {
                try self.buildPipeline()
                self.printRouteDiagnostics(context: "after rebuild")
                print("Started Process Tap -> \(self.dspProcessor.processingDescription) -> default output playback.")
                print("Play system audio in another app. Press Control-C to stop.")
            } catch {
                self.handleRebuildFailure(
                    error,
                    reason: reason,
                    retryAttemptsRemaining: rebuildRetryLimit
                )
            }
        }
    }

    private func scheduleRecoveryRebuild(
        reason: String,
        delay: TimeInterval,
        attemptsRemaining: Int
    ) {
        guard !isStopped, !isSuspendedForSleep else { return }

        recoveryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptRecoveryRebuild(reason: reason, attemptsRemaining: attemptsRemaining)
        }
        recoveryWorkItem = workItem

        let milliseconds = Int((delay * 1000.0).rounded())
        print("Recovery: scheduling rebuild for \(reason) in \(milliseconds) ms.")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func attemptRecoveryRebuild(reason: String, attemptsRemaining: Int) {
        guard !isStopped, !isSuspendedForSleep else { return }
        recoveryWorkItem = nil

        print("")
        print("Recovery: attempting rebuild (\(reason)); attempts remaining after this: \(attemptsRemaining).")
        printRouteDiagnostics(context: "before recovery rebuild")

        do {
            try rebuildPipeline(reason: reason)
            print("Recovery: rebuild succeeded.")
        } catch {
            handleRebuildFailure(error, reason: reason, retryAttemptsRemaining: attemptsRemaining)
        }
    }

    private func handleRebuildFailure(
        _ error: Error,
        reason: String,
        retryAttemptsRemaining: Int
    ) {
        teardownPipeline(log: true, reason: "rebuild failure cleanup")
        print("Rebuild failed (\(reason)): \(error)")

        if error is NoDefaultOutputDeviceError {
            print("No output device is currently available. The pipeline is stopped and normal system audio should be unmuted.")
            print("Connect or select an output device; the default-output listener will retry when Core Audio reports a route.")
            return
        }

        guard retryAttemptsRemaining > 0 else {
            print("Recovery retries exhausted. Change routes again or restart the app to retry.")
            return
        }

        scheduleRecoveryRebuild(
            reason: reason,
            delay: rebuildRetryDelay,
            attemptsRemaining: retryAttemptsRemaining - 1
        )
    }

    private func startStatusTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self, let ringBuffer else { return }

            let fill = ringBuffer.fillFrames
            let dropped = ringBuffer.droppedFrames
            let underflows = ringBuffer.underflowFrames
            let written = ringBuffer.writtenFrames
            let read = ringBuffer.readFrames
            let peakPPM = ringBuffer.lastInputPeakPPM
            let gainPPM = ringBuffer.currentGainPPM
            let writtenDelta = written - lastWrittenFrames
            let readDelta = read - lastReadFrames
            lastWrittenFrames = written
            lastReadFrames = read

            let peak = max(Double(peakPPM) / 1_000_000.0, 1.0e-12)
            let peakDB = 20.0 * log10(peak)
            let gain = Double(gainPPM) / 1_000_000.0
            print(
                String(
                    format: "ring fill: %u frames, in/s: %llu, out/s: %llu, input peak: %.1f dBFS, gain: %.3f, dropped: %llu, underflow: %llu",
                    fill,
                    writtenDelta,
                    readDelta,
                    peakDB,
                    gain,
                    dropped,
                    underflows
                )
            )

            statusTick += 1
            if statusTick % 5 == 0 {
                printRouteDiagnostics(context: "periodic")
            }
        }
        statusTimer = timer
        timer.resume()
    }

    private func printRouteDiagnostics(context: String) {
        print("Route diagnostics (\(context)):")

        if let currentDefaultDevice = try? CoreAudioSupport.defaultOutputDevice(),
           let currentDefault = try? CoreAudioSupport.deviceSummary(currentDefaultDevice) {
            print("  Current default output: \(currentDefault)")
        } else {
            print("  Current default output: unavailable")
        }

        if let activeTapSourceDevice = tapCaptureEngine?.sourceDevice {
            print("  Tap source device:      \(activeTapSourceDevice)")
        } else {
            print("  Tap source device:      none")
        }

        if let activePlaybackDevice = audioOutputEngine?.deviceSummary {
            print("  Playback output device: \(activePlaybackDevice)")
        } else {
            print("  Playback output device: none")
        }
    }

    private func defaultOutputDeviceAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func activeDeviceAliveAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
