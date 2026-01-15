import SwiftUI

final class TutorialController: ObservableObject {
    @Published var step: TutorialStep = .inactive
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false

    var isActive: Bool { step != .inactive }

    var allowBuildAction: Bool {
        switch step {
        case .inactive, .homeBuild:
            return true
        default:
            return false
        }
    }

    var allowPresetsAction: Bool {
        switch step {
        case .inactive, .homePresets:
            return true
        default:
            return false
        }
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
             .buildHeaderIntro,
             .buildPower,
             .buildShield,
             .buildOutput,
             .buildAddBass,
             .buildAutoExplain,
             .buildAutoAddClarity,
             .buildAutoReorder,
             .buildManualExplain,
             .buildDoubleClick,
             .buildCloseOverlay,
             .buildRightClick,
             .buildCloseContextMenu,
             .buildWiringManual,
             .buildConnect,
             .buildAutoConnectEnd,
             .buildParallelExplain,
             .buildParallelAddReverb,
             .buildParallelConnect,
             .buildGraphMode,
             .buildDualMonoAdd,
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
        guard !hasSeenTutorial, !isSetupVisible else { return }
        step = .welcome
        hasSeenTutorial = true
    }

    func startFromHelp() {
        step = .welcome
    }

    func advance() {
        switch step {
        case .welcome:
            step = .homePresets
        case .homePresets:
            step = .presetsExplore
        case .presetsExplore:
            step = .presetsBack
        case .presetsBack:
            step = .homeBuild
        case .homeBuild:
            step = .buildIntro
        case .buildIntro:
            step = .buildHeaderIntro
        case .buildHeaderIntro:
            step = .buildPower
        case .buildPower:
            step = .buildShield
        case .buildShield:
            step = .buildOutput
        case .buildOutput:
            step = .buildAddBass
        case .buildAddBass:
            step = .buildAutoExplain
        case .buildAutoExplain:
            step = .buildAutoAddClarity
        case .buildAutoAddClarity:
            step = .buildAutoReorder
        case .buildAutoReorder:
            step = .buildManualExplain
        case .buildManualExplain:
            step = .buildWiringManual
        case .buildDoubleClick:
            step = .buildCloseOverlay
        case .buildCloseOverlay:
            step = .buildRightClick
        case .buildRightClick:
            step = .buildCloseContextMenu
        case .buildCloseContextMenu:
            step = .buildResetWiringForParallel
        case .buildWiringManual:
            step = .buildConnect
        case .buildConnect:
            step = .buildAutoConnectEnd
        case .buildAutoConnectEnd:
            step = .buildDoubleClick
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
            step = .buildSave
        case .buildSave:
            step = .buildSaveConfirm
        case .buildSaveConfirm:
            step = .buildLoad
        case .buildLoad:
            step = .buildCloseLoad
        case .buildCloseLoad:
            step = .buildFinish
        case .buildFinish:
            step = .inactive
        case .inactive:
            break
        }
    }

    func handlePresetsClick() {
        if step == .homePresets {
            step = .presetsExplore
        }
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
        step = .inactive
    }
}

