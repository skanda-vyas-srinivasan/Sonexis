import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

let suite = "SonexisTutorialTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let tutorial = TutorialController(defaults: defaults)

func walk(to final: TutorialStep) -> [TutorialStep] {
    var visited: [TutorialStep] = []
    while tutorial.step != final {
        expect(tutorial.isActive, "Tour ended before reaching \(final)")
        expect(!visited.contains(tutorial.step), "Tour loop at \(tutorial.step)")
        visited.append(tutorial.step)
        expect(visited.count < 80, "Tour did not finish")
        tutorial.advance()
    }
    return visited + [final]
}

tutorial.startIfNeeded(isSetupVisible: true)
expect(!tutorial.isActive, "Setup must finish before onboarding starts")
tutorial.startIfNeeded(isSetupVisible: false)
expect(tutorial.step == .welcome, "First launch starts Basics")
tutorial.advanceIf(.buildSave)
expect(tutorial.step == .welcome, "Unrelated UI events cannot advance the tour")
let basics = walk(to: .basicsComplete)
expect(basics == [.welcome, .homeBuild, .buildPower, .buildAddBass,
                  .buildAutoAddClarity, .buildAutoReorder, .buildDoubleClick,
                  .buildEffectControls, .buildCloseOverlay, .buildSettings,
                  .buildSettingsExplain, .buildOutputGain, .buildCeiling, .buildSettingsSummary,
                  .buildSave, .buildLoad, .basicsComplete],
       "Basics follows the build/edit/save task with separate settings explanations")
expect(basics.filter(\.showsAudioSettings) == [.buildSettings, .buildSettingsExplain,
                                             .buildOutputGain, .buildCeiling, .buildSettingsSummary],
       "Settings stays open through the explanations and summary, then closes")
tutorial.finishTutorial()
tutorial.startChains()
expect(tutorial.basicsCompleted && tutorial.step == .chainsIntro, "Continue records Basics completion")
let chains = walk(to: .chainsComplete)
expect(chains == [.chainsIntro, .chainsAdd, .chainsOverrides,
                  .chainsMenuBar, .chainsChoosePreset, .chainsDisable,
                  .chainsEnable, .chainsOpenEditor, .chainsClose, .chainsComplete],
       "App tour includes a real action for each feature it teaches")
expect(chains.allSatisfy { step in tutorial.step = step; return tutorial.isBuildStep },
       "App tour uses workspace interaction restrictions")
tutorial.finishTutorial()
tutorial.startAdvanced()
expect(tutorial.chainsCompleted && tutorial.shouldRestoreOnEnd, "Continuing keeps the original canvas restore")
let advanced = walk(to: .advancedComplete)
for step: TutorialStep in [.buildConnect, .buildParallelConnect, .buildWireLevels,
                           .buildDualMonoConnect, .buildReturnStereoAuto] {
    expect(advanced.contains(step), "Manual wiring must cover \(step)")
}
expect(!advanced.contains(.buildFlow) && !advanced.contains(.buildParallelExplain)
       && !advanced.contains(.buildDisconnected), "Wiring teaches through exercises rather than extra explanation cards")
tutorial.advance()
expect(!tutorial.isActive && tutorial.advancedCompleted && tutorial.shouldRestoreOnEnd,
       "Finish restores the original canvas and records completion")
let reopened = TutorialController(defaults: defaults)
expect(reopened.basicsCompleted && reopened.chainsCompleted && reopened.advancedCompleted,
       "Each tour completion persists")
reopened.startIfNeeded(isSetupVisible: false)
expect(!reopened.isActive, "Completed onboarding does not automatically replay")

defaults.removePersistentDomain(forName: suite)
let standalone = TutorialController(defaults: defaults)
standalone.startChains()
standalone.step = .chainsComplete
standalone.finishTutorial()
expect(standalone.chainsCompleted && !standalone.basicsCompleted && !standalone.advancedCompleted,
       "Finishing one tour must not mark unvisited tours complete")
