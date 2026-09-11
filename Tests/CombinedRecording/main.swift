import AVFoundation
@testable import Sonexis

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}

func emptyGraph() -> GraphSnapshot {
    GraphSnapshot(
        graphMode: .single,
        wiringMode: .automatic,
        nodes: [],
        connections: [],
        startNodeID: UUID(),
        endNodeID: UUID(),
        leftStartNodeID: UUID(),
        leftEndNodeID: UUID(),
        rightStartNodeID: UUID(),
        rightEndNodeID: UUID()
    )
}

func render(_ engine: AudioEngine, value: Float, frames: Int = 256,
            channels: Int = 2, sampleRate: Double = 48_000) {
    let input = [Float](repeating: value, count: frames * channels)
    var output = [Float](repeating: 0, count: input.count)
    input.withUnsafeBufferPointer { source in
        output.withUnsafeMutableBufferPointer { destination in
            engine.processSystemAudio(
                input: source.baseAddress!,
                output: destination.baseAddress!,
                frameCount: frames,
                channelCount: channels,
                sampleRate: sampleRate
            )
        }
    }
}

let defaultID = UUID()
let appID = UUID()
let runtime = MultiChainAudioEngine()
try runtime.configure([
    AudioChainDefinition(id: defaultID, target: nil, graph: emptyGraph(), effectsEnabled: true),
    AudioChainDefinition(
        id: appID,
        target: AudioCaptureTarget(bundleID: "com.sonexis.recording-test", name: "Recording Test", bundlePath: "/Applications/Recording Test.app"),
        graph: emptyGraph(),
        effectsEnabled: true
    )
])

let defaultProcessor = runtime.processors[defaultID]!
let appProcessor = runtime.processors[appID]!
for processor in [defaultProcessor, appProcessor] {
    processor.processTapInputTrimDB = 0
    processor.processTapOutputMakeupDB = 0
    processor.processTapOutputCeilingEnabled = false
}

// Prime both format snapshots before recording starts.
render(defaultProcessor, value: 0.1)
render(appProcessor, value: 0.2)

let root = FileManager.default.temporaryDirectory.appendingPathComponent("Sonexis-combined-recording-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let url = root.appendingPathComponent("combined.wav")

runtime.startRecording(url: url)
expect(runtime.isRecording, "Combined recording did not start")
for _ in 0..<60 {
    render(defaultProcessor, value: 0.1)
    render(appProcessor, value: 0.2)
}
runtime.stopRecording()
let deadline = Date().addingTimeInterval(5)
while runtime.isFinalizingRecording && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
}
expect(!runtime.isFinalizingRecording, "Combined recording did not finalize")
expect(runtime.recordingWarningText == nil, runtime.recordingWarningText ?? "Combined recording reported a warning")

let file = try AVAudioFile(forReading: url)
let buffer = AVAudioPCMBuffer(
    pcmFormat: file.processingFormat,
    frameCapacity: AVAudioFrameCount(file.length)
)!
try file.read(into: buffer)
expect(buffer.frameLength > 0, "Combined recording is empty")
let samples = (0..<Int(buffer.frameLength)).flatMap { frame in
    (0..<2).map { channel in buffer.floatChannelData![channel][frame] }
}
let audible = samples.filter { abs($0) > 0.001 }
expect(!audible.isEmpty, "Combined recording contains only silence")
expect(audible.allSatisfy { abs($0 - 0.3) < 0.0001 }, "Combined recording did not sum both chain outputs")

// A process tap may produce no callbacks while its app is silent. That input
// contributes silence without stalling the recording or reporting fake loss.
let silentChainURL = root.appendingPathComponent("silent-chain.wav")
runtime.startRecording(url: silentChainURL)
expect(runtime.isRecording, "Silent-chain recording did not start")
for _ in 0..<60 {
    render(defaultProcessor, value: 0.1)
    RunLoop.main.run(until: Date().addingTimeInterval(0.006))
}
runtime.stopRecording()
let silentChainDeadline = Date().addingTimeInterval(5)
while runtime.isFinalizingRecording && Date() < silentChainDeadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
}
expect(!runtime.isFinalizingRecording, "Silent-chain recording did not finalize")
expect(runtime.recordingWarningText == nil,
       runtime.recordingWarningText ?? "Silent chain produced a false missing-frames warning")
let silentChainFile = try AVAudioFile(forReading: silentChainURL)
expect(silentChainFile.length > 0, "Silent-chain recording is empty")

// A chain that changes to an incompatible format must stop/refuse recording,
// never disappear silently from the combined file.
render(defaultProcessor, value: 0.1, sampleRate: 48_000)
render(appProcessor, value: 0.2, sampleRate: 44_100)
runtime.startRecording(url: root.appendingPathComponent("mismatch.wav"))
expect(!runtime.isRecording, "Mixed-format recording should not start")
expect(runtime.recordingWarningText?.contains("different audio formats") == true,
       "Mixed-format recording did not explain why it was refused")

print("PASS: two-chain output is summed into one file; incompatible chain formats are refused visibly")
