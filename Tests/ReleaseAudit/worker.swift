import Foundation
@testable import Sonexis
setbuf(stdout,nil)
// Same worker and rings as playback, driven by a synthetic 48 kHz device clock.
let count=Int(CommandLine.arguments.dropFirst().first ?? "0")!
let engine=AudioEngine(observeSystemLifecycle:false)
engine.processTapInputTrimDB = -15;engine.processTapOutputMakeupDB=15;engine.processTapOutputCeilingEnabled=true
engine.updateEffectChain((0..<count).map{_ in var n=BeginnerNode(type:.rubberBandPitch);n.parameters.rubberBandPitchSemitones=7;return n})
engine.publishProcessingState()
let input=try RealtimeRingBuffer(capacityFrames:96000,channels:2)
let output=try RealtimeRingBuffer(capacityFrames:96000,channels:2)
output.setTargetFillFrames(4096)
let worker=ProcessTapProcessingWorker(inputRingBuffer:input,outputRingBuffer:output,processor:engine,sampleRate:48000,channels:2)
let block=[Float](repeating:0.01,count:2048)
worker.start()
for _ in 0..<4 {_=block.withUnsafeBufferPointer{input.writeInterleaved($0.baseAddress!,frames:1024)}}
let until=Date().addingTimeInterval(5)
while output.fillFrames<4096 && Date()<until {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
let start=DispatchTime.now().uptimeNanoseconds;let duration=UInt64(1024.0/48000*1e9)
var dst=[Float](repeating:0,count:2048);var lateTicks=0;var maxLateMS=0.0;var underflowTicks=0
for tick in 0..<400 {
 let target=start+UInt64(tick)*duration
 while DispatchTime.now().uptimeNanoseconds<target {RunLoop.main.run(until:Date().addingTimeInterval(0.001))}
 let late=Double(DispatchTime.now().uptimeNanoseconds-target)/1e6;maxLateMS=max(maxLateMS,late);if late>5 {lateTicks+=1}
 _=block.withUnsafeBufferPointer{input.writeInterleaved($0.baseAddress!,frames:1024)}
 let read=dst.withUnsafeMutableBufferPointer{output.readInterleaved($0.baseAddress!,frames:1024)}
 if read<1024{underflowTicks+=1}
}
worker.stop(log:false)
print("WORKER pitchNodes=\(count) durationSeconds=\(400.0*1024/48000) outputUnderflowFrames=\(output.underflowFrames) underflowTicks=\(underflowTicks) inputDroppedFrames=\(input.droppedFrames) outputDroppedFrames=\(output.droppedFrames) clockLateTicksOver5ms=\(lateTicks) maxClockLateMS=\(maxLateMS)")