standalone.startAdvanced()
standalone.skipTutorial()
expect(!standalone.isActive && !standalone.advancedCompleted && standalone.shouldRestoreOnEnd,
       "Exit restores the canvas without marking an unfinished tour complete")
standalone.startBasics()
standalone.advance()
standalone.handleBuildClick()
expect(standalone.step == .buildPower, "Home click enters the exercise directly")
standalone.step = .basicsComplete
standalone.finishTutorial()
expect(standalone.basicsCompleted && standalone.shouldRestoreOnEnd, "Finish button also restores the original")
print("PASS: three tour paths, feature coverage, settings lifetime, event guards, completion, exit and persistence")

// The Next button cannot bypass an action step, including the formerly passive edits.
for step in basics + chains + advanced where !step.allowsNextButton {
    standalone.step = step
    standalone.nextButtonTapped()
    expect(standalone.step == step, "Next must not skip the required action: \(step)")
}
standalone.step = .buildSettingsExplain
for expected: TutorialStep in [.buildOutputGain, .buildCeiling, .buildSettingsSummary, .buildSave] {
    expect(standalone.step.isAudioSettingsExplanation && standalone.step.showsAudioSettings,
           "Each settings explanation keeps the panel visible")
    standalone.nextButtonTapped()
    expect(standalone.step == expected, "Next explains the next setting without requiring an edit")
}
expect(!standalone.step.showsAudioSettings, "The panel closes before the save exercise")
standalone.step = .buildSettings
standalone.nextButtonTapped()
expect(standalone.step == .buildSettings, "Opening the gear still requires the actual action")
standalone.step = .buildEffectControls
standalone.advanceIf(.buildWireLevels)
expect(standalone.step == .buildEffectControls, "Unrelated edits do not complete the knob exercise")
standalone.advanceIf(.buildEffectControls)
expect(standalone.step == .buildCloseOverlay, "An actual parameter edit completes the knob step")
standalone.step = .chainsAdd
let practiceID = UUID()
standalone.didAddPracticeChain(id: practiceID, name: "Practice App")
expect(standalone.step == .chainsOverrides && standalone.practiceChainID == practiceID,
       "Successful add records the practice app and advances")
standalone.advanceIf(.chainsOverrides)
expect(standalone.step == .chainsMenuBar, "Adding an effect moves straight to the menu bar")
standalone.didOpenMenuBar(hasPresets: true)
expect(standalone.step == .chainsChoosePreset, "Existing presets support the menu exercise without a save step")
standalone.step = .chainsMenuBar
standalone.didOpenMenuBar(hasPresets: false)
expect(standalone.step == .chainsDisable, "Deleting every preset does not block the app lesson")
standalone.didOpenMenuBar(hasPresets: true)
expect(standalone.step == .chainsDisable, "Reopening the menu cannot restart the preset exercise")
standalone.step = .chainsOpenEditor
standalone.didOpenEditor(chainID: UUID())
expect(standalone.step == .chainsOpenEditor, "Wrong menu-bar chain does not advance")
standalone.didOpenEditor(chainID: practiceID)
expect(standalone.step == .chainsClose, "Opening the practice chain advances")
print("PASS: action steps cannot be skipped; settings remains optional; app events require the correct target")

// A release gets one automatic presentation, even for users of the old one-time tutorial.
defaults.removePersistentDomain(forName: suite)
defaults.set(true, forKey: "hasSeenTutorial")
defaults.set(true, forKey: "hasCompletedBasicsTutorial")
let migrated = TutorialController(defaults: defaults, appVersion: "2.0.1")
migrated.startIfNeeded(isSetupVisible: true)
expect(!migrated.isActive && defaults.string(forKey: "lastPresentedTutorialVersion") == nil,
       "Setup defers onboarding without marking the release as shown")
