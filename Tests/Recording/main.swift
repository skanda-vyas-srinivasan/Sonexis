import AVFoundation
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
func finish(_ session: AudioRecordingSession) -> AudioRecordingSession.Result {
    let done = DispatchSemaphore(value: 0)
    var result: AudioRecordingSession.Result?
    session.stop { value in result = value; done.signal() }
    expect(done.wait(timeout: .now() + 5) == .success, "Recording did not finish")
    return result!
}
func append(_ samples: [Float], to session: AudioRecordingSession, rate: Double = 48_000, channels: Int = 2) {
    samples.withUnsafeBufferPointer {
        session.append($0.baseAddress!, frames: samples.count / channels, channels: channels, sampleRate: rate)
    }
}
func read(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(max(file.length, 1)))!
    try file.read(into: buffer)
    return (0..<Int(buffer.frameLength)).flatMap { frame in
        (0..<Int(buffer.format.channelCount)).map { buffer.floatChannelData![$0][frame] }
    }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("Sonexis-recording-tests-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

// Different sizes/channels verify exact copying, order and no stale tail samples.
let first: [Float] = [0.25, -0.5, 0.95, -0.95, 0, 0.1]
let second: [Float] = [-0.2, 0.7]
let exact = try AudioRecordingSession(url: root.appendingPathComponent("exact.wav"), sampleRate: 48_000,
    channels: 2, frameCapacity: 1024, onIssue: { fatalError($0) })
append(first, to: exact)
append(second, to: exact)
let exactResult = finish(exact)
expect(exactResult.writtenFrames == 4 && exactResult.droppedFrames == 0 && exactResult.error == nil, "Exact recording metrics incorrect")
let exactSamples = try read(exactResult.url)
expect(exactSamples == first + second, "Saved samples must exactly match final output input")
append(first, to: exact)
let afterStop = try read(exactResult.url)
expect(afterStop == exactSamples, "Stopped recording must reject later samples")

// Block the writer deterministically: append/stop must return without waiting on disk.
let entered = DispatchSemaphore(value: 0)
let release = DispatchSemaphore(value: 0)
let overloaded = try AudioRecordingSession(url: root.appendingPathComponent("overload.wav"), sampleRate: 48_000,
    channels: 2, frameCapacity: 1024, poolSize: 1,
    writeBuffer: { file, buffer in
        entered.signal()
        _ = release.wait(timeout: .now() + 5)
        try file.write(from: buffer)
    }, onIssue: { _ in })
append(first, to: overloaded)
expect(entered.wait(timeout: .now() + 5) == .success, "Writer not entered")
append(second, to: overloaded)
let completed = DispatchSemaphore(value: 0)
var overloadResult: AudioRecordingSession.Result?
overloaded.stop { overloadResult = $0; completed.signal() }
expect(completed.wait(timeout: .now() + 0.05) == .timedOut, "Stop must wait for queued writes before reporting completion")
release.signal()
expect(completed.wait(timeout: .now() + 5) == .success, "Queued writer did not drain")
expect(overloadResult?.droppedFrames == 1 && overloadResult?.writtenFrames == 3, "Pool exhaustion must count dropped frames")
let overloadSamples = try read(overloadResult!.url)
expect(overloadSamples == first, "Accepted audio must survive writer overload")

// A temporary writer stall must be absorbed by the default reserve. This
// models scheduler/filesystem pauses without ever blocking or allocating in
// the real-time append path.
let stalledWriterEntered = DispatchSemaphore(value: 0)
let releaseStalledWriter = DispatchSemaphore(value: 0)
var isFirstStalledWrite = true
let buffered = try AudioRecordingSession(url: root.appendingPathComponent("buffered-stall.wav"), sampleRate: 48_000,
    channels: 2, frameCapacity: 1024,
    writeBuffer: { file, buffer in
        if isFirstStalledWrite {
            isFirstStalledWrite = false
            stalledWriterEntered.signal()
            _ = releaseStalledWriter.wait(timeout: .now() + 5)
        }
        try file.write(from: buffer)
    }, onIssue: { fatalError($0) })
append(first, to: buffered)
expect(stalledWriterEntered.wait(timeout: .now() + 5) == .success, "Buffered writer not entered")
for index in 0..<96 {
    append([Float(index) / 100, -Float(index) / 100], to: buffered)
}
releaseStalledWriter.signal()
let bufferedResult = finish(buffered)
expect(bufferedResult.droppedFrames == 0 && bufferedResult.writtenFrames == 99,
       "Default recording reserve must absorb a temporary writer stall")
let bufferedSamples = try read(bufferedResult.url)
expect(bufferedSamples.count == 198, "Buffered stall recording must retain every sample")

let oversized = try AudioRecordingSession(url: root.appendingPathComponent("oversized.wav"), sampleRate: 48_000,
    channels: 2, frameCapacity: 2, onIssue: { _ in })
append(first, to: oversized)
append(second, to: oversized)
let oversizedResult = finish(oversized)
expect(oversizedResult.droppedFrames == 3 && oversizedResult.writtenFrames == 1, "Oversized block must be reported and pool recycled")

let changed = try AudioRecordingSession(url: root.appendingPathComponent("format.wav"), sampleRate: 48_000,
    channels: 2, frameCapacity: 1024, onIssue: { _ in })
append(first, to: changed)
append(second, to: changed, rate: 44_100)
expect(changed.mustStop, "Format change must request stop")
let changedResult = finish(changed)
expect(changedResult.error != nil && changedResult.droppedFrames == 1, "Format error must be visible")
let changedSamples = try read(changedResult.url)
expect(changedSamples == first, "Already accepted blocks must finish after a format change")

let failed = try AudioRecordingSession(url: root.appendingPathComponent("failed.wav"), sampleRate: 48_000,
    channels: 2, frameCapacity: 1024,
    writeBuffer: { _, _ in throw CocoaError(.fileWriteOutOfSpace) }, onIssue: { _ in })
append(first, to: failed)
let failedResult = finish(failed)
expect(failedResult.error != nil && failedResult.droppedFrames == 3, "Disk failure must report incomplete recording")
expect(failedResult.writtenFrames == 0, "Failed write cannot count as written")

let mono = try AudioRecordingSession(url: root.appendingPathComponent("mono.wav"), sampleRate: 44_100,
    channels: 1, frameCapacity: 1024, onIssue: { fatalError($0) })
append([0.1, -0.2, 0.3], to: mono, rate: 44_100, channels: 1)
let monoResult = finish(mono)
let monoSamples = try read(monoResult.url)
expect(monoSamples == [0.1, -0.2, 0.3], "Fresh mono session must not inherit previous errors or state")
print("PASS: exact WAV samples/order, variable blocks, stop/drain, post-stop rejection, buffered writer stalls, bounded overload, oversize recovery, format changes, disk failures, independent mono session")
