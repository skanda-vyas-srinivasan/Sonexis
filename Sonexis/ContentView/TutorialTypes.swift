import SwiftUI

enum TutorialTarget: Hashable {
    case chainTabs
    case practiceChainTab
    case addAppChain
    case chainBypass
    case inputGain
    case outputGain
    case ceiling
    case settingsStrip
    case flow
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
    case buildTrayTabs
    case buildSave
    case buildLoad
    case buildBassNode
    case buildClarityNode
    case buildReverbNode
    case buildPower
    case buildRecord
    case buildOutput
    case buildSettings
    case buildEffectControls
    case buildActionMenu
    case basicsComplete
    case advancedIntro
    case advancedComplete
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
    case buildTrayTabs
    case buildHeaderIntro
    case buildPower
    case buildRecord
    case buildOutput
    case buildSettings
    case buildSettingsExplain
    case buildOutputGain
    case buildCeiling
    case buildSettingsSummary
    case buildLibrary
    case buildPresetLibrary
    case buildBypass
    case buildDisconnected
    case buildFlow
    case buildWireLevels
    case buildSelection
    case chainsIntro
    case chainsAdd
    case chainsOverrides
    case chainsClose
    case chainsMenuBar
    case chainsBackground
    case chainsComplete
    case chainsChoosePreset
    case chainsDisable
    case chainsEnable
    case chainsOpenEditor
    case buildAddBass
    case buildAutoExplain
    case buildAutoAddClarity
    case buildAutoReorder
    case buildManualExplain
    case buildDoubleClick
    case buildEffectControls
    case buildCloseOverlay
    case buildRightClick
    case buildActionMenu
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
    case basicsComplete
    case advancedIntro
    case advancedComplete
    case buildFinish
}

extension TutorialStep {
    // Settings is intentionally an explanation; all other live lesson steps
    // require the corresponding action. Introductions and endings are navigation.
    var allowsNextButton: Bool {
        isAudioSettingsExplanation || [.welcome, .advancedIntro, .chainsIntro, .advancedComplete].contains(self)
    }

    var isAudioSettingsExplanation: Bool {
        [.buildSettingsExplain, .buildOutputGain, .buildCeiling, .buildSettingsSummary].contains(self)
    }

    var showsAudioSettings: Bool {
        self == .buildSettings || isAudioSettingsExplanation
    }
}

extension View {
    func tutorialTarget(_ target: TutorialTarget) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: TutorialTargetPreferenceKey.self,
                                   value: [target: proxy.frame(in: .global)])
        })
    }
}
