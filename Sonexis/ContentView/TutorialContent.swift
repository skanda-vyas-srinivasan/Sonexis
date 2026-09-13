import SwiftUI

extension TutorialOverlay {
    func tutorialContent() -> (title: String, body: String, showNext: Bool, isBasicsComplete: Bool)? {
        switch step {
        case .welcome:
            return (
                title: "Welcome to Sonexis",
                body: "Follow along to learn how to use the app.",
                showNext: true,
                isBasicsComplete: false
            )
        case .homePresets:
            return (
                title: "Presets",
                body: "Open your saved presets.",
                showNext: false,
                isBasicsComplete: false
            )
        case .presetsExplore:
            return (
                title: "Load a preset",
                body: "Choose a preset to load its effects and wiring.",
                showNext: true,
                isBasicsComplete: false
            )
        case .presetsBack:
            return (
                title: "Build a chain",
                body: "Return to Home to start building.",
                showNext: false,
                isBasicsComplete: false
            )
        case .homeBuild:
            return (
                title: "Start",
                body: "Click anywhere to start.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildIntro:
            return (
                title: "Add effects",
                body: "Drag effects onto the canvas to build a chain.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildTrayTabs:
            return (
                title: "Find an effect",
                body: "Star effects you use often to keep them in Favorites. Installed Audio Units appear under Plugins.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildHeaderIntro:
            return (
                title: "Try it with audio",
                body: "Play some audio so you can hear your changes.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildPower:
            if !isSetupReady {
                return (
                    title: "Power",
                    body: "Finish audio setup to continue.",
                    showNext: false,
                    isBasicsComplete: false
                )
            } else {
                return (
                    title: "Turn on Sonexis",
                    body: "Press the power button to start Sonexis. Play some audio in the background so you can hear the effects as you try them.",
                    showNext: false,
                    isBasicsComplete: false
                )
            }
        case .buildRecord:
            return (
                title: "Record a chain",
                body: "Record saves the selected chain as a WAV file.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildOutput:
            return (
                title: "Output",
                body: "Reduce gain if the signal clips.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildSettings:
            return (
                title: "Open settings",
                body: "Click the gear to view your audio settings. No changes needed.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildSettingsExplain:
            return (
                title: "Input Gain",
                body: "Controls how loud the audio is before it enters your effects. Lowering it gives effects room to boost the sound.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildAddBass:
            return (
                title: "Add an effect",
                body: "Drag Bass Boost onto the canvas.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildAutoExplain:
            return (
                title: "Effect order",
                body: "In Automatic mode, effects run from left to right.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildAutoAddClarity:
            return (
                title: "Add another effect",
                body: "Drag Clarity to the left of Bass Boost.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildAutoReorder:
            return (
                title: "Change the order",
                body: "Now move Clarity to the right of Bass Boost. In Automatic mode, audio passes through the effects from left to right.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildManualExplain:
            return (
                title: "Manual wiring",
                body: "Use Manual mode to choose which effects connect.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildDoubleClick:
            return (
                title: "Adjust Bass Boost",
                body: "Double-click Bass Boost to open its controls.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildEffectControls:
            return (
                title: "Adjust the effect",
                body: "Drag the Amount knob up or down to change how much bass is added.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildCloseOverlay:
            return (
                title: "Close controls",
                body: "Double-click Bass Boost again to close its controls.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildRightClick:
            return (
                title: "More actions",
                body: "Right-click Bass Boost for more actions.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildActionMenu:
            return (
                title: "More actions",
                body: "Use Reset Params to restore the effect’s original settings.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildCloseContextMenu:
            return (
                title: "Close the menu",
                body: "Click empty canvas space to close the menu.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildWiringManual:
            return (
                title: "Edit the wires",
                body: "Switch Wiring to Manual. Your existing connections stay in place.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildConnect:
            return (
                title: "Add another path",
                body: "Hold Option and drag from Bass Boost to End. Some audio will now skip Clarity.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildAutoConnectEnd:
            return (
                title: "Auto-connect End",
                body: "This connects loose outputs to End for you.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildResetWiringForParallel:
            return (
                title: "Clear the wires",
                body: "Open the Canvas menu and choose Reset Wiring. The effects stay on the canvas.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildParallelExplain:
            return (
                title: "Parallel effects",
                body: "Parallel paths process the same sound separately, then mix together.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildParallelAddReverb:
            return (
                title: "Add Reverb",
                body: "Drag Reverb onto the canvas. We’ll send both effects into it.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildParallelConnect:
            return (
                title: "Connect the paths",
                body: "Hold Option and drag to connect:\nStart → Bass Boost\nStart → Clarity\nBass Boost → Reverb\nClarity → Reverb\nReverb → End",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildClearCanvasForDualMono:
            return (
                title: "Clear the canvas",
                body: "Open the Canvas menu and choose Clear Canvas. Next, we’ll put different effects on the left and right audio channels.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildGraphMode:
            return (
                title: "Separate left and right",
                body: "Open Graph Mode and choose Dual Mono. Each lane handles one audio channel.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildDualMonoAdd:
            return (
                title: "Add the effects",
                body: "Drag Bass Boost into the left lane and Clarity into the right lane.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildDualMonoConnect:
            return (
                title: "Connect each lane",
                body: "Hold Option and connect each lane:\nStart → effect → End",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildReturnStereoAuto:
            return (
                title: "Return to Automatic",
                body: "Set Graph Mode to Stereo, then Wiring to Automatic.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildSave:
            return (
                title: "Save a preset",
                body: "Click Save, enter a name, and save. A preset stores your effects and settings so you can use them again.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildSaveConfirm:
            return (
                title: "Saved",
                body: "Save updates this preset. Save As creates a separate copy.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildLoad:
            return (
                title: "Load a preset",
                body: "Click Load and select the preset you just saved to put it back on the canvas.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildCloseLoad:
            return (
                title: "Continue",
                body: "Close Load to continue.",
                showNext: false,
                isBasicsComplete: false
            )
        case .basicsComplete:
            return (
                title: "Basics complete",
                body: "Continue to learn about app chains, or finish here and start making your own.",
                showNext: false,
                isBasicsComplete: true
            )
        case .advancedIntro:
            return (
                title: "Advanced wiring",
                body: "In this tutorial, you’ll learn how to connect effects in more advanced and creative ways.",
                showNext: true,
                isBasicsComplete: false
            )
        case .advancedComplete:
            return (
                title: "Tutorial complete",
                body: "You’ve completed the tutorial. Press Finish to start making your own chains.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildFinish:
            return (
                title: "Done",
                body: "Your chain is ready.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildWireLevels:
            return (title: "Balance the paths",
                    body: "Right-click a wire, choose Wire Gain, adjust its level, then click Done.",
                    showNext: true, isBasicsComplete: false)
        case .buildSelection:
            return (title: "Select a group",
                    body: "Drag across empty canvas to select several blocks, then move them together.",
                    showNext: true, isBasicsComplete: false)
        case .buildLibrary:
            return (title: "Audio Unit plugins",
                    body: "Open Plugins to find installed Audio Units. Double-click a plugin on the canvas to open its editor.",
                    showNext: true, isBasicsComplete: false)
        case .buildOutputGain:
            return (title: "Output Gain",
                    body: "Controls how loud the audio is after your effects. It can bring the level back up if the effects leave it too quiet.",
                    showNext: true, isBasicsComplete: false)
        case .buildCeiling:
            return (title: "Ceiling",
                    body: "Limits peaks at the output.",
                    showNext: true, isBasicsComplete: false)
        case .buildSettingsSummary:
            return (title: "Your audio setup",
                    body: "Adjust these settings to suit your speakers, avoid clipping, and get the best listening experience.",
                    showNext: true, isBasicsComplete: false)
        case .buildPresetLibrary:
            return (title: "Manage presets",
                    body: "Right-click a preset in Load to rename, export, or delete it.",
                    showNext: true, isBasicsComplete: false)
        case .buildBypass:
            return (title: "Compare the sound",
                    body: "Use the sliders button to turn this chain’s effects off and back on.",
                    showNext: true, isBasicsComplete: false)
        case .buildDisconnected:
            return (title: "Disconnected effects",
                    body: "An amber outline means the effect is not connected to End.",
                    showNext: true, isBasicsComplete: false)
        case .buildFlow:
            return nil
        case .chainsIntro:
            return (title: "App audio chains",
                    body: "In this tutorial, you’ll learn how to create audio chains for specific apps.",
                    showNext: true, isBasicsComplete: false)
        case .chainsAdd:
            return (title: "The Default chain",
                    body: "Audio from all apps uses Default unless an app has its own chain. Click + and choose an app to give it a separate chain.",
                    showNext: true, isBasicsComplete: false)
        case .chainsOverrides:
            return (title: "Add an effect",
                    body: "Drag Bass Boost onto this app’s canvas. This app will use its own effects instead of the Default tab’s effects.",
                    showNext: true, isBasicsComplete: false)
        case .chainsClose:
            return (title: "Close an app chain",
                    body: "Close the \(practiceAppName) tab with ×, then confirm. The app will use Default again.",
                    showNext: true, isBasicsComplete: false)
        case .chainsMenuBar:
            return (title: "Open the menu bar",
                    body: "Click the S in your Mac’s menu bar.",
                    showNext: true, isBasicsComplete: false)
        case .chainsBackground:
            return (title: "Keep listening",
                    body: "Closing the window keeps your audio running. Quit stops Sonexis.",
                    showNext: true, isBasicsComplete: false)
        case .chainsComplete:
            return (title: "App chains complete",
                    body: "Continue to learn about manual wiring, or finish here and start making your own chains.",
                    showNext: true, isBasicsComplete: false)
        case .chainsChoosePreset:
            return (title: "Load from the menu bar", body: "Choose a preset under \(practiceAppName) in the menu-bar panel.", showNext: false, isBasicsComplete: false)
        case .chainsDisable:
            return (title: "Turn the effects off", body: "In the menu-bar panel, click the sliders button beside \(practiceAppName).", showNext: false, isBasicsComplete: false)
        case .chainsEnable:
            return (title: "Turn the effects back on", body: "Click the same sliders button again.", showNext: false, isBasicsComplete: false)
        case .chainsOpenEditor:
            return (title: "Return to the canvas", body: "Click \(practiceAppName)’s name in the menu-bar panel to open its canvas.", showNext: false, isBasicsComplete: false)
        case .inactive:
            return nil
        }
    }
}
