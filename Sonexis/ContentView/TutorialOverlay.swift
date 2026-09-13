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
