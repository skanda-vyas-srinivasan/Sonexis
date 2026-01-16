import SwiftUI

struct TutorialOverlay: View {
    let step: TutorialStep
    let targets: [TutorialTarget: CGRect]
    let isSetupReady: Bool
    let onNext: () -> Void
    let onSkip: () -> Void
    let onOpenSetup: () -> Void

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
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.neonCyan.opacity(0.9), lineWidth: 2)
                        .shadow(color: AppColors.neonCyan.opacity(0.6), radius: 14)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
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
            return [convertToLocal(rect: targets[.buildButton], proxy: proxy)].compactMap { $0 }
        case .presetsBack:
            return [convertToLocal(rect: targets[.backButton], proxy: proxy)].compactMap { $0 }
        case .buildAutoAddClarity:
            return [
                convertToLocal(rect: targets[.buildClarity], proxy: proxy),
                convertToLocal(rect: targets[.buildCanvas], proxy: proxy)
            ].compactMap { $0 }
        case .buildAutoReorder:
            return [
                convertToLocal(rect: targets[.buildBassNode], proxy: proxy),
                convertToLocal(rect: targets[.buildClarityNode], proxy: proxy)
            ].compactMap { $0 }
        case .buildWiringManual:
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
        case .buildShield:
            return [convertToLocal(rect: targets[.buildShield], proxy: proxy)].compactMap { $0 }
        case .buildOutput:
            return [convertToLocal(rect: targets[.buildOutput], proxy: proxy)].compactMap { $0 }
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

    private func convertToLocal(rect: CGRect?, proxy: GeometryProxy) -> CGRect? {
        guard let rect else { return nil }
        let global = proxy.frame(in: .global)
        return rect.offsetBy(dx: -global.minX, dy: -global.minY)
    }

    @ViewBuilder
    private func dimmingLayer(size: CGSize, highlights: [CGRect]) -> some View {
        if shouldDimBackground {
            if !highlights.isEmpty {
                ZStack {
                    Color.black.opacity(0.55)
                    ForEach(Array(highlights.enumerated()), id: \.offset) { _, rect in
                        RoundedRectangle(cornerRadius: 16)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            } else {
                Color.black.opacity(0.55)
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
            let cardBase = tutorialCard(
                title: content.title,
                body: content.body,
                showNext: content.showNext
            )

            let card = cardBase
                .frame(maxWidth: highlight == nil ? 420 : 360)
                .background(
                    GeometryReader { cardProxy in
                        Color.clear.preference(
                            key: TutorialCardSizePreferenceKey.self,
                            value: cardProxy.size
                        )
                    }
                )
                .onPreferenceChange(TutorialCardSizePreferenceKey.self) { newSize in
                    measuredCardSize = newSize
                }

            if let rect = highlight {
                let position = bestCalloutPosition(
                    screen: size,
                    target: rect,
                    cardSize: measuredCardSize == .zero ? CGSize(width: 360, height: 140) : measuredCardSize
                )
                card.position(position)
            } else {
                let fallbackSize = measuredCardSize == .zero ? CGSize(width: 420, height: 140) : measuredCardSize
                let position = clamp(
                    CGPoint(x: size.width / 2, y: size.height * 0.22),
                    screen: size,
                    cardSize: fallbackSize
                )
                card.position(position)
            }
        } else {
            EmptyView()
        }
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

    private func tutorialContent() -> (title: String, body: String, showNext: Bool)? {
        switch step {
        case .welcome:
            return (
                title: "Welcome",
                body: "Hey, welcome to Sonexis. Since it's your first time here, let me walk you through the key screens.",
                showNext: true
            )
        case .homePresets:
            return (
                title: "Presets",
                body: "This page houses your saved chains. Tap Presets to browse them before heading back.",
                showNext: false
            )
        case .presetsExplore:
            return (
                title: "Browse presets",
                body: "Once you start saving chains, they’ll show up here. Take a quick look around, then press Next to continue.",
                showNext: true
            )
        case .presetsBack:
            return (
                title: "Back to Home",
                body: "Tap Home to return once you’ve reviewed a preset.",
                showNext: false
            )
        case .homeBuild:
            return (
                title: "Build",
                body: "Build opens a fresh canvas for crafting blocks. Tap it when you’re ready.",
                showNext: false
            )
        case .buildIntro:
            return (
                title: "Canvas",
                body: "This is where signal flow happens. Drag effects from the tray into this space.",
                showNext: true
            )
        case .buildHeaderIntro:
            return (
                title: "Header Controls",
                body: "Up top you'll find controls for power, processing, limiter, and output device. Let's walk through them.",
                showNext: true
            )
        case .buildPower:
            if !isSetupReady {
                return (
                    title: "Install BlackHole",
                    body: "You need BlackHole 2ch installed to continue. Press the power button - we'll automatically route your audio through BlackHole!",
                    showNext: false
                )
            } else {
                return (
                    title: "Turn It On",
                    body: "Click the power button to start processing audio. We'll automatically route your system audio through BlackHole. Feel free to play some music!",
                    showNext: false
                )
            }
        case .buildShield:
            return (
                title: "Limiter (Shield)",
                body: "The shield button enables a limiter to prevent clipping. It's on by default to protect your ears.",
                showNext: true
            )
        case .buildOutput:
            return (
                title: "Output Device",
                body: "Choose where you want to hear the processed audio. Select your headphones or speakers from the Output dropdown.",
                showNext: true
            )
        case .buildAddBass:
            return (
                title: "Add Bass Boost",
                body: "Bass Boost fattens the lows. Drag Bass Boost from the Effects tray onto the canvas.",
                showNext: false
            )
        case .buildAutoExplain:
            return (
                title: "Automatic wiring",
                body: "Over here, Automatic wiring connects your effects for you. Add blocks and we’ll keep the signal flowing left to right.",
                showNext: true
            )
        case .buildAutoAddClarity:
            return (
                title: "Add a second block",
                body: "Drag Clarity onto the canvas. It should auto-connect into the chain.",
                showNext: false
            )
        case .buildAutoReorder:
            return (
                title: "Reorder by moving",
                body: "Drag Clarity to the left of Bass Boost. The auto-chain should reorder instantly.",
                showNext: false
            )
        case .buildManualExplain:
            return (
                title: "Manual wiring",
                body: "Manual wiring gives you full control. You can connect in series, build parallel paths, and merge them back together.",
                showNext: true
            )
        case .buildDoubleClick:
            return (
                title: "Open controls",
                body: "Double-click the Bass Boost node to open its controls.",
                showNext: false
            )
        case .buildCloseOverlay:
            return (
                title: "Close controls",
                body: "Nice. Now close the panel (double-click the node again) so we can continue.",
                showNext: false
            )
        case .buildRightClick:
            return (
                title: "Right-click menu",
                body: "Right-click the Bass Boost node to open the action menu.",
                showNext: false
            )
        case .buildCloseContextMenu:
            return (
                title: "Close the menu",
                body: "Click anywhere outside the menu to close it.",
                showNext: false
            )
        case .buildWiringManual:
            return (
                title: "Switch to Manual",
                body: "Switch Wiring to Manual so you can draw connections yourself.",
                showNext: false
            )
        case .buildConnect:
            return (
                title: "Connect nodes",
                body: "Hold Option, then drag from Start to Bass Boost. Then drag from Bass Boost to End.",
                showNext: false
            )
        case .buildAutoConnectEnd:
            return (
                title: "Auto-connect End",
                body: "In manual mode, you wire to End yourself. But you can toggle Auto-connect End ON to automatically wire the last node to End.",
                showNext: true
            )
        case .buildResetWiringForParallel:
            return (
                title: "Reset wiring",
                body: "Before we build a new wiring pattern, reset the current wires. Open Canvas, then click Reset Wiring.",
                showNext: false
            )
        case .buildParallelExplain:
            return (
                title: "Parallel paths",
                body: "Now let’s do a parallel route. We’ll split into two effects, then merge into Reverb.",
                showNext: true
            )
        case .buildParallelAddReverb:
            return (
                title: "Add Reverb",
                body: "Drag Reverb onto the canvas. We’ll use it as the merge point.",
                showNext: false
            )
        case .buildParallelConnect:
            return (
                title: "Wire the parallel merge",
                body: "Option-drag: Start → Bass Boost, Start → Clarity, then Bass Boost → Reverb, Clarity → Reverb, and Reverb → End.",
                showNext: false
            )
        case .buildClearCanvasForDualMono:
            return (
                title: "Clear the canvas",
                body: "Clear the canvas so the next step starts clean. Open Canvas, then click Clear Canvas.",
                showNext: false
            )
        case .buildGraphMode:
            return (
                title: "Graph Mode",
                body: "Dual Mono (L/R) separates the channels. Switch to it to keep left and right processing paths independent.",
                showNext: false
            )
        case .buildDualMonoAdd:
            return (
                title: "Dual Mono demo",
                body: "With Dual Mono on, drag Bass Boost into the left lane, then drag Clarity into the right lane.",
                showNext: false
            )
        case .buildDualMonoConnect:
            return (
                title: "Wire both lanes",
                body: "Hold Option and connect Start L → Bass Boost → End L. Then connect Start R → Clarity → End R.",
                showNext: false
            )
        case .buildReturnStereoAuto:
            return (
                title: "Back to defaults",
                body: "Set Graph Mode back to Stereo, and Wiring back to Automatic.",
                showNext: false
            )
        case .buildSave:
            return (
                title: "Save your chain",
                body: "Save locks this chain into a preset you can reload later.",
                showNext: false
            )
        case .buildSaveConfirm:
            return (
                title: "Saved",
                body: "Nice. Your chain is saved. Next we’ll load a preset.",
                showNext: true
            )
        case .buildLoad:
            return (
                title: "Load presets",
                body: "Open Load, pick a preset, and press Apply.",
                showNext: false
            )
        case .buildCloseLoad:
            return (
                title: "Close Load",
                body: "Close the Load window to finish the tutorial.",
                showNext: false
            )
        case .buildFinish:
            return (
                title: "All set",
                body: "That’s the loop. Build, tweak, save, load. You’re ready to bend audio.",
                showNext: true
            )
        case .inactive:
            return nil
        }
    }

    private func tutorialCard(title: String, body: String, showNext: Bool) -> some View {
        let showSetupButtons = step == .buildPower && !isSetupReady
        return TutorialCardView(
            title: title,
            message: body,
            showNext: showNext,
            onNext: onNext,
            onSkip: { showSkipConfirmation = true },
            showSetupButtons: showSetupButtons,
            onOpenSetup: onOpenSetup
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