migrated.startIfNeeded(isSetupVisible: false)
expect(migrated.step == .welcome && migrated.basicsCompleted,
       "Existing users see the release tutorial without losing their completion history")
migrated.advance()
migrated.startIfNeeded(isSetupVisible: false)
expect(migrated.step == .homeBuild, "Repeated launch hooks cannot restart an active lesson")
migrated.skipTutorial()
let sameRelease = TutorialController(defaults: defaults, appVersion: "2.0.1")
sameRelease.startIfNeeded(isSetupVisible: false)
expect(!sameRelease.isActive, "Skipping dismisses automatic onboarding for this release")
let nextRelease = TutorialController(defaults: defaults, appVersion: "2.0.2")
nextRelease.startIfNeeded(isSetupVisible: false)
expect(nextRelease.step == .welcome, "A new version starts onboarding again")
let quitDuringTour = TutorialController(defaults: defaults, appVersion: "2.0.2")
quitDuringTour.startIfNeeded(isSetupVisible: false)
expect(!quitDuringTour.isActive, "Quitting mid-lesson does not force another presentation of the same release")
let manualTour = TutorialController(defaults: defaults, appVersion: "2.1.0")
manualTour.startAdvanced()
manualTour.skipTutorial()
manualTour.startIfNeeded(isSetupVisible: false)
expect(!manualTour.isActive, "A manually opened lesson also counts as seeing this release's tutorial")
print("PASS: per-version onboarding, existing-user migration, setup deferral, skip, relaunch and active-tour guards")

defaults.removePersistentDomain(forName: suite)
let linked = TutorialController(defaults: defaults)
linked.startBasics()
linked.continueToNextLesson()
expect(linked.step == .welcome && linked.pendingNextLesson == nil,
       "Continue cannot bypass an unfinished lesson")
linked.step = .basicsComplete
linked.continueToNextLesson()
expect(!linked.isActive && linked.basicsCompleted && linked.pendingNextLesson == .appChains,
       "Continue completes Basics and waits for workspace restoration")
var allowAppStart = false
linked.onBeginAppTour = { allowAppStart }
linked.startPendingLesson()
expect(!linked.isActive && linked.pendingNextLesson == .appChains,
       "A failed app lesson start retains the requested continuation")
allowAppStart = true
linked.startPendingLesson()
expect(linked.step == .chainsIntro && linked.pendingNextLesson == nil,
       "The app lesson starts after the workspace is ready")
linked.step = .chainsComplete
linked.onEndAppTour = { false }
linked.continueToNextLesson()
expect(linked.step == .chainsComplete && linked.pendingNextLesson == nil && !linked.chainsCompleted,
       "Failed workspace restoration keeps the completion card for retry")
linked.onEndAppTour = { true }
linked.continueToNextLesson()
expect(!linked.isActive && linked.chainsCompleted && linked.pendingNextLesson == .manualWiring,
       "App completion queues Manual wiring after successful restoration")
linked.startPendingLesson()
expect(linked.step == .advancedIntro && !linked.isAppChainTour && linked.pendingNextLesson == nil,
       "The next lesson uses the Manual wiring lifecycle")
linked.step = .advancedComplete
linked.continueToNextLesson()
expect(linked.step == .advancedComplete && linked.pendingNextLesson == nil,
       "The final lesson has no further continuation")
linked.finishTutorial()
expect(!linked.isActive && linked.advancedCompleted, "Finish completes the final lesson")
linked.startBasics()
linked.step = .basicsComplete
linked.finishTutorial()
linked.startPendingLesson()
expect(!linked.isActive && linked.pendingNextLesson == nil, "Finish here does not start another lesson")
linked.startChains()
linked.step = .chainsComplete
linked.finishTutorial()
expect(!linked.isActive && linked.pendingNextLesson == nil, "App chains can also finish independently")
print("PASS: optional lesson continuation, restoration gates, retry, final completion and Finish here")

