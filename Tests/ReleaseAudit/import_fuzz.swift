import Foundation
@testable import Sonexis
var accepted=0,rejected=0
let values:[Any]=[NSNull(),true,false,0,-1,1e100,"invalid",[],[:], [1,2,3]]
let fields=["nodes","connections","graphMode","wiringMode","startNodeID","endNodeID","hasNodeParameters","autoGainOverrides"]
for iteration in 0..<2000 {
 let field=fields[iteration%fields.count]
 var graph:[String:Any]=["nodes":[],"connections":[]]
 graph[field]=values[(iteration/fields.count)%values.count]
 let object:[String:Any]=["name":"Audit","graph":graph]
 let data=try JSONSerialization.data(withJSONObject:object)
 do {let p=try decodePresetImportData(data);try p.graph.validateForIndependentProcessing();accepted+=1}catch{rejected+=1}
}
var truncatedRejected=0
let good=Data("{\"name\":\"Audit\",\"graph\":{\"nodes\":[]}}".utf8)
for length in 0..<good.count {do{_=try decodePresetImportData(good.prefix(length))}catch{truncatedRejected+=1}}
print("IMPORT_FUZZ cases=2000 accepted=\(accepted) rejected=\(rejected) truncatedRejected=\(truncatedRejected)/\(good.count); no render/no storage writes")
