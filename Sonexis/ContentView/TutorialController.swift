import SwiftUI

final class TutorialController: ObservableObject {
    @Published var step: TutorialStep = .inactive
    @Published var hasVisitedTrayTabs = false
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @AppStorage("hasCompletedBasicsTutorial") private var hasCompletedBasicsTutorial = false
    @AppStorage("hasCompletedAdvancedTutorial") private var hasCompletedAdvancedTutorial = false
    private(set) var shouldRestoreOnEnd = false

    var isActive: Bool { step != .inactive }
    var basicsCompleted: Bool { hasCompletedBasicsTutorial }
    var advancedCompleted: Bool { hasCompletedAdvancedTutorial }

    var allowBuildAction: Bool {
        switch step {
        case .inactive, .homeBuild:
            return true
        default:
            return false
        }
    }

    var allowPresetsAction: Bool {
        step == .inactive
    }

    var allowBackAction: Bool {
        switch step {
        case .presetsBack:
            return true
        default:
            return false
        }
    }

    var isBuildStep: Bool {
        switch step {
        case .buildIntro,
             .buildTrayTabs,
             .buildHeaderIntro,
             .buildPower,
             .buildRecord,
             .buildOutput,
             .buildSettings,
             .buildSettingsExplain,
             .buildAddBass,
             .buildAutoExplain,
             .buildAutoAddClarity,
             .buildAutoReorder,
             .buildDoubleClick,
             .buildEffectControls,
             .buildCloseOverlay,
             .buildRightClick,
             .buildActionMenu,
             .buildCloseContextMenu,
             .basicsComplete,
             .advancedIntro,
             .advancedComplete,
             .buildManualExplain,
             .buildWiringManual,
             .buildConnect,
             .buildAutoConnectEnd,
             .buildResetWiringForParallel,
             .buildParallelExplain,
             .buildParallelAddReverb,
             .buildParallelConnect,
             .buildClearCanvasForDualMono,
             .buildGraphMode,
             .buildDualMonoAdd,
             .buildDualMonoConnect,
             .buildReturnStereoAuto,
             .buildSave,
             .buildSaveConfirm,
             .buildLoad,
             .buildCloseLoad,
             .buildFinish:
            return true
        default:
            return false
        }
    }

    func startIfNeeded(isSetupVisible: Bool) {
        guard !hasSeenTutorial, !isSetupVisible, !isActive else { return }
        startBasics()
        hasSeenTutorial = true
    }

    func startBasics() {
        shouldRestoreOnEnd = true
        step = .welcome
        hasVisitedTrayTabs = false
    }

    func startAdvanced() {
        shouldRestoreOnEnd = true
        step = .advancedIntro
        hasVisitedTrayTabs = false
    }

    func continueToAdvanced() {
        hasCompletedBasicsTutorial = true
        shouldRestoreOnEnd = false
        step = .advancedIntro
        hasVisitedTrayTabs = false
    }

    func advance() {
        switch step {
        case .welcome:
            step = .homeBuild
        case .homePresets:
            step = .presetsExplore
        case .presetsExplore:
            step = .presetsBack
        case .presetsBack:
            step = .homeBuild
        case .homeBuild:
            step = .buildIntro
        case .buildIntro:
            step = .buildTrayTabs
            hasVisitedTrayTabs = false
        case .buildTrayTabs:
            step = .buildPower
        case .buildPower:
            step = .buildAddBass
        case .buildAddBass:
            step = .buildAutoAddClarity
        case .buildAutoAddClarity:
            step = .buildAutoReorder
        case .buildAutoReorder:
            step = .buildAutoExplain
        case .buildAutoExplain:
            step = .buildDoubleClick
        case .buildDoubleClick:
            step = .buildEffectControls
        case .buildEffectControls:
            step = .buildCloseOverlay
        case .buildCloseOverlay:
            step = .buildRightClick
        case .buildRightClick:
            step = .buildActionMenu
        case .buildActionMenu:
            step = .buildSettings
        case .buildCloseContextMenu:
            step = .buildSettings
        case .buildSettings:
            step = .buildSettingsExplain
        case .buildSettingsExplain:
            step = .buildSave
        case .buildSave:
            step = .buildSaveConfirm
        case .buildSaveConfirm:
            step = .buildLoad
        case .buildLoad:
            step = .basicsComplete
        case .basicsComplete:
            finishTutorial()
        case .advancedIntro:
            step = .buildWiringManual
        case .buildManualExplain:
            step = .buildWiringManual
        case .buildWiringManual:
            step = .buildConnect
        case .buildConnect:
            step = .buildAutoConnectEnd
        case .buildAutoConnectEnd:
            step = .buildResetWiringForParallel
        case .buildResetWiringForParallel:
            step = .buildParallelExplain
        case .buildParallelExplain:
            step = .buildParallelAddReverb
        case .buildParallelAddReverb:
            step = .buildParallelConnect
        case .buildParallelConnect:
            step = .buildClearCanvasForDualMono
        case .buildClearCanvasForDualMono:
            step = .buildGraphMode
        case .buildGraphMode:
            step = .buildDualMonoAdd
        case .buildDualMonoAdd:
            step = .buildDualMonoConnect
        case .buildDualMonoConnect:
            step = .buildReturnStereoAuto
        case .buildReturnStereoAuto:
            step = .advancedComplete
        case .advancedComplete:
            finishTutorial(completedAdvanced: true)
        case .buildHeaderIntro:
            step = .buildPower
        case .buildRecord:
            step = .buildOutput
        case .buildOutput:
            step = .buildSettings
        case .buildCloseLoad:
            step = .buildFinish
        case .buildFinish:
            finishTutorial()
        case .inactive:
            break
        }
    }

    func handlePresetsClick() {
        if step == .homePresets { step = .presetsExplore }
    }

    func handleBuildClick() {
        if step == .homeBuild {
            step = .buildIntro
        }
    }

    func handleBackClick() {
        if step == .presetsBack {
            step = .homeBuild
        }
    }

    func advanceIf(_ expected: TutorialStep) {
        if step == expected {
            advance()
        }
    }

    func endTutorial() {
        shouldRestoreOnEnd = false
        step = .inactive
    }

    func skipTutorial() {
        shouldRestoreOnEnd = true
        step = .inactive
    }

    func finishTutorial(completedAdvanced: Bool = false) {
        if step == .basicsComplete || completedAdvanced {
            hasCompletedBasicsTutorial = true
        }
        if completedAdvanced {
            hasCompletedAdvancedTutorial = true
        }
        shouldRestoreOnEnd = false
        step = .inactive
    }
}
