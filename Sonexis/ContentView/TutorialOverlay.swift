import SwiftUI
import AppKit

struct TutorialOverlay: View {
    let step: TutorialStep
    let isReviewing: Bool
    let targets: [TutorialTarget: CGRect]
    let isSetupReady: Bool
    let trayTabsVisited: Bool
    let practiceAppName: String
    let onNext: () -> Void
    let onSkip: () -> Void
    let onOpenSetup: () -> Void
    let onEndTutorial: () -> Void
    let onContinueTutorial: () -> Void
    let onPreviousInstruction: () -> Void
    let onNextInstruction: () -> Void

    @State private var measuredCardSize: CGSize = .zero
    @State private var showSkipConfirmation = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let highlightRects = highlightFrames(in: size, proxy: proxy)
            let primaryHighlight: CGRect? = {
                switch step {
                case .buildReturnStereoAuto:
                    guard let first = highlightRects.first else { return nil }
                    return highlightRects.dropFirst().reduce(first) { partial, rect in
                        partial.union(rect)
                    }
                default:
                    return highlightRects.first
                }
            }()

            // Power stays available throughout App Chains without stealing the
            // current exercise's highlight or adding a colored border to Power.
            let powerRects = step.isAppChainStep && !isReviewing
                ? [convertToLocal(rect: targets[.buildPower], proxy: proxy)].compactMap { $0 }
                : []
            ZStack {
                dimmingLayer(size: size, highlights: highlightRects + powerRects)
                    .allowsHitTesting(false)

                if isReviewing {
                    // Past instructions are read-only; reviewing must not repeat
                    // an add/delete action or reset the current practice graph.
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture {}
                }

                ForEach(Array(highlightRects.enumerated()), id: \.offset) { _, rect in
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.neonCyan.opacity(0.64), lineWidth: 1.25)
                        .shadow(color: AppColors.neonCyan.opacity(0.18), radius: 5)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                if let hintPosition = reverbScrollHintPosition(in: size, proxy: proxy) {
                    ReverbScrollHint()
                        .position(hintPosition)
                        .allowsHitTesting(false)
                }

                if !showSkipConfirmation {
                    // Explain one control at a time, but keep the card below the
                    // whole strip so it never covers the neighboring settings.
                    let calloutAnchor = step.isAudioSettingsExplanation
                        ? convertToLocal(rect: targets[.settingsStrip], proxy: proxy) ?? primaryHighlight
                        : primaryHighlight
                    calloutView(in: size, highlight: calloutAnchor)
                }
            }
        }
        .ignoresSafeArea()
        .background(TutorialArrowKeyHandler(
            isEnabled: !showSkipConfirmation,
            onPrevious: onPreviousInstruction,
            onNext: onNextInstruction
        ))
        .overlay(
            Group {
                if showSkipConfirmation {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture {
                                showSkipConfirmation = false
                            }
                        
                        SkipTutorialConfirm(
                            onCancel: { showSkipConfirmation = false },
                            onConfirm: onSkip
                        )
                    }
                }
            }
        )
    }

    private struct TutorialCardSizePreferenceKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            let next = nextValue()
            if next != .zero {
                value = next
            }
        }
    }

    private func highlightFrames(in size: CGSize, proxy: GeometryProxy) -> [CGRect] {
        switch step {
        case .chainsIntro:
            return [convertToLocal(rect: targets[.chainTabs], proxy: proxy)].compactMap { $0 }
        case .chainsClose:
            return [convertToLocal(rect: targets[.practiceChainTab], proxy: proxy)]
                .compactMap { $0.map { paddedHighlight($0, padding: 3) } }
        case .chainsOverrides:
            return [convertToLocal(rect: targets[.buildBassBoost], proxy: proxy),
                    convertToLocal(rect: targets[.buildCanvas], proxy: proxy)].compactMap { $0 }
        case .chainsAdd:
            return [convertToLocal(rect: targets[.addAppChain], proxy: proxy)].compactMap { $0 }
        case .buildBypass:
            return [convertToLocal(rect: targets[.chainBypass], proxy: proxy)].compactMap { $0 }
        case .buildLibrary:
            return [convertToLocal(rect: targets[.buildTrayTabs], proxy: proxy)].compactMap { $0 }
        case .buildOutputGain:
            return [convertToLocal(rect: targets[.outputGain], proxy: proxy)].compactMap { $0 }
        case .buildCeiling:
            return [convertToLocal(rect: targets[.ceiling], proxy: proxy)].compactMap { $0 }
        case .buildSettingsSummary:
            return [convertToLocal(rect: targets[.settingsStrip], proxy: proxy)].compactMap { $0 }
        case .buildPresetLibrary:
            return [convertToLocal(rect: targets[.buildLoad], proxy: proxy)].compactMap { $0 }
        case .buildFlow:
            return [convertToLocal(rect: targets[.flow], proxy: proxy)].compactMap { $0 }
        case .homePresets:
            return [convertToLocal(rect: targets[.presetsButton], proxy: proxy)].compactMap { $0 }
        case .presetsExplore:
            return []
        case .homeBuild:
            return []
        case .buildIntro:
            return [convertToLocal(rect: targets[.buildCanvas], proxy: proxy)].compactMap { $0 }
        case .presetsBack:
            return [convertToLocal(rect: targets[.backButton], proxy: proxy)]
                .compactMap { rect in
                    rect.map { paddedHighlight($0, padding: 8) }
                }
        case .buildAutoAddClarity:
            return [
                convertToLocal(rect: targets[.buildClarity], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        case .buildTrayTabs:
            return [convertToLocal(rect: targets[.buildTrayTabs], proxy: proxy)]
                .compactMap { rect in
                    rect.map { paddedHighlight($0, insets: EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 6)) }
                }
        case .buildHeaderIntro:
            return [
                convertToLocal(rect: targets[.buildPower], proxy: proxy),
                convertToLocal(rect: targets[.buildRecord], proxy: proxy),
                convertToLocal(rect: targets[.buildOutput], proxy: proxy)
            ].compactMap { $0 }
        case .buildAutoReorder:
            return [
                convertToLocal(rect: targets[.buildBassNode], proxy: proxy),
                convertToLocal(rect: targets[.buildClarityNode], proxy: proxy)
            ].compactMap { $0 }
        case .buildWiringManual:
            return [convertToLocal(rect: targets[.buildWiringMode], proxy: proxy)].compactMap { $0 }
        case .buildAutoExplain:
            return [convertToLocal(rect: targets[.buildWiringMode], proxy: proxy)].compactMap { $0 }
        case .buildManualExplain:
            return [convertToLocal(rect: targets[.buildWiringMode], proxy: proxy)].compactMap { $0 }
        case .buildAutoConnectEnd:
            return [convertToLocal(rect: targets[.buildAutoConnectEnd], proxy: proxy)].compactMap { $0 }
        case .buildResetWiringForParallel:
            return [convertToLocal(rect: targets[.buildCanvasMenu], proxy: proxy)].compactMap { $0 }
        case .buildClearCanvasForDualMono:
            return [convertToLocal(rect: targets[.buildCanvasMenu], proxy: proxy)].compactMap { $0 }
        case .buildGraphMode:
            return [convertToLocal(rect: targets[.buildGraphMode], proxy: proxy)].compactMap { $0 }
        case .buildReturnStereoAuto:
            return [
                convertToLocal(rect: targets[.buildGraphMode], proxy: proxy),
                convertToLocal(rect: targets[.buildWiringMode], proxy: proxy)
            ].compactMap { $0 }
        case .buildPower:
            return [convertToLocal(rect: targets[.buildPower], proxy: proxy)].compactMap { $0 }
        case .buildRecord:
            return [convertToLocal(rect: targets[.buildRecord], proxy: proxy)]
                .compactMap { rect in
                    rect.map { paddedHighlight($0, padding: 10) }
                }
        case .buildOutput:
            return [convertToLocal(rect: targets[.buildOutput], proxy: proxy)].compactMap { $0 }
        case .buildSettings:
            return [convertToLocal(rect: targets[.buildSettings], proxy: proxy)].compactMap { $0 }
        case .buildSettingsExplain:
            return [convertToLocal(rect: targets[.inputGain], proxy: proxy)].compactMap { $0 }
        case .buildAddBass:
            return [
                convertToLocal(rect: targets[.buildBassBoost], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        case .buildDoubleClick:
            return [convertToLocal(rect: targets[.buildBassNode], proxy: proxy)].compactMap { $0 }
        case .buildEffectControls:
            return [convertToLocal(rect: targets[.buildEffectControls], proxy: proxy)]
                .compactMap { $0.map { paddedHighlight($0, padding: 6) } }
        case .buildCloseOverlay:
            return [convertToLocal(rect: targets[.buildBassNode], proxy: proxy)].compactMap { $0 }
        case .buildSave:
            return [convertToLocal(rect: targets[.buildSave], proxy: proxy)].compactMap { $0 }
        case .buildSaveConfirm:
            return []
        case .buildLoad:
            return [convertToLocal(rect: targets[.buildLoad], proxy: proxy)].compactMap { $0 }
        case .buildCloseLoad:
            return []
        case .buildRightClick:
            return [convertToLocal(rect: targets[.buildBassNode], proxy: proxy)].compactMap { $0 }
        case .buildCloseContextMenu:
            return [convertToLocal(rect: targets[.buildBassNode], proxy: proxy)].compactMap { $0 }
        case .buildParallelAddReverb:
            return [
                convertToLocal(rect: targets[.buildReverb], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        case .buildParallelConnect:
            return [
                convertToLocal(rect: targets[.buildBassNode], proxy: proxy),
                convertToLocal(rect: targets[.buildClarityNode], proxy: proxy),
                convertToLocal(rect: targets[.buildReverbNode], proxy: proxy)
            ].compactMap { $0 }
        case .buildParallelExplain, .buildWireLevels:
            return [convertToLocal(rect: targets[.buildCanvas], proxy: proxy)].compactMap { $0 }
        case .buildDualMonoAdd:
            return [
                convertToLocal(rect: targets[.buildGraphMode], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        case .buildDualMonoConnect:
            return [
                convertToLocal(rect: targets[.buildBassNode], proxy: proxy),
                convertToLocal(rect: targets[.buildClarityNode], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        default:
            return []
        }
    }

    private func reverbScrollHintPosition(in size: CGSize, proxy: GeometryProxy) -> CGPoint? {
        guard step == .buildParallelAddReverb,
              targets[.buildReverb] == nil else {
            return nil
        }

        if let canvas = convertToLocal(rect: targets[.buildCanvas], proxy: proxy) {
            return CGPoint(
                x: max(76, canvas.minX * 0.5),
                y: min(size.height - 110, max(canvas.minY + 190, 270))
            )
        }

        return CGPoint(
            x: min(max(size.width * 0.18, 76), 150),
            y: min(size.height - 110, max(size.height * 0.45, 270))
        )
    }

    private func convertToLocal(rect: CGRect?, proxy: GeometryProxy) -> CGRect? {
        guard let rect else { return nil }
        let global = proxy.frame(in: .global)
        return rect.offsetBy(dx: -global.minX, dy: -global.minY)
    }

    private func paddedHighlight(_ rect: CGRect, padding: CGFloat) -> CGRect {
        rect.insetBy(dx: -padding, dy: -padding)
    }

    private func paddedHighlight(_ rect: CGRect, insets: EdgeInsets) -> CGRect {
        CGRect(
            x: rect.minX - insets.leading,
            y: rect.minY - insets.top,
            width: rect.width + insets.leading + insets.trailing,
            height: rect.height + insets.top + insets.bottom
        )
    }

    @ViewBuilder
    private func dimmingLayer(size: CGSize, highlights: [CGRect]) -> some View {
        if shouldDimBackground {
            if !highlights.isEmpty {
                ZStack {
                    Color.black.opacity(0.32)
                    ForEach(Array(highlights.enumerated()), id: \.offset) { _, rect in
                        RoundedRectangle(cornerRadius: 10)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            } else {
                Color.black.opacity(0.32)
            }
        } else {
            Color.clear
        }
    }

    private var shouldDimBackground: Bool {
        switch step {
        case .presetsExplore:
            return false
        case .buildAddBass:
            return false
        case .buildAutoAddClarity:
            return false
        case .buildConnect:
            // User needs to see the whole canvas to wire.
            return false
        case .buildAutoReorder:
            return false
        case .buildSaveConfirm:
            return false
        case .buildCloseLoad:
            return false
        case .buildActionMenu:
            return false
        case .buildCloseContextMenu:
            return false
        case .buildParallelConnect:
            return false
        case .buildParallelAddReverb:
            return false
        case .buildDualMonoAdd:
            return false
        case .buildDualMonoConnect:
            return false
        case .buildResetWiringForParallel:
            return false
        case .buildClearCanvasForDualMono:
            return false
        case .buildReturnStereoAuto:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private func calloutView(in size: CGSize, highlight: CGRect?) -> some View {
        if let content = tutorialContent() {
            let cardMaxWidth: CGFloat = {
                if step.showsAudioSettings {
                    return 340
                }
                return highlight == nil ? 380 : 340
            }()
            let cardBase = tutorialCard(
                title: content.title,
                body: content.body,
                showNext: content.showNext,
                isBasicsComplete: content.isBasicsComplete
            )

            let card = cardBase
                .frame(maxWidth: cardMaxWidth)
                .overlay(alignment: .top) {
                    if step == .chainsMenuBar {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(AppColors.neonCyan)
                            .offset(y: -44)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(
                    GeometryReader { cardProxy in
                        Color.clear.preference(
                            key: TutorialCardSizePreferenceKey.self,
                            value: cardProxy.size
                        )
                    }
                )
                .onPreferenceChange(TutorialCardSizePreferenceKey.self) { newSize in
                    DispatchQueue.main.async {
                        guard measuredCardSize != newSize else { return }
                        measuredCardSize = newSize
                    }
                }

            if let rect = highlight {
                let position = bestCalloutPosition(
                    screen: size,
                    target: rect,
                    cardSize: measuredCardSize == .zero ? CGSize(width: 340, height: 126) : measuredCardSize
                )
                card.position(position)
            } else {
                let fallbackSize = measuredCardSize == .zero ? CGSize(width: cardMaxWidth, height: 126) : measuredCardSize
                let position = clamp(
                    fallbackCalloutCenter(in: size),
                    screen: size,
                    cardSize: fallbackSize
                )
                card.position(position)
            }
        } else {
            EmptyView()
        }
    }

    private func fallbackCalloutCenter(in size: CGSize) -> CGPoint {
        if step.showsAudioSettings {
            return CGPoint(x: size.width / 2, y: max(290, size.height * 0.36))
        }
        return CGPoint(x: size.width / 2, y: size.height * 0.22)
    }

    private func bestCalloutPosition(screen: CGSize, target: CGRect, cardSize: CGSize) -> CGPoint {
        let padding: CGFloat = 16
        let avoidPad: CGFloat = 10

        if step.isAudioSettingsExplanation {
            return clamp(
                CGPoint(x: target.minX + cardSize.width / 2 + padding,
                        y: target.maxY + padding + cardSize.height / 2),
                screen: screen,
                cardSize: cardSize
            )
        }

        // Special case: For back button, force center-lower position to avoid blocking
        if step == .presetsBack {
            return clamp(
                CGPoint(x: screen.width / 2, y: screen.height * 0.65),
                screen: screen,
                cardSize: cardSize
            )
        }

        let candidates: [CGPoint]
        if step == .buildReturnStereoAuto {
            candidates = [
                CGPoint(x: target.midX, y: target.minY - padding - cardSize.height / 2), // above
                CGPoint(x: target.maxX + padding + cardSize.width / 2, y: target.midY), // right
                CGPoint(x: target.minX - padding - cardSize.width / 2, y: target.midY), // left
                CGPoint(x: target.midX, y: target.maxY + padding + cardSize.height / 2) // below
            ]
        } else {
            candidates = [
                CGPoint(x: target.maxX + padding + cardSize.width / 2, y: target.midY), // right
                CGPoint(x: target.minX - padding - cardSize.width / 2, y: target.midY), // left
                CGPoint(x: target.midX, y: target.maxY + padding + cardSize.height / 2), // below
                CGPoint(x: target.midX, y: target.minY - padding - cardSize.height / 2)  // above
            ]
        }

        let inflatedTarget = target.insetBy(dx: -avoidPad, dy: -avoidPad)
        for candidate in candidates {
            let rect = cardRect(center: candidate, cardSize: cardSize)
            if isRectOnScreen(rect, screen: screen, padding: padding),
               !rect.intersects(inflatedTarget) {
                return candidate
            }
        }

        // Fallback: prefer below, but clamp so it always stays visible.
        return clamp(candidates.last ?? CGPoint(x: screen.width / 2, y: screen.height / 2), screen: screen, cardSize: cardSize)
    }

    private func clamp(_ center: CGPoint, screen: CGSize, cardSize: CGSize) -> CGPoint {
        let padding: CGFloat = 14
        let halfW = cardSize.width / 2
        let halfH = cardSize.height / 2
        let x = min(max(center.x, padding + halfW), screen.width - padding - halfW)
        let y = min(max(center.y, padding + halfH), screen.height - padding - halfH)
        return CGPoint(x: x, y: y)
    }

    private func cardRect(center: CGPoint, cardSize: CGSize) -> CGRect {
        CGRect(
            x: center.x - cardSize.width / 2,
            y: center.y - cardSize.height / 2,
            width: cardSize.width,
            height: cardSize.height
        )
    }

    private func isRectOnScreen(_ rect: CGRect, screen: CGSize, padding: CGFloat) -> Bool {
        rect.minX >= padding &&
        rect.minY >= padding &&
        rect.maxX <= screen.width - padding &&
        rect.maxY <= screen.height - padding
    }

    private func tutorialContent() -> (title: String, body: String, showNext: Bool, isBasicsComplete: Bool)? {
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
            return (title: "Wire animation",
                    body: "Flow Off stops the animation while audio keeps playing.",
                    showNext: true, isBasicsComplete: false)
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

    private func tutorialCard(title: String, body: String, showNext: Bool, isBasicsComplete: Bool) -> some View {
        let showSetupButtons = step == .buildPower && !isSetupReady
        let isChainsComplete = step == .chainsComplete
        let isLessonComplete = isBasicsComplete || isChainsComplete
        return TutorialCardView(
            title: title,
            message: body,
            showNext: step.allowsNextButton,
            onNext: onNext,
            onSkip: { showSkipConfirmation = true },
            showSetupButtons: showSetupButtons && !isReviewing,
            onOpenSetup: onOpenSetup,
            showSkip: !isReviewing && !isLessonComplete && step != .advancedComplete,
            secondaryActionTitle: !isReviewing && isLessonComplete ? "Finish here" : nil,
            onSecondaryAction: !isReviewing && isLessonComplete ? onEndTutorial : nil,
            primaryActionTitle: isReviewing ? "Next" : (isLessonComplete ? "Continue" : (step == .advancedComplete ? "Finish" : nil)),
            onPrimaryAction: isReviewing ? onNextInstruction : (isLessonComplete ? onContinueTutorial : (step == .advancedComplete ? onNext : nil))
        )
    }
}

private struct TutorialArrowKeyHandler: NSViewRepresentable {
    let isEnabled: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeNSView(context: Context) -> KeyMonitorView { KeyMonitorView() }

    func updateNSView(_ view: KeyMonitorView, context: Context) {
        view.isEnabled = isEnabled
        view.onPrevious = onPrevious
        view.onNext = onNext
    }

    static func dismantleNSView(_ view: KeyMonitorView, coordinator: ()) { view.stop() }

    final class KeyMonitorView: NSView {
        var isEnabled = false
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled, let window = self.window,
                      event.window === window, window.isKeyWindow, window.attachedSheet == nil,
                      !event.isARepeat, [123, 124].contains(event.keyCode),
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
                // Never take arrows from a focused slider, knob, text field,
                // native menu, or other control. The canvas capture is non-editing.
                let responder = window.firstResponder
                guard responder == nil || responder === window || responder === window.contentView ||
                      responder is KeyEventCapture.KeyCaptureView else { return event }
                if event.keyCode == 123 { self.onPrevious?() } else { self.onNext?() }
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stop() }
    }
}

private struct ReverbScrollHint: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .bold))
            Text("Scroll for Reverb")
                .font(AppTypography.caption.weight(.semibold))
        }
        .foregroundColor(AppColors.neonCyan)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.deepBlack.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.neonCyan.opacity(0.24), lineWidth: 1)
        )
    }
}

private struct SkipTutorialConfirm: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Exit Tutorial?")
                .font(AppTypography.heading)
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("You can always restart it from the Home screen.")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 10) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .tint(AppColors.textSecondary)

                Button("Exit") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.neonPink)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.midPurple.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.neonPink.opacity(0.6), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 6)
        .frame(maxWidth: 320)
    }
}
