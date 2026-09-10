import SwiftUI

final class TutorialController: ObservableObject {
    enum NextLesson: Equatable {
        case appChains
        case manualWiring
    }

    @Published var step: TutorialStep = .inactive {
        didSet {
            guard step != oldValue else { return }
            hasAdjustedWireGain = false
            reviewIndex = nil
            if step == .inactive {
                instructionHistory.removeAll()
            } else {
                if [.welcome, .chainsIntro, .advancedIntro].contains(step) {
                    instructionHistory.removeAll()
                }
                instructionHistory.append(step)
            }
        }
    }
    private var instructionHistory: [TutorialStep] = []
    @Published private(set) var reviewIndex: Int?
    var isReviewing: Bool { reviewIndex != nil }
    var displayedStep: TutorialStep {
        guard let reviewIndex else { return step }
        return instructionHistory[reviewIndex]
    }
    private var hasAdjustedWireGain = false
    @Published private(set) var pendingNextLesson: NextLesson?
    @Published var hasVisitedTrayTabs = false
    private(set) var isAppChainTour = false
    private(set) var practiceChainID: UUID?
    private(set) var practiceAppName = "the app"
    var onBeginAppTour: (() -> Bool)?
    var onEndAppTour: (() -> Bool)?

    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @AppStorage("lastPresentedTutorialVersion") private var lastPresentedTutorialVersion = ""
    private let appVersion: String
    @AppStorage("hasCompletedBasicsTutorial") private var hasCompletedBasicsTutorial = false
    @AppStorage("hasCompletedAdvancedTutorial") private var hasCompletedAdvancedTutorial = false
    @AppStorage("hasCompletedChainsTutorial") private var hasCompletedChainsTutorial = false
    private(set) var shouldRestoreOnEnd = false

    var isActive: Bool { step != .inactive }
    var basicsCompleted: Bool { hasCompletedBasicsTutorial }
    var chainsCompleted: Bool { hasCompletedChainsTutorial }
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
             .buildOutputGain, .buildCeiling, .buildSettingsSummary, .buildLibrary, .buildPresetLibrary,
             .buildBypass, .buildDisconnected, .buildFlow, .buildWireLevels, .buildSelection,
             .chainsIntro, .chainsAdd, .chainsOverrides,
             .chainsClose, .chainsMenuBar, .chainsBackground, .chainsComplete,
             .chainsChoosePreset, .chainsDisable,
             .chainsEnable, .chainsOpenEditor,
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

    init(defaults: UserDefaults = .standard,
         appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") {
        self.appVersion = appVersion
        _hasSeenTutorial = AppStorage(wrappedValue: false, "hasSeenTutorial", store: defaults)
        _lastPresentedTutorialVersion = AppStorage(wrappedValue: "", "lastPresentedTutorialVersion", store: defaults)
        _hasCompletedBasicsTutorial = AppStorage(wrappedValue: false, "hasCompletedBasicsTutorial", store: defaults)
        _hasCompletedAdvancedTutorial = AppStorage(wrappedValue: false, "hasCompletedAdvancedTutorial", store: defaults)
        _hasCompletedChainsTutorial = AppStorage(wrappedValue: false, "hasCompletedChainsTutorial", store: defaults)
    }

    func startChains() {
        guard !isActive, onBeginAppTour?() ?? true else { return }
        pendingNextLesson = nil
        isAppChainTour = true
        hasSeenTutorial = true
        lastPresentedTutorialVersion = appVersion
        practiceChainID = nil
        practiceAppName = "the app"
        shouldRestoreOnEnd = true
        step = .chainsIntro
    }

    func startIfNeeded(isSetupVisible: Bool) {
        guard lastPresentedTutorialVersion != appVersion, !isSetupVisible, !isActive else { return }
        startBasics()
    }

    func startBasics() {
        pendingNextLesson = nil
        hasSeenTutorial = true
        // Mark presentation, rather than completion, so Skip or quitting during
        // the lesson does not force it to replay on every launch of this release.
        lastPresentedTutorialVersion = appVersion
        isAppChainTour = false
        shouldRestoreOnEnd = true
        step = .welcome
        hasVisitedTrayTabs = false
    }

