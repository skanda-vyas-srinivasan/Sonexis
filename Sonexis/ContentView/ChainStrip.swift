import AppKit
import Combine
import SwiftUI
struct ChainStrip: View {
    @ObservedObject var workspace: ChainWorkspace
    @State private var apps = AudioCaptureTarget.runningApps()
    @State private var removingAll = false
    @State private var hoveredID: UUID?
    @State private var hoveredCloseID: UUID?
    @State private var isAddHovered = false
    @State private var draggingID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragCompensation: CGFloat = 0
    @State private var tabWidths: [UUID: CGFloat] = [:]

    private var canCloseApps: Bool {
        !workspace.isRecording && !workspace.tutorial.isActive && workspace.chains.contains { $0.target != nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(workspace.chains) { chain in
                        tab(chain)
                    }
                }
                .coordinateSpace(name: "chain-tabs")
            }
            Menu {
                ForEach(apps.filter { app in !workspace.chains.contains { $0.target?.id == app.id } }) { app in
                    Button { workspace.add(app) } label: {
                        Label {
                            Text(app.name)
                        } icon: {
                            Image(nsImage: AppIconCache.shared.icon(for: app.bundlePath))
                                .renderingMode(.original)
                        }
                    }
                }
                if apps.allSatisfy({ app in workspace.chains.contains { $0.target?.id == app.id } }) {
                    Text("Open another app to add its chain")
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isAddHovered ? AppColors.neonPink : AppColors.textSecondary)
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(AppColors.neonPink)
                            .frame(width: 14, height: 1)
                            .opacity(isAddHovered ? 1 : 0)
                            .offset(y: -7)
                    }
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .onHover { hovering in
                isAddHovered = hovering && workspace.canAddChain
            }
            .accessibilityLabel("Add app chain")
            .tutorialTarget(.addAppChain)
            .padding(.trailing, 4)
            .disabled(!workspace.canAddChain)
        }
        .foregroundStyle(AppColors.textPrimary)
        .frame(height: 40)
        .tutorialTarget(.chainTabs)
        .background(AppColors.panelPurple)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColors.controlStrokeSoft).frame(height: 1)
                .allowsHitTesting(false)
        }
        .contextMenu {
            Button("Close All App Tabs", role: .destructive) { removingAll = true }
                .disabled(!canCloseApps)
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            let refreshed = AudioCaptureTarget.runningApps()
            if refreshed != apps { apps = refreshed }
        }
        .sonexisDialog("Close all app tabs?",
            message: "Their chains will be removed and all apps will use Default.",
            tone: .warning,
            isPresented: $removingAll,
            actions: [
                SonexisDialogAction("Cancel", role: .cancel) {},
                SonexisDialogAction("Close All App Tabs", role: .destructive) { workspace.removeAllAppChains() }
            ]
        )
    }

    private func tab(_ chain: AudioChainDefinition) -> some View {
        let selected = workspace.selectedID == chain.id
        let enabled = chain.effectsEnabled && !workspace.runtime.globallyBypassed
        let isCloseTutorialTarget = workspace.tutorial.step == .chainsClose &&
            workspace.tutorial.practiceChainID == chain.id
        return HStack(spacing: 0) {
            Button { workspace.select(chain.id) } label: {
                HStack(spacing: 7) {
                    if let target = chain.target {
                        Image(nsImage: AppIconCache.shared.icon(for: target.bundlePath))
                            .renderingMode(.original)
                            .resizable()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "speaker.wave.2")
                    }
                    Text(workspace.name(for: chain)).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 160)
                    if let target = chain.target, !apps.contains(where: { $0.id == target.id }) {
                        Image(systemName: "moon").font(.system(size: 10)).foregroundStyle(AppColors.textMuted)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? AppColors.textPrimary : AppColors.textSecondary)
                .padding(.leading, 14).padding(.trailing, chain.target == nil ? 14 : 6)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!workspace.canSelectChain(chain.id))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(enabled ? "Chain enabled" : "Chain disabled")
            if chain.target != nil {
                Button { workspace.remove(chain.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isCloseTutorialTarget ? AppColors.neonCyan :
                            (hoveredCloseID == chain.id ? AppColors.textPrimary : AppColors.textMuted))
                        .frame(width: 18, height: 18)
                        .background {
                            Circle().fill(hoveredCloseID == chain.id ? AppColors.error.opacity(0.78) : .clear)
                        }
                        .frame(width: 24, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .disabled(!workspace.canRemoveChain(chain.id))
                .accessibilityLabel("Close \(workspace.name(for: chain)) chain")
                .onHover { hovering in
                    hoveredCloseID = hovering ? chain.id : (hoveredCloseID == chain.id ? nil : hoveredCloseID)
                }
            }
        }
        .background {
            if isCloseTutorialTarget {
                Color.clear.tutorialTarget(.practiceChainTab)
            }
        }
        .background(selected ? AppColors.controlPurpleRaised.opacity(0.42) :
            (hoveredID == chain.id ? AppColors.controlPurple.opacity(0.62) : .clear))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppColors.controlStrokeSoft.opacity(0.62))
                .frame(width: 1, height: 22)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            if selected {
                Rectangle().fill(AppColors.neonPink).frame(height: 2).padding(.horizontal, 14)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { tabWidths[chain.id] = proxy.size.width }
                    .onChange(of: proxy.size.width) { tabWidths[chain.id] = $0 }
            }
        }
        .offset(x: draggingID == chain.id ? dragTranslation + dragCompensation : 0)
        .zIndex(draggingID == chain.id ? 10 : 0)
        .simultaneousGesture(tabDragGesture(for: chain))
        .onHover { hoveredID = $0 ? chain.id : (hoveredID == chain.id ? nil : hoveredID) }
        .contextMenu {
            Button(chain.effectsEnabled ? "Disable Chain" : "Enable Chain") { workspace.toggleEffects(chain.id) }
                .disabled(!workspace.canToggleChain(chain.id))
            if chain.target != nil {
                Button("Close Tab", role: .destructive) { workspace.remove(chain.id) }.disabled(!workspace.canRemoveChain(chain.id))
            }
            Divider()
            Button("Close All App Tabs", role: .destructive) { removingAll = true }.disabled(!canCloseApps)
        }
    }

    private func tabDragGesture(for chain: AudioChainDefinition) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("chain-tabs"))
            .onChanged { value in
                guard chain.target != nil, !workspace.tutorial.isActive else { return }
                if draggingID == nil {
                    draggingID = chain.id
                    dragTranslation = 0
                    dragCompensation = 0
                }
                guard draggingID == chain.id,
                      let currentIndex = workspace.chains.firstIndex(where: { $0.id == chain.id }) else { return }

                dragTranslation = value.translation.width
                let pointerX = value.location.x

                if currentIndex > 1 {
                    let previous = workspace.chains[currentIndex - 1]
                    if pointerX < tabMidX(previous.id) {
                        compensateForMove(chain.id, from: currentIndex, to: currentIndex - 1)
                        withAnimation(.easeOut(duration: 0.12)) {
                            workspace.moveAppChain(chain.id, toPositionOf: previous.id)
                        }
                        return
                    }
                }

                if currentIndex + 1 < workspace.chains.count {
                    let next = workspace.chains[currentIndex + 1]
                    if pointerX > tabMidX(next.id) {
                        compensateForMove(chain.id, from: currentIndex, to: currentIndex + 1)
                        withAnimation(.easeOut(duration: 0.12)) {
                            workspace.moveAppChain(chain.id, toPositionOf: next.id)
                        }
                    }
                }
            }
            .onEnded { _ in
                guard draggingID == chain.id else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    draggingID = nil
                    dragTranslation = 0
                    dragCompensation = 0
                }
            }
    }

    private func tabMidX(_ id: UUID) -> CGFloat {
        tabOriginX(id) + (tabWidths[id] ?? 0) / 2
    }

    private func tabOriginX(_ id: UUID) -> CGFloat {
        var origin: CGFloat = 0
        for chain in workspace.chains {
            if chain.id == id { break }
            origin += tabWidths[chain.id] ?? 0
        }
        return origin
    }

    private func compensateForMove(_ id: UUID, from sourceIndex: Int, to destinationIndex: Int) {
        let oldOrigin = tabOriginX(id)
        let destination = workspace.chains[destinationIndex]
        let newOrigin: CGFloat
        if sourceIndex < destinationIndex {
            newOrigin = tabOriginX(destination.id) + (tabWidths[destination.id] ?? 0) - (tabWidths[id] ?? 0)
        } else {
            newOrigin = tabOriginX(destination.id)
        }
        dragCompensation += oldOrigin - newOrigin
    }
}
