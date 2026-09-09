import CoreAudio

/// A resolved capture partition. Multi-chain routing resolves all partitions
/// together; individual pipelines must not discover or broaden their own scope.
struct ProcessTapSelection: Equatable {
    let isExclusive: Bool
    let processIDs: [AudioObjectID]

    static func allAudio(excluding ids: Set<AudioObjectID>) -> Self {
        Self(isExclusive: true, processIDs: ids.sorted())
    }

    static func only(_ ids: Set<AudioObjectID>) -> Self {
        Self(isExclusive: false, processIDs: ids.sorted())
    }

    func safeProcessIDs(ownProcessID: AudioObjectID) -> [AudioObjectID] {
        var ids = Set(processIDs.filter { $0 != kAudioObjectUnknown })
        if isExclusive { ids.insert(ownProcessID) } else { ids.remove(ownProcessID) }
        return ids.sorted()
    }
}
