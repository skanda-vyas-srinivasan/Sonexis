import Foundation
import AVFoundation
@testable import Sonexis

// Runs only offline; never opens a Process Tap or playback device.
func publish() { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }
func makeEngine(_ nodes: [BeginnerNode], ceiling: Bool = false) -> AudioEngine {
    let e = AudioEngine()
    e.processTapInputTrimDB = -15
    e.processTapOutputMakeupDB = 15
    e.processTapOutputCeilingEnabled = ceiling
    e.updateEffectChain(nodes)
    e.publishProcessingState()
    publish()
    return e
}
func render(_ e: AudioEngine, _ input: [Float], channels: Int, rate: Double) -> [Float] {
    var out = [Float](repeating: -999, count: input.count)
    input.withUnsafeBufferPointer { src in out.withUnsafeMutableBufferPointer { dst in
        e.processSystemAudio(input: src.baseAddress!, output: dst.baseAddress!, frameCount: input.count/channels, channelCount: channels, sampleRate: rate)
    }}
    return out
}
func signal(_ frames: Int, channels: Int, rate: Double, offset: Int = 0, amplitude: Float = 0.8) -> [Float] {
    (0..<frames*channels).map { i in
        let frequency = i % channels == 0 ? 997.0 : 173.0
        return amplitude * Float(sin(2 * Double.pi * frequency * Double(i/channels+offset)/rate))
    }
}
func emit(_ row: [String:Any]) {
    let d = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    print(String(data:d,encoding:.utf8)!); fflush(stdout)
}
let mode = CommandLine.arguments.dropFirst().first ?? "sweep"
if mode == "malformed" {
    let parameter = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "bitcrusherBitDepth"
    let effectName = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "Bitcrusher"
    let json = """
    {"name":"Audit malformed parameter","graph":{"nodes":[{"type":"\(effectName)","parameters":{"\(parameter)":1e100}}]}}
    """
    let p = try decodePresetImportData(Data(json.utf8))
    try p.graph.validateForIndependentProcessing()
    emit(["phase":"import and independent graph validation accepted", "parameter":parameter, "value":1e100])
    let e=makeEngine([]); e.applyIndependentGraph(p.graph); publish()
    _=render(e,signal(1024,channels:2,rate:48000),channels:2,rate:48000)
    emit(["phase":"render returned"])
} else if mode == "sweep" {
    for type in EffectType.allCases where type != .plugin && !type.isRetired {
        for channels in [1,2] { for rate in [44100.0,48000.0,96000.0] {
            let e=makeEngine([BeginnerNode(type:type)])
            var peak:Float=0; var nonfinite=0; var count=0; var clipped=0
            for block in 0..<24 {
                let frames=[1,17,128,1024,4096,31][block%6]
                let out=render(e,signal(frames,channels:channels,rate:rate,offset:count),channels:channels,rate:rate)
                for x in out { if !x.isFinite { nonfinite+=1 } else { peak=max(peak,abs(x)); if abs(x)>1 {clipped+=1} } }
                count+=frames; publish()
            }
            emit(["case":"effect-sweep","effect":type.rawValue,"channels":channels,"sampleRate":rate,"frames":count,"peak":Double(peak),"nonfinite":nonfinite,"aboveFullScale":clipped])
        }}
    }
} else if mode == "ceiling" {
    for enabled in [false,true] {
        let e=makeEngine([BeginnerNode(type:.bassBoost),BeginnerNode(type:.bassBoost)],ceiling:enabled)
        var peak:Float=0; var nonfinite=0
        for block in 0..<200 {
            var input=signal(1024,channels:2,rate:48000,offset:block*1024,amplitude:1)
            if block==100 { input[0] = .nan; input[1] = .infinity; input[2] = -.infinity }
            let out=render(e,input,channels:2,rate:48000)
            for x in out { if !x.isFinite {nonfinite+=1} else {peak=max(peak,abs(x))} }
            publish()
        }
        let recovery=render(e,signal(1024,channels:2,rate:48000),channels:2,rate:48000)
        emit(["case":"ceiling-and-nonfinite","ceiling":enabled,"peak":Double(peak),"nonfinite":nonfinite,"recoveredNonzero":recovery.contains{abs($0)>0.001}])
    }
} else if mode == "edits" {
    let e=makeEngine([]); var worst:Float=0;var zeros=0; var samples=0
    for step in 0..<1000 {
        let nodes=(0..<(step%12)).map { _ in BeginnerNode(type:.simpleEQ,isEnabled:false) }
        e.updateEffectChain(nodes); e.publishProcessingState()
        let out=render(e,[Float](repeating:0.1,count:2048),channels:2,rate:48000)
        for x in out { worst=max(worst,abs(x-0.1)); if x == 0 {zeros+=1} };samples+=out.count
        publish()
    }
    emit(["case":"1000-neutral-graph-edits","samples":samples,"worstDeviation":Double(worst),"zeroSamples":zeros])
} else if mode == "performance" {
    for type in [EffectType.simpleEQ,.bassBoost,.reverb,.rubberBandPitch] {
        for count in [1,4,16,48] {
            let e=makeEngine((0..<count).map{_ in var n=BeginnerNode(type:type); if type == .rubberBandPitch { n.parameters.rubberBandPitchSemitones = 7 }; return n })
            let input=signal(1024,channels:2,rate:48000,amplitude:0.02)
            for _ in 0..<12 {_=render(e,input,channels:2,rate:48000);publish()}
            var times:[Double]=[]
            for _ in 0..<100 {
                let begin=DispatchTime.now().uptimeNanoseconds
                _=render(e,input,channels:2,rate:48000)
                times.append(Double(DispatchTime.now().uptimeNanoseconds-begin)/1e6)
                publish()
            }
            times.sort()
            emit(["case":"offline-render-performance","effect":type.rawValue,"nodes":count,"frames":1024,"sampleRate":48000,"medianMS":times[50],"p95MS":times[95],"maxMS":times.last!,"blockBudgetMS":1024.0/48,"overBudgetBlocks":times.filter{$0>1024.0/48}.count])
        }
    }
} else if mode == "pitch-gaps" {
    for semitones in [0.0, 7.0, -7.0] {
        var n=BeginnerNode(type:.rubberBandPitch); n.parameters.rubberBandPitchSemitones=semitones
        let e=makeEngine([n]); var maxRun=0; var run=0; var onset:Int?=nil; var zerosAfterWarmup=0
        for b in 0..<400 {
            let out=render(e,signal(1024,channels:2,rate:48000,offset:b*1024,amplitude:0.1),channels:2,rate:48000)
            for i in stride(from:0,to:out.count,by:2) {
                let frame=b*1024+i/2
                if abs(out[i])+abs(out[i+1]) < 0.00000001 {run+=1;if frame>96000 {zerosAfterWarmup+=1}} else {if onset==nil{onset=frame};maxRun=max(maxRun,run);run=0}
            }
            publish()
        }
        emit(["case":"pitch-continuity","semitones":semitones,"firstNonzeroFrame":onset ?? -1,"longestSilenceFrames":max(maxRun,run),"zeroFramesAfterTwoSeconds":zerosAfterWarmup])
    }
} else if mode == "pitch-edit" {
    for rate in [44100.0,48000.0] {
        var n=BeginnerNode(type:.rubberBandPitch)
        let e=makeEngine([n]);var all:[Float]=[]
        for b in 0..<40 {all += render(e,signal(1024,channels:2,rate:rate,offset:b*1024,amplitude:0.1),channels:2,rate:rate);publish()}
        n.parameters.rubberBandPitchSemitones=7
        e.updateEffectChain([n]);e.publishProcessingState()
        var run=0,maxRun=0,firstSound:Int?=nil
        for b in 0..<150 {
            let out=render(e,signal(1024,channels:2,rate:rate,offset:(b+40)*1024,amplitude:0.1),channels:2,rate:rate);all+=out
            for i in stride(from:0,to:out.count,by:2){if abs(out[i])+abs(out[i+1])<0.00000001{run+=1}else{maxRun=max(maxRun,run);run=0;if firstSound==nil{firstSound=b*1024+i/2}}};publish()
        }
        emit(["case":"live-parameter-change-offline","rate":rate,"fromSemitones":0,"toSemitones":7,"longestSilentFrames":max(maxRun,run),"silenceMS":Double(max(maxRun,run))*1000/rate,"firstSoundAfterEditFrame":firstSound ?? -1])
        if rate == 48000 {
            let outputPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "docs/release-2.1.0-evidence/pitch-edit-output.wav"
            let url=URL(fileURLWithPath:outputPath)
            let fmt=AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!
            let file=try AVAudioFile(forWriting:url,settings:fmt.settings)
            let buf=AVAudioPCMBuffer(pcmFormat:fmt,frameCapacity:AVAudioFrameCount(all.count/2))!;buf.frameLength=buf.frameCapacity
            for f in 0..<all.count/2 {for c in 0..<2 {buf.floatChannelData![c][f]=all[f*2+c]}}
            try file.write(from:buf)
        }
    }
} else if mode == "seed" {
    let path=CommandLine.arguments[2]
    let presets=try JSONDecoder().decode([SavedPreset].self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    for p in presets {
        try p.graph.validateForIndependentProcessing()
        let e=makeEngine([]);e.applyIndependentGraph(p.graph);publish()
        var peak:Float=0
        for b in 0..<100 {for x in render(e,signal(1024,channels:2,rate:48000,offset:b*1024,amplitude:0.1),channels:2,rate:48000) {peak=max(peak,abs(x))};publish()}
        emit(["case":"starter-preset","name":p.name,"nodes":p.graph.nodes.count,"peakAtMinus20DBFS":Double(peak)])
    }
}
