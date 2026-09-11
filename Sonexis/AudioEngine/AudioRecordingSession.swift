import AVFoundation
import Foundation

/// One recording owns its writer, bounded buffer pool, and completion barrier.
/// append() copies samples only; all file writes and finalization use writerQueue.
final class AudioRecordingSession {
    struct Result {
        let url: URL
        let writtenFrames: Int64
        let droppedFrames: Int64
        let error: String?
    }

    let url: URL
    let format: AVAudioFormat
    private let lock = NSLock()
    // Recording is user-initiated work. A utility queue can be starved long
    // enough to exhaust a small pool even when the disk itself is healthy.
    private let writerQueue = DispatchQueue(label: "Sonexis.RecordingWriter", qos: .userInitiated)
    private var file: AVAudioFile?
    private var pool: [AVAudioPCMBuffer]
    private var accepting = true
    private var finalizing = false
    private var droppedFrames: Int64 = 0
    private var writtenFrames: Int64 = 0
    private var failure: String?
    private var reportedDrop = false
    private var writeFailed = false
    private let onIssue: (String) -> Void
    private let writeBuffer: (AVAudioFile, AVAudioPCMBuffer) throws -> Void

    init(url: URL, sampleRate: Double, channels: AVAudioChannelCount,
         frameCapacity: Int, poolSize: Int = 128,
         writeBuffer: @escaping (AVAudioFile, AVAudioPCMBuffer) throws -> Void = { try $0.write(from: $1) },
         onIssue: @escaping (String) -> Void) throws {
        guard frameCapacity > 0, poolSize > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                  channels: channels, interleaved: false) else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.url = url
        self.format = format
        self.onIssue = onIssue
        self.writeBuffer = writeBuffer
        var buffers: [AVAudioPCMBuffer] = []
        for _ in 0..<poolSize {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCapacity)) else {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            buffers.append(buffer)
        }
        pool = buffers
        file = try AVAudioFile(forWriting: url, settings: format.settings)
    }

    func append(_ samples: UnsafePointer<Float>, frames: Int, channels: Int, sampleRate: Double) {
        guard frames > 0 else { return }
        lock.lock()
        guard accepting else { lock.unlock(); return }
        guard sampleRate == format.sampleRate, channels == Int(format.channelCount) else {
            droppedFrames += Int64(frames)
            failure = "Recording stopped because the audio format changed. Start a new recording for this output device."
            accepting = false
            let message = failure!
            lock.unlock()
            onIssue(message)
            return
        }
        guard let buffer = pool.popLast() else {
            droppedFrames += Int64(frames)
            let shouldReport = !reportedDrop
            reportedDrop = true
            lock.unlock()
            if shouldReport { onIssue("Recording has gaps: the disk writer could not keep up. Live playback continues.") }
            return
        }
        guard buffer.frameCapacity >= AVAudioFrameCount(frames), let data = buffer.floatChannelData else {
            pool.append(buffer)
            droppedFrames += Int64(frames)
            let shouldReport = !reportedDrop
            reportedDrop = true
            lock.unlock()
            if shouldReport { onIssue("Recording has gaps: an audio block exceeded the recording buffer capacity.") }
            return
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<channels {
            for frame in 0..<frames {
                data[channel][frame] = samples[frame * channels + channel]
            }
        }
        // Submit under the same lock used by stop(): completion cannot overtake
        // a block that has already been accepted for recording.
        writerQueue.async { [self] in
            lock.lock()
            let shouldWrite = !writeFailed
            lock.unlock()
            var newError: String?
            if shouldWrite, let file {
                do {
                    try writeBuffer(file, buffer)
                    lock.lock()
                    writtenFrames += Int64(buffer.frameLength)
                    lock.unlock()
                } catch {
                    newError = "Recording stopped: \(error.localizedDescription). The file may be incomplete."
                }
            }
            lock.lock()
            if !shouldWrite || newError != nil { droppedFrames += Int64(buffer.frameLength) }
            if let newError {
                failure = newError
                writeFailed = true
                accepting = false
            }
            pool.append(buffer)
            lock.unlock()
            if let newError { onIssue(newError) }
        }
        lock.unlock()
    }

    /// Only for application termination, never called by the audio worker.
    func waitForWrites() { writerQueue.sync {} }

    var mustStop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return failure != nil
    }

    func stop(completion: @escaping (Result) -> Void) {
        lock.lock()
        guard !finalizing else { lock.unlock(); return }
        accepting = false
        finalizing = true
        writerQueue.async { [self] in
            // All accepted writes finish before the file is released and the UI
            // receives completion. No disk wait occurs on the processing worker.
            file = nil
            lock.lock()
            pool.removeAll()
            let result = Result(url: url, writtenFrames: writtenFrames,
                droppedFrames: droppedFrames, error: failure)
            lock.unlock()
            completion(result)
        }
        lock.unlock()
    }
}
