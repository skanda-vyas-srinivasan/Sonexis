import SwiftUI

enum TutorialTarget: Hashable {
    case buildButton
    case presetsButton
    case backButton
    case buildGraphMode
    case buildWiringMode
    case buildAutoConnectEnd
    case buildCanvasMenu
    case buildBassBoost
    case buildClarity
    case buildReverb
    case buildCanvas
    case buildSave
    case buildLoad
    case buildBassNode
    case buildClarityNode
    case buildReverbNode
    case buildPower
    case buildShield
    case buildOutput
}

struct TutorialTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [TutorialTarget: CGRect] = [:]

    static func reduce(value: inout [TutorialTarget: CGRect], nextValue: () -> [TutorialTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum TutorialStep: Equatable {
    case inactive
    case welcome
    case homePresets
    case presetsExplore
    case presetsBack
    case homeBuild
    case buildIntro
    case buildHeaderIntro
    case buildPower
    case buildShield
    case buildOutput
    case buildAddBass
    case buildAutoExplain
    case buildAutoAddClarity
    case buildAutoReorder
    case buildManualExplain
    case buildDoubleClick
    case buildCloseOverlay
    case buildRightClick
    case buildCloseContextMenu
    case buildWiringManual
    case buildConnect
    case buildAutoConnectEnd
    case buildResetWiringForParallel
    case buildParallelExplain
    case buildParallelAddReverb
    case buildParallelConnect
    case buildClearCanvasForDualMono
    case buildGraphMode
    case buildDualMonoAdd
    case buildDualMonoConnect
    case buildReturnStereoAuto
    case buildSave
    case buildSaveConfirm
    case buildLoad
    case buildCloseLoad
    case buildFinish
}