    func startAdvanced() {
        pendingNextLesson = nil
        hasSeenTutorial = true
        lastPresentedTutorialVersion = appVersion
        isAppChainTour = false
        shouldRestoreOnEnd = true
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
            step = .buildPower
        case .buildIntro:
            step = .buildTrayTabs
            hasVisitedTrayTabs = false
        case .buildTrayTabs:
            step = .buildLibrary
        case .buildLibrary:
            step = .buildPower
        case .buildPower:
            step = .buildAddBass
        case .buildAddBass:
            step = .buildAutoAddClarity
        case .buildAutoAddClarity:
            step = .buildAutoReorder
        case .buildAutoReorder:
            step = .buildDoubleClick
        case .buildAutoExplain:
            step = .buildDoubleClick
        case .buildDoubleClick:
            step = .buildEffectControls
        case .buildEffectControls:
            step = .buildCloseOverlay
        case .buildCloseOverlay:
            step = .buildSettings
        case .buildRightClick:
            step = .buildActionMenu
        case .buildActionMenu:
            step = .buildSelection
        case .buildSelection:
            step = .buildSettings
        case .buildCloseContextMenu:
            step = .buildSettings
        case .buildSettings:
            step = .buildSettingsExplain
        case .buildSettingsExplain:
            step = .buildOutputGain
        case .buildOutputGain:
            step = .buildCeiling
        case .buildCeiling:
            step = .buildSettingsSummary
        case .buildSettingsSummary:
            step = .buildSave
        case .buildBypass:
            step = .buildSave
        case .buildSave:
            step = .buildLoad
        case .buildSaveConfirm:
            step = .buildLoad
        case .buildLoad:
            step = .basicsComplete
        case .buildPresetLibrary:
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
            step = .buildResetWiringForParallel
        case .buildAutoConnectEnd:
            step = .buildResetWiringForParallel
        case .buildResetWiringForParallel:
            step = .buildParallelAddReverb
        case .buildDisconnected:
            step = .buildParallelExplain
        case .buildParallelExplain:
            step = .buildParallelAddReverb
        case .buildParallelAddReverb:
            step = .buildParallelConnect
        case .buildParallelConnect:
            step = .buildWireLevels
        case .buildWireLevels:
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
        case .buildFlow:
            step = .advancedComplete
        case .advancedComplete:
            finishTutorial(completedAdvanced: true)
        case .buildHeaderIntro:
            step = .buildPower
        case .buildOutput:
            step = .buildRecord
        case .buildRecord:
            step = .buildBypass
        case .chainsIntro:
            step = .chainsAdd
        case .chainsAdd:
            step = .chainsOverrides
        case .chainsOverrides:
            step = .chainsMenuBar
        case .chainsClose:
            step = .chainsComplete
        case .chainsMenuBar:
            step = .chainsChoosePreset
        case .chainsChoosePreset:
            step = .chainsDisable
        case .chainsDisable:
            step = .chainsEnable
        case .chainsEnable:
            step = .chainsOpenEditor
        case .chainsOpenEditor:
            step = .chainsClose
        case .chainsBackground:
            step = .chainsComplete
        case .chainsComplete:
            finishTutorial()
        case .buildCloseLoad:
            step = .buildFinish
        case .buildFinish:
            finishTutorial()
        case .inactive:
            break
        }
    }

    func didOpenMenuBar(hasPresets: Bool) {
        guard step == .chainsMenuBar else { return }
        // Starter presets are deletable. An empty library must not block the lesson.
        step = hasPresets ? .chainsChoosePreset : .chainsDisable
    }

    var menuInstruction: String? {
        guard isActive && isAppChainTour else { return nil }
        switch step {
        case .chainsMenuBar, .chainsChoosePreset:
            return "Choose a preset for \(practiceAppName)."
        case .chainsDisable:
            return "Click the sliders button beside \(practiceAppName) to turn its effects off."
        case .chainsEnable:
            return "Click the same sliders button to turn the effects back on."
        case .chainsOpenEditor:
            return "Click \(practiceAppName)’s name to open its canvas."
        default:
            return "Continue this step in the main window."
        }
    }

    func nextButtonTapped() {
        guard step.allowsNextButton else { return }
        advance()
    }

    func previousInstruction() {
        guard isActive else { return }
        let index = reviewIndex ?? (instructionHistory.count - 1)
        guard index > 0 else { return }
        reviewIndex = index - 1
    }

    func nextInstruction() {
        guard isActive else { return }
        if let index = reviewIndex {
            reviewIndex = index + 1 < instructionHistory.count - 1 ? index + 1 : nil
        } else if ![.basicsComplete, .chainsComplete, .advancedComplete].contains(step) {
            // Completion cards require an explicit Continue/Finish choice.
            // Arrow navigation is also available for reading without doing the exercise.
            advance()
        }
    }

    func didAddPracticeChain(id: UUID, name: String) {
        guard step == .chainsAdd else { return }
        practiceChainID = id
        practiceAppName = name
        advance()
    }

    func didOpenEditor(chainID: UUID) {
        if step == .chainsOpenEditor && chainID == practiceChainID { advance() }
    }

    func handlePresetsClick() {
        if step == .homePresets { step = .presetsExplore }
    }

    func handleBuildClick() {
        if step == .homeBuild {
            step = .buildPower
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

    func didAdjustWireGain() {
        guard step == .buildWireLevels else { return }
        hasAdjustedWireGain = true
    }

    func didFinishWireGain() {
        guard step == .buildWireLevels, hasAdjustedWireGain else { return }
        advance()
    }

    func endTutorial() { skipTutorial() }

    func skipTutorial() {
        guard !isAppChainTour || (onEndAppTour?() ?? true) else { return }
        pendingNextLesson = nil
        shouldRestoreOnEnd = true
        step = .inactive
    }

    func continueToNextLesson() {
        let next: NextLesson
        switch step {
        case .basicsComplete: next = .appChains
        case .chainsComplete: next = .manualWiring
        default: return
        }
        guard finishTutorial() else { return }
        pendingNextLesson = next
    }

    // ContentView calls this only after the previous lesson's workspace and
    // canvas have finished restoring. Do not race their asynchronous graph load.
    func startPendingLesson() {
        guard !isActive, let next = pendingNextLesson else { return }
        switch next {
        case .appChains: startChains()
        case .manualWiring: startAdvanced()
        }
    }

    @discardableResult
    func finishTutorial(completedAdvanced: Bool = false) -> Bool {
        guard !isAppChainTour || (onEndAppTour?() ?? true) else { return false }
        pendingNextLesson = nil
        if step == .basicsComplete {
            hasCompletedBasicsTutorial = true
        }
        if completedAdvanced || step == .advancedComplete {
            hasCompletedAdvancedTutorial = true
        }
        if step == .chainsComplete { hasCompletedChainsTutorial = true }
        shouldRestoreOnEnd = true
        step = .inactive
        return true
    }
}
