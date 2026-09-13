import SwiftUI
import AppKit

extension CanvasView {
    @ViewBuilder
    var floatingContextMenuLayer: some View {
        if let menu = customContextMenu {
            let rootMenu = contextMenuInRootCoordinates(menu)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissCustomContextMenu()
                    }
                    .zIndex(CanvasLayerZIndex.floatingBackdrop)

                CustomContextMenuView(menu: rootMenu) {
                    dismissCustomContextMenu()
                }
                .zIndex(CanvasLayerZIndex.floatingMenu)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func contextMenuInRootCoordinates(_ menu: CustomContextMenu) -> CustomContextMenu {
        CustomContextMenu(
            anchor: CGPoint(
                x: menu.anchor.x + canvasDocumentFrameInRoot.minX,
                y: menu.anchor.y + canvasDocumentFrameInRoot.minY
            ),
            position: CGPoint(
                x: menu.position.x + canvasDocumentFrameInRoot.minX,
                y: menu.position.y + canvasDocumentFrameInRoot.minY
            ),
            tint: menu.tint,
            items: menu.items
        )
    }

    func dismissCustomContextMenu() {
        customContextMenu = nil
        wireContextMenu = nil
        tutorial.advanceIf(.buildCloseContextMenu)
    }

    func updateCanvasSizeIfNeeded(_ newSize: CGSize) {
        guard canvasSize != newSize else { return }
        canvasSize = newSize
        prepareAdvancedTutorialCanvasIfNeeded()
    }

    func prepareAdvancedTutorialCanvasIfNeeded() {
        guard tutorial.step == .advancedIntro, !didPrepareAdvancedTutorialCanvas else { return }
        guard canvasSize.width > 1, canvasSize.height > 1 else { return }

        let size = canvasSize
        let centerY = max(size.height * 0.5, 120)
        let verticalOffset = min(120, max(80, size.height * 0.2))
        let bassPosition = clamp(
            CGPoint(x: max(size.width * 0.42, 220), y: centerY - verticalOffset),
            to: size,
            lane: nil
        )
        let clarityPosition = clamp(
            CGPoint(x: max(size.width * 0.58, 360), y: centerY + verticalOffset),
            to: size,
            lane: nil
        )

        didPrepareAdvancedTutorialCanvas = true
        isRestoringSnapshot = true
        graphMode = .single
        wiringMode = .automatic
        autoConnectEnd = false
        manualConnections.removeAll()
        autoGainOverrides.removeAll()
        selectedNodeIDs.removeAll()
        selectedWireID = nil
        selectedAutoWire = nil
        customContextMenu = nil
        wireContextMenu = nil
        activeConnectionFromID = nil
        activeConnectionPoint = .zero
        lassoStart = nil
        lassoCurrent = nil

        effectChain = [
            BeginnerNode(type: .bassBoost, position: bassPosition, lane: .left, accentIndex: 0),
            BeginnerNode(type: .clarity, position: clarityPosition, lane: .left, accentIndex: 1)
        ]
        nextAccentIndex = accentPalette.isEmpty ? 0 : 2 % accentPalette.count
        applyChainToEngine(reason: "advanced tutorial setup", forceAudioApply: true)

        DispatchQueue.main.async {
            isRestoringSnapshot = false
        }
    }

    func updateFocusState(isKeyWindow: Bool) {
        let active = scenePhase == .active && isKeyWindow
        let shouldShowSignalFlow = active && audioEngine.isRunning
        guard isWindowKey != isKeyWindow ||
            isAppActive != active ||
            showSignalFlow != shouldShowSignalFlow else {
            return
        }
        isWindowKey = isKeyWindow
        isAppActive = active
        showSignalFlow = shouldShowSignalFlow
    }

    func updateSignalFlowVisibility(
        scenePhase phase: ScenePhase? = nil,
        isRunning running: Bool? = nil
    ) {
        let resolvedPhase = phase ?? scenePhase
        let resolvedRunning = running ?? audioEngine.isRunning
        let active = resolvedPhase == .active && isWindowKey
        let shouldShowSignalFlow = active && resolvedRunning
        guard isAppActive != active || showSignalFlow != shouldShowSignalFlow else { return }
        isAppActive = active
        showSignalFlow = shouldShowSignalFlow
    }

    func restorePendingGraphSnapshot(
        _ snapshot: GraphSnapshot,
        mode: GraphLoadMode,
        reason: String
    ) {
        isRestoringSnapshot = true
        expandedControlPanelLifts.removeAll()
        applyGraphSnapshot(
            snapshot,
            mode: mode,
            reason: reason
        )
        DispatchQueue.main.async {
            isRestoringSnapshot = false
            if tutorial.step == .advancedIntro {
                didPrepareAdvancedTutorialCanvas = false
                prepareAdvancedTutorialCanvasIfNeeded()
            }
        }
    }

    func updateCursor() {
        guard isCanvasHovering else {
            NSCursor.arrow.set()
            return
        }
        if isOptionHeld && wiringMode == .manual {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    func triggerDropAnimation(for id: UUID) {
        dropAnimatedNodeIDs.insert(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            dropAnimatedNodeIDs.remove(id)
        }
    }

    func openPluginEditor(for nodeId: UUID) {
        let fallbackView = NSHostingView(
            rootView: PluginEditorFallbackView(
                audioEngine: audioEngine,
                nodeId: nodeId
            )
        )
        fallbackView.frame = NSRect(x: 0, y: 0, width: 720, height: 520)
        audioEngine.openPluginEditor(for: nodeId, fallbackView: fallbackView)
    }


    func removeEffect(id: UUID) {
        effectChain.removeAll { $0.id == id }
        manualConnections.removeAll { $0.fromNodeId == id || $0.toNodeId == id }
        autoGainOverrides = autoGainOverrides.filter { $0.key.from != id && $0.key.to != id }
        selectedNodeIDs.remove(id)
        expandedControlPanelLifts.removeValue(forKey: id)
        normalizeAllOutgoingGains()
        applyChainToEngine()
    }

    func duplicateEffect(id: UUID) {
        guard let index = effectChain.firstIndex(where: { $0.id == id }) else { return }
        let source = effectChain[index]
        var clone = BeginnerNode(
            type: source.type,
            position: CGPoint(x: source.position.x + 40, y: source.position.y + 40),
            lane: source.lane,
            isEnabled: source.isEnabled,
            parameters: source.parameters,
            accentIndex: source.accentIndex,
            plugin: source.plugin
        )
        clone.position = clamp(clone.position, to: canvasSize, lane: graphMode == .split ? clone.lane : nil)
        effectChain.append(clone)
        applyChainToEngine()
    }

    func duplicateEffects(ids: Set<UUID>) {
        let sources = effectChain.filter { ids.contains($0.id) }
        guard !sources.isEmpty else { return }

        let clones = sources.map { source in
            var clone = BeginnerNode(
                type: source.type,
                position: CGPoint(x: source.position.x + 40, y: source.position.y + 40),
                lane: source.lane,
                isEnabled: source.isEnabled,
                parameters: source.parameters,
                accentIndex: source.accentIndex,
                plugin: source.plugin
            )
            clone.position = clamp(clone.position, to: canvasSize, lane: graphMode == .split ? clone.lane : nil)
            return clone
        }

        effectChain.append(contentsOf: clones)
        selectedNodeIDs = Set(clones.map(\.id))
        applyChainToEngine()
    }

    func resetEffectParameters(id: UUID) {
        guard let index = effectChain.firstIndex(where: { $0.id == id }) else { return }
        effectChain[index].parameters = NodeEffectParameters.defaults()
        updateChainParametersOnly()
    }

    func removeEffects(ids: Set<UUID>) {
        effectChain.removeAll { ids.contains($0.id) }
        manualConnections.removeAll { ids.contains($0.fromNodeId) || ids.contains($0.toNodeId) }
        autoGainOverrides = autoGainOverrides.filter { !ids.contains($0.key.from) && !ids.contains($0.key.to) }
        selectedNodeIDs.subtract(ids)
        expandedControlPanelLifts = expandedControlPanelLifts.filter { !ids.contains($0.key) }
        normalizeAllOutgoingGains()
        applyChainToEngine()
    }

    func deleteWiresForSelected() {
        manualConnections.removeAll { selectedNodeIDs.contains($0.fromNodeId) || selectedNodeIDs.contains($0.toNodeId) }
        normalizeAllOutgoingGains()
        applyChainToEngine()
    }

}
