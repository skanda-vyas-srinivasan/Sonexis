import Foundation
import Darwin
@testable import Sonexis
setbuf(stdout,nil)
func memory()->Int64{var u=rusage();getrusage(RUSAGE_SELF,&u);return Int64(u.ru_maxrss)}
func tick(){RunLoop.main.run(until:Date().addingTimeInterval(0.001))}
let sharedID=UUID()
let engines=(0..<4).map{ index -> AudioEngine in
 let e=AudioEngine(observeSystemLifecycle:false)
 let type:EffectType = index==0 ? .simpleEQ : index==1 ? .delay : index==2 ? .reverb : .chorus
 let encoded=try! JSONSerialization.data(withJSONObject:["id":sharedID.uuidString,"type":type.rawValue])
 let n=try! JSONDecoder().decode(BeginnerNode.self,from:encoded)
 e.processTapInputTrimDB = -15;e.processTapOutputMakeupDB=15;e.processTapOutputCeilingEnabled=true;e.updateEffectChain([n]);e.publishProcessingState();return e
}
let input=(0..<2048).map{Float(sin(Double($0/2)*0.07))*0.1}
let silence=[Float](repeating:0,count:2048)
var output=[Float](repeating:0,count:2048)
var nonfinite=0, leaked=0;var peak:Float=0
let start=DispatchTime.now().uptimeNanoseconds
for b in 0..<10000 {
 for (i,e) in engines.enumerated(){let source=i==3 ? silence:input
  source.withUnsafeBufferPointer{src in output.withUnsafeMutableBufferPointer{dst in e.processSystemAudio(input:src.baseAddress!,output:dst.baseAddress!,frameCount:1024,channelCount:2,sampleRate:48000)}}
  for x in output{if !x.isFinite{nonfinite+=1};peak=max(peak,abs(x));if i==3 && abs(x)>1e-8{leaked+=1}}
 }
 if b%16==0{tick()}
 if [99,999,4999,9999].contains(b){print("LONGRUN blocksPerChain=\(b+1) maxRSS=\(memory()) nonfinite=\(nonfinite) silentChainLeakedSamples=\(leaked) peak=\(peak)")}
}
print("LONGRUN completed 40,960,000 audio frames across four independent processors with identical node UUIDs; wallSeconds=\(Double(DispatchTime.now().uptimeNanoseconds-start)/1e9)")
