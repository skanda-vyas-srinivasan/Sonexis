import Foundation
import AVFoundation
import CoreAudio
@testable import Sonexis

setbuf(stdout, nil)

// Captures only the generated audit tone's process; never the user's global mix.
final class Probe: ProcessTapAudioProcessor {
 let engine=AudioEngine(observeSystemLifecycle:false)
 let lock=NSLock()
 var samples=0, active=0, callbacks=0, zeros=0, maxZeros=0
 var peak:Float=0
 var gaps=0
 func processTapFormatDidChange(maxFrameCount:Int,channelCount:Int,sampleRate:Double){engine.processTapFormatDidChange(maxFrameCount:maxFrameCount,channelCount:channelCount,sampleRate:sampleRate)}
 func processTapAudioGapDetected(fillFrames:UInt32,droppedFrames:UInt64,underflowFrames:UInt64){lock.lock();gaps+=1;lock.unlock();print("GAP fill=\(fillFrames) dropped=\(droppedFrames) underflow=\(underflowFrames)")}
 func processSystemAudio(input:UnsafePointer<Float>,output:UnsafeMutablePointer<Float>,frameCount:Int,channelCount:Int,sampleRate:Double){
  engine.processSystemAudio(input:input,output:output,frameCount:frameCount,channelCount:channelCount,sampleRate:sampleRate)
  lock.lock();defer{lock.unlock()};callbacks+=1;samples+=frameCount
  for f in 0..<frameCount {var p:Float=0;for c in 0..<channelCount{p=max(p,abs(input[f*channelCount+c]));peak=max(peak,abs(output[f*channelCount+c]))};if p>0.000001{active+=1;maxZeros=max(maxZeros,zeros);zeros=0}else{zeros+=1}}
 }
 func summary(_ label:String){lock.lock();defer{lock.unlock()};print("LIVE \(label): callbacks=\(callbacks) frames=\(samples) nonzeroInputFrames=\(active) longestInputZeroRun=\(max(maxZeros,zeros)) peak=\(peak) gapWarnings=\(gaps)")}
}
let root=FileManager.default.temporaryDirectory.appendingPathComponent("sonexis-live-audit-\(UUID().uuidString)")
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
defer{try? FileManager.default.removeItem(at:root)}
let wav=root.appendingPathComponent("quiet-audit-tone.wav")
let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
let f=try AVAudioFile(forWriting:wav,settings:format.settings)
let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!
buffer.frameLength=48000
for i in 0..<48000 {for c in 0..<2 {buffer.floatChannelData![c][i]=0.005*Float(sin(2*Double.pi*440*Double(i)/48000))}}
for _ in 0..<30 {try f.write(from:buffer)}
let player=Process();player.executableURL=URL(fileURLWithPath:"/usr/bin/afplay");player.arguments=[wav.path]
try player.run();defer{if player.isRunning{player.terminate();player.waitUntilExit()}}
RunLoop.main.run(until:Date().addingTimeInterval(0.5))
guard let id=try CoreAudioSupport.processObjectID(forPID:player.processIdentifier) else{throw PrototypeError(message:"Generated tone process missing from HAL")}
print("AUDIT SOURCE resolved PID=\(player.processIdentifier) object=\(id)")
let probe=Probe();probe.engine.processTapInputTrimDB=0;probe.engine.processTapOutputMakeupDB=0;probe.engine.processTapOutputCeilingEnabled=true;probe.engine.updateEffectChain([]);probe.engine.publishProcessingState()
let pipeline=ProcessTapDSPEngine(audioProcessor:probe,fixedSelection:.only([id]))
try pipeline.start();defer{pipeline.stopImmediately(reason:"Sonexis release audit cleanup")}
RunLoop.main.run(until:Date().addingTimeInterval(3));probe.summary("neutral")
probe.engine.updateEffectChain([BeginnerNode(type:.bassBoost)]);probe.engine.publishProcessingState()
RunLoop.main.run(until:Date().addingTimeInterval(3));probe.summary("effect edit")
pipeline.stopImmediately(reason:"Sonexis release audit restart")
try pipeline.start();RunLoop.main.run(until:Date().addingTimeInterval(3));probe.summary("restart")
