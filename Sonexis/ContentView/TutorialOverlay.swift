import SwiftUI

struct TutorialOverlay: View {
    let step: TutorialStep
    let targets: [TutorialTarget: CGRect]
    let isSetupReady: Bool
    let trayTabsVisited: Bool
    let onNext: () -> Void
    let onSkip: () -> Void
    let onOpenSetup: () -> Void
    let onEndTutorial: () -> Void
    let onContinueAdvanced: () -> Void

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

            ZStack {
                dimmingLayer(size: size, highlights: highlightRects)
                    .allowsHitTesting(false)

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
                    calloutView(in: size, highlight: primaryHighlight)
                }
            }
        }
        .ignoresSafeArea()
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
            return []
        case .buildAddBass:
            return [
                convertToLocal(rect: targets[.buildBassBoost], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        case .buildDoubleClick:
            return [convertToLocal(rect: targets[.buildBassNode], proxy: proxy)].compactMap { $0 }
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
        case .buildParallelExplain:
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
                if step == .buildSettingsExplain {
                    return 460
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
        if step == .buildSettingsExplain {
            return CGPoint(x: size.width / 2, y: max(290, size.height * 0.36))
        }
        return CGPoint(x: size.width / 2, y: size.height * 0.22)
    }

    private func bestCalloutPosition(screen: CGSize, target: CGRect, cardSize: CGSize) -> CGPoint {
        let padding: CGFloat = 16
        let avoidPad: CGFloat = 10

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
                title: "Welcome",
                body: "Hey, welcome to Sonexis. Since it's your first time here, let me walk you through the basics.",
                showNext: true,
                isBasicsComplete: false
            )
        case .homePresets:
            return (
                title: "Presets",
                body: "Presets is where saved chains live. Open it to see where your sounds go after you save them.",
                showNext: false,
                isBasicsComplete: false
            )
        case .presetsExplore:
            return (
                title: "Browse presets",
                body: "Saved chains show up here. Loading one brings back its effects, wiring, and settings.",
                showNext: true,
                isBasicsComplete: false
            )
        case .presetsBack:
            return (
                title: "Back to Home",
                body: "Head back Home. We'll build a fresh chain next.",
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
                title: "Canvas",
                body: "This is where you build your effect chain. Add effects here, and Sonexis will run your Mac audio through them in order.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildTrayTabs:
            return (
                title: "Effects",
                body: "This is the effects tray. \"Built-in\" contains effects included with Sonexis. \"Plugins\" contains Audio Units installed on your Mac.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildHeaderIntro:
            return (
                title: "Header controls",
                body: "The header runs the session: power, recording, output level, settings, save, and load.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildPower:
            if !isSetupReady {
                return (
                    title: "Power",
                    body: "Sonexis needs audio capture setup before it can run. Open setup, finish it, then start power.",
                    showNext: false,
                    isBasicsComplete: false
                )
            } else {
                return (
                    title: "Power",
                    body: "Press the power button to turn on the audio engine. Keep it running so you can hear each effect as you add it.",
                    showNext: false,
                    isBasicsComplete: false
                )
            }
        case .buildRecord:
            return (
                title: "Record",
                body: "Record saves the processed sound to a WAV file. We'll skip recording now, but this is where it lives.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildOutput:
            return (
                title: "Output meter",
                body: "This meter shows the processed signal leaving Sonexis, so you can tell if the chain is too quiet or too hot.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildSettings:
            return (
                title: "Settings",
                body: "Open Settings to see the controls that affect the whole audio chain.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildSettingsExplain:
            return (
                title: "Audio settings",
                body: "Tap In sets how hard audio enters the chain. Makeup sets the final output level. Ceiling is the safety limiter: keep it on to catch peaks and reduce clipping. Theme only changes the look.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildAddBass:
            return (
                title: "Add Bass Boost",
                body: "Drag Bass Boost onto the canvas.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildAutoExplain:
            return (
                title: "Automatic wiring",
                body: "Sonexis keeps the chain connected automatically. In this mode, sound moves through the blocks from left to right, so the order on the canvas controls the order of the sound.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildAutoAddClarity:
            return (
                title: "Add Clarity",
                body: "Drag Clarity onto the canvas, to the left of Bass Boost.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildAutoReorder:
            return (
                title: "Reorder Clarity",
                body: "Now drag Clarity to the right of Bass Boost.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildManualExplain:
            return (
                title: "Manual wiring",
                body: "Automatic is the quick path. Manual wiring is for exact routes: series chains, splits, and merges.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildDoubleClick:
            return (
                title: "Controls",
                body: "Double-click Bass Boost to open its controls.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildEffectControls:
            return (
                title: "Effect Controls",
                body: "Each effect has its own controls. Adjust them here to change how that effect shapes the sound.",
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
                title: "Block Actions",
                body: "Right-click Bass Boost to open its action menu.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildActionMenu:
            return (
                title: "Action Menu",
                body: "This menu lets you duplicate, delete, or remove connections from a block.",
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
                title: "Manual Wiring",
                body: "Switch Wiring to Manual. In Manual mode, you draw the connections yourself.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildConnect:
            return (
                title: "Connect First Chain",
                body: "Hold Option and drag from Start to Bass Boost. Then drag from Bass Boost to End.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildAutoConnectEnd:
            return (
                title: "Auto-connect End",
                body: "Auto-connect End can finish the last connection for you. Leave it off for now so you can see the wires yourself.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildResetWiringForParallel:
            return (
                title: "Reset wiring",
                body: "Open Canvas and choose Reset Wiring so we can build a parallel route.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildParallelExplain:
            return (
                title: "Parallel Routing",
                body: "Parallel routing lets the sound split into more than one path, then merge back together.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildParallelAddReverb:
            return (
                title: "Add Reverb",
                body: "Reverb is lower in \"Built-in.\" Scroll the tray and drag Reverb onto the canvas.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildParallelConnect:
            return (
                title: "Wire Split",
                body: "Hold Option and connect Start to Bass Boost, then Start to Clarity. Then connect Bass Boost to Reverb, Clarity to Reverb, and Reverb to End.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildClearCanvasForDualMono:
            return (
                title: "Clear the canvas",
                body: "Open Canvas and choose Clear Canvas so we can look at left and right lanes.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildGraphMode:
            return (
                title: "Dual Mono",
                body: "Switch Graph Mode to Dual Mono. This gives the left and right channels separate lanes.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildDualMonoAdd:
            return (
                title: "Add Lane Effects",
                body: "Drag Bass Boost into the left lane and Clarity into the right lane.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildDualMonoConnect:
            return (
                title: "Wire Lanes",
                body: "Hold Option and wire each lane from its Start, through its effect, to its End.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildReturnStereoAuto:
            return (
                title: "Back To Normal",
                body: "Switch Graph Mode back to Stereo and Wiring back to Automatic.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildSave:
            return (
                title: "Save",
                body: "Save this chain as a preset so you can come back to it later.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildSaveConfirm:
            return (
                title: "Saved",
                body: "Saved. Now let's load it back.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildLoad:
            return (
                title: "Load",
                body: "Open Load.",
                showNext: false,
                isBasicsComplete: false
            )
        case .buildCloseLoad:
            return (
                title: "Close Load",
                body: "Close Load when you're done choosing a preset.",
                showNext: false,
                isBasicsComplete: false
            )
        case .basicsComplete:
            return (
                title: "Basics Complete",
                body: "You now know how to build, edit, run, save, and load a normal Sonexis chain. You can end here or continue to the advanced tutorial. You can always reopen Tutorials from Home later.",
                showNext: false,
                isBasicsComplete: true
            )
        case .advancedIntro:
            return (
                title: "Advanced Tutorial",
                body: "Now let's look at routing. This is where you control how blocks connect, split, and merge.",
                showNext: true,
                isBasicsComplete: false
            )
        case .advancedComplete:
            return (
                title: "Advanced Complete",
                body: "You now know how to use manual wiring, parallel routes, and Dual Mono. You can reopen Tutorials from Home anytime.",
                showNext: true,
                isBasicsComplete: false
            )
        case .buildFinish:
            return (
                title: "All set",
                body: "That's the basic loop: open Home, build on the canvas, run audio, adjust, save, and load.",
                showNext: true,
                isBasicsComplete: false
            )
        case .inactive:
            return nil
        }
    }

    private func tutorialCard(title: String, body: String, showNext: Bool, isBasicsComplete: Bool) -> some View {
        let showSetupButtons = step == .buildPower && !isSetupReady
        return TutorialCardView(
            title: title,
            message: body,
            showNext: showNext,
            onNext: onNext,
            onSkip: { showSkipConfirmation = true },
            showSetupButtons: showSetupButtons,
            onOpenSetup: onOpenSetup,
            showSkip: !isBasicsComplete,
            secondaryActionTitle: isBasicsComplete ? "End tutorial" : nil,
            onSecondaryAction: isBasicsComplete ? onEndTutorial : nil,
            primaryActionTitle: isBasicsComplete ? "Continue to advanced tutorial" : nil,
            onPrimaryAction: isBasicsComplete ? onContinueAdvanced : nil
        )
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