linked.startAdvanced()
linked.didAdjustWireGain()
linked.step = .buildWireLevels
linked.didFinishWireGain()
expect(linked.step == .buildWireLevels, "Done without a wire-gain edit does not finish the exercise")
linked.didAdjustWireGain()
linked.didAdjustWireGain()
expect(linked.step == .buildWireLevels, "Slider changes keep the exercise and gain panel open")
linked.nextButtonTapped()
expect(linked.step == .buildWireLevels, "Next cannot bypass finishing the gain adjustment")
linked.didFinishWireGain()
expect(linked.step == .buildClearCanvasForDualMono, "Done advances after a gain adjustment")
linked.step = .buildWireLevels
linked.didFinishWireGain()
expect(linked.step == .buildWireLevels, "Reentering the exercise requires a fresh adjustment")
print("PASS: wire gain stays open during edits and completes only on Done after a change")

linked.startBasics()
linked.previousInstruction()
expect(linked.displayedStep == .welcome && !linked.isReviewing, "Left stops at the lesson's first instruction")
linked.nextInstruction()
expect(linked.step == .homeBuild, "Right advances an explanation just like Next")
linked.nextInstruction()
expect(linked.step == .buildPower, "Right advances through action steps without requiring interaction")
linked.advanceIf(.buildPower)
linked.previousInstruction()
expect(linked.step == .buildAddBass && linked.displayedStep == .buildPower && linked.isReviewing,
       "Left reviews instructions without rewinding the live exercise")
linked.previousInstruction()
expect(linked.displayedStep == .homeBuild, "Repeated Left walks through visited instructions")
linked.nextInstruction()
expect(linked.displayedStep == .buildPower && linked.step == .buildAddBass,
       "Right moves through history without repeating actions")
linked.nextInstruction()
expect(!linked.isReviewing && linked.displayedStep == .buildAddBass,
       "Right returns to the current exercise after review")
linked.previousInstruction()
linked.advanceIf(.buildAddBass)
expect(!linked.isReviewing && linked.displayedStep == .buildAutoAddClarity,
       "A completed live action returns the tutorial to its current instruction")
linked.step = .basicsComplete
linked.nextInstruction()
expect(linked.step == .basicsComplete && linked.pendingNextLesson == nil,
       "Right cannot choose Continue or Finish on the user's behalf")
linked.startAdvanced()
linked.previousInstruction()
expect(!linked.isReviewing, "History does not cross lesson boundaries")
linked.nextInstruction()
linked.step = .buildWireLevels
linked.didAdjustWireGain()
linked.previousInstruction()
linked.nextInstruction()
linked.didFinishWireGain()
expect(linked.step == .buildClearCanvasForDualMono, "Reviewing preserves an in-progress gain exercise")
linked.step = .advancedComplete
linked.nextInstruction()
expect(linked.step == .advancedComplete, "Right does not dismiss the final completion card")
linked.skipTutorial()
linked.previousInstruction()
expect(!linked.isReviewing && linked.displayedStep == .inactive, "History clears when the tutorial closes")
print("PASS: Left/Right instruction navigation, action-step skipping, non-destructive review and lesson boundaries")

for (start, completion): (() -> Void, TutorialStep) in [
    ({ linked.startBasics() }, .basicsComplete),
    ({ linked.startChains() }, .chainsComplete),
    ({ linked.startAdvanced() }, .advancedComplete)
] {
    start()
    var readSteps: [TutorialStep] = []
    while linked.step != completion {
        expect(linked.isActive && !readSteps.contains(linked.step),
               "Keyboard-only reading must not get stuck at \(linked.step)")
        readSteps.append(linked.step)
        linked.nextInstruction()
    }
    expect(readSteps.count > 5, "Keyboard-only reading follows the full lesson")
    linked.nextInstruction()
    expect(linked.step == completion, "The last card still offers an explicit finish choice")
    linked.finishTutorial()
}
print("PASS: all three lessons can be read with Right arrow without editing, adding apps, or saving presets")
