import SwiftUI

// MARK: - Beginner View

struct BeginnerView: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var effectChain: [ChainedEffect] = []
    @State private var draggedEffect: ChainedEffect?
    @State private var draggedEffectType: EffectType?
    @State private var hoveredDropIndex: Int?
    @State private var showSignalFlow = false
    @State private var dropLocation: CGPoint = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Effect palette at top
            EffectPalette(
                onEffectSelected: { type in
                    addEffectToChain(type)
                },
                onEffectDragged: { type in
                    draggedEffectType = type
                }
            )
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Effect chain area - entire ScrollView is drop target
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .leading) {
                        HStack(spacing: 16) {
                            // Start node
                            StartNodeView()
                                .padding(.leading, 60)

                            FlowConnection(isActive: audioEngine.isRunning && showSignalFlow)

                            // Effect blocks
                            ForEach(Array(effectChain.enumerated()), id: \.element.id) { index, effect in
                                HStack(spacing: 16) {
                                    EffectBlockHorizontal(
                                        effect: effect,
                                        audioEngine: audioEngine,
                                        onRemove: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                removeEffect(at: index)
                                            }
                                        }
                                    )
                                    .transition(.scale.combined(with: .opacity))
                                    .onDrag {
                                        draggedEffect = effect
                                        return NSItemProvider(object: effect.id.uuidString as NSString)
                                    }

                                    FlowConnection(isActive: audioEngine.isRunning && showSignalFlow)
                                }
                            }

                            // Placeholder when empty
                            if effectChain.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "waveform.path")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary.opacity(0.3))
                                    Text("Drag effects here")
                                        .font(.title3)
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                                .frame(width: 200, height: 100)
                            }

                            // End node
                            EndNodeView()
                                .padding(.trailing, 60)
                        }
                        .padding(.vertical, 40)
                        .frame(minWidth: max(geometry.size.width, 800))

                        // Insertion indicator
                        if let insertionIndex = hoveredDropIndex {
                            InsertionIndicator()
                                .offset(x: calculateInsertionX(for: insertionIndex))
                        }
                    }
                    .frame(minHeight: geometry.size.height)
                    .contentShape(Rectangle())  // Make entire area tappable
                }
                .onDrop(of: [.text], delegate: ChainDropDelegate(
                    effectChain: $effectChain,
                    draggedEffect: $draggedEffect,
                    draggedEffectType: $draggedEffectType,
                    hoveredDropIndex: $hoveredDropIndex,
                    dropLocation: $dropLocation,
                    onDrop: { index in
                        handleDrop(at: index)
                    }
                ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    Color(NSColor.textBackgroundColor)

                    // Subtle grid pattern
                    Canvas { context, size in
                        let spacing: CGFloat = 30
                        context.stroke(
                            Path { path in
                                for x in stride(from: 0, through: size.width, by: spacing) {
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: size.height))
                                }
                                for y in stride(from: 0, through: size.height, by: spacing) {
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: size.width, y: y))
                                }
                            },
                            with: .color(.secondary.opacity(0.05)),
                            lineWidth: 1
                        )
                    }
                }
            )
        }
        .onChange(of: audioEngine.isRunning) { isRunning in
            showSignalFlow = isRunning
        }
    }

    private func calculateInsertionX(for index: Int) -> CGFloat {
        let startNodeWidth: CGFloat = 80
        let effectBlockWidth: CGFloat = 120
        let connectionWidth: CGFloat = 100
        let spacing: CGFloat = 16
        let leadingPadding: CGFloat = 60

        if index == 0 {
            return leadingPadding + startNodeWidth + connectionWidth / 2
        } else {
            let offset = leadingPadding + startNodeWidth + connectionWidth + spacing
            return offset + CGFloat(index - 1) * (effectBlockWidth + spacing + connectionWidth)
                + effectBlockWidth + spacing + connectionWidth / 2
        }
    }

    private func handleDrop(at index: Int) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            // Check if we're reordering an existing effect
            if let draggedEffect = draggedEffect,
               let sourceIndex = effectChain.firstIndex(where: { $0.id == draggedEffect.id }) {
                // Reordering
                let effect = effectChain.remove(at: sourceIndex)
                let targetIndex = sourceIndex < index ? index - 1 : index
                effectChain.insert(effect, at: targetIndex)
            }
            // Check if we're adding a new effect from palette
            else if let effectType = draggedEffectType {
                let newEffect = ChainedEffect(type: effectType)
                effectChain.insert(newEffect, at: index)
            }

            applyChainToEngine()
            draggedEffect = nil
            draggedEffectType = nil
            hoveredDropIndex = nil
        }
    }

    private func addEffectToChain(_ type: EffectType) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            let newEffect = ChainedEffect(type: type)
            effectChain.append(newEffect)
            applyChainToEngine()
        }
    }

    private func removeEffect(at index: Int) {
        effectChain.remove(at: index)
        applyChainToEngine()
    }

    private func applyChainToEngine() {
        audioEngine.updateEffectChain(effectChain)
    }
}

// MARK: - Drop Delegate

struct ChainDropDelegate: DropDelegate {
    @Binding var effectChain: [ChainedEffect]
    @Binding var draggedEffect: ChainedEffect?
    @Binding var draggedEffectType: EffectType?
    @Binding var hoveredDropIndex: Int?
    @Binding var dropLocation: CGPoint
    let onDrop: (Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        return true
    }

    func dropEntered(info: DropInfo) {
        dropLocation = info.location
        updateHoveredIndex(location: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropLocation = info.location
        updateHoveredIndex(location: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        hoveredDropIndex = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        if let index = hoveredDropIndex {
            onDrop(index)
        }
        return true
    }

    private func updateHoveredIndex(location: CGPoint) {
        let startNodeWidth: CGFloat = 80
        let effectBlockWidth: CGFloat = 120
        let connectionWidth: CGFloat = 100
        let spacing: CGFloat = 16
        let leadingPadding: CGFloat = 60

        // Calculate which insertion point is closest
        let xPos = location.x

        // Before first effect
        if xPos < leadingPadding + startNodeWidth + connectionWidth {
            hoveredDropIndex = 0
            return
        }

        // Between or after effects
        let chainStartX = leadingPadding + startNodeWidth + connectionWidth + spacing
        let relativeX = xPos - chainStartX

        if effectChain.isEmpty {
            hoveredDropIndex = 0
        } else {
            let blockAndConnectionWidth = effectBlockWidth + spacing + connectionWidth
            let index = Int(relativeX / blockAndConnectionWidth) + 1
            hoveredDropIndex = min(max(0, index), effectChain.count)
        }
    }
}

// MARK: - Insertion Indicator

struct InsertionIndicator: View {
    @State private var pulse = false

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.3), .blue, .blue.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 4, height: 120)
            .cornerRadius(2)
            .shadow(color: .blue.opacity(0.5), radius: pulse ? 12 : 6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Effect Palette (Horizontal)

struct EffectPalette: View {
    let onEffectSelected: (EffectType) -> Void
    let onEffectDragged: (EffectType) -> Void

    private let effects: [EffectType] = [
        .bassBoost, .pitchShift, .clarity, .deMud,
        .simpleEQ, .compressor, .reverb, .stereoWidth,
        .delay, .distortion, .tremolo
    ]

    var body: some View {
        VStack(spacing: 8) {
            Text("Available Effects (Drag or Click to Add)")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(effects, id: \.self) { effectType in
                        EffectPaletteButton(
                            effectType: effectType,
                            onTap: {
                                onEffectSelected(effectType)
                            },
                            onDragStart: {
                                onEffectDragged(effectType)
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

struct EffectPaletteButton: View {
    let effectType: EffectType
    let onTap: () -> Void
    let onDragStart: () -> Void
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: effectType.icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(
                        colors: isHovered ? [.blue.opacity(0.8), .blue] : [.blue.opacity(0.6), .blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: isHovered ? 8 : 4, y: isHovered ? 4 : 2)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .opacity(isDragging ? 0.5 : 1.0)

            Text(effectType.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onTap()
        }
        .onDrag {
            isDragging = true
            onDragStart()
            return NSItemProvider(object: effectType.rawValue as NSString)
        }
    }
}

// MARK: - Start/End Nodes

struct StartNodeView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.green.opacity(0.8), .green],
                        center: .center,
                        startRadius: 10,
                        endRadius: 40
                    )
                )
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                )
                .shadow(color: .green.opacity(0.6), radius: pulse ? 20 : 10)
                .scaleEffect(pulse ? 1.05 : 1.0)

            Text("Start")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .frame(width: 80)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct EndNodeView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.purple.opacity(0.8), .purple],
                        center: .center,
                        startRadius: 10,
                        endRadius: 40
                    )
                )
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                )
                .shadow(color: .purple.opacity(0.6), radius: pulse ? 20 : 10)
                .scaleEffect(pulse ? 1.05 : 1.0)

            Text("End")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .frame(width: 80)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Flow Connection

struct FlowConnection: View {
    let isActive: Bool
    @State private var animationProgress: CGFloat = 0

    var body: some View {
        ZStack {
            // Base line
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 100, height: 2)

            // Animated flow
            if isActive {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .blue, .blue, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 30, height: 3)
                    .offset(x: animationProgress * 70 - 35)
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            animationProgress = 1.0
                        }
                    }
            }
        }
    }
}

// MARK: - Effect Block

struct EffectBlockHorizontal: View {
    let effect: ChainedEffect
    @ObservedObject var audioEngine: AudioEngine
    let onRemove: () -> Void
    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                // Icon and name
                VStack(spacing: 6) {
                    Image(systemName: effect.type.icon)
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(
                            LinearGradient(
                                colors: getEffectEnabled() ? [.blue, .blue.opacity(0.7)] : [.gray, .gray.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(getEffectEnabled() ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                    Text(effect.type.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 80)
                }

                // Control buttons
                HStack(spacing: 8) {
                    // Toggle
                    Button(action: {
                        setEffectEnabled(!getEffectEnabled())
                    }) {
                        Image(systemName: getEffectEnabled() ? "power.circle.fill" : "power.circle")
                            .font(.system(size: 18))
                            .foregroundColor(getEffectEnabled() ? .green : .secondary)
                    }
                    .buttonStyle(.plain)

                    // Expand/collapse
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "slider.horizontal.3")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)

                    // Remove
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(width: 120)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }

            // Expanded parameters
            if isExpanded && getEffectEnabled() {
                VStack(spacing: 12) {
                    EffectParametersViewCompact(effectType: effect.type, audioEngine: audioEngine)
                }
                .padding()
                .frame(width: 200)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.9))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                )
                .padding(.top, 8)
                .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
            }
        }
    }

    private func getEffectEnabled() -> Bool {
        switch effect.type {
        case .bassBoost: return audioEngine.bassBoostEnabled
        case .pitchShift: return audioEngine.nightcoreEnabled
        case .clarity: return audioEngine.clarityEnabled
        case .reverb: return audioEngine.reverbEnabled
        case .compressor: return audioEngine.compressorEnabled
        case .stereoWidth: return audioEngine.stereoWidthEnabled
        case .simpleEQ: return audioEngine.simpleEQEnabled
        case .deMud: return audioEngine.deMudEnabled
        case .delay: return audioEngine.delayEnabled
        case .distortion: return audioEngine.distortionEnabled
        case .tremolo: return audioEngine.tremoloEnabled
        }
    }

    private func setEffectEnabled(_ enabled: Bool) {
        switch effect.type {
        case .bassBoost: audioEngine.bassBoostEnabled = enabled
        case .pitchShift: audioEngine.nightcoreEnabled = enabled
        case .clarity: audioEngine.clarityEnabled = enabled
        case .reverb: audioEngine.reverbEnabled = enabled
        case .compressor: audioEngine.compressorEnabled = enabled
        case .stereoWidth: audioEngine.stereoWidthEnabled = enabled
        case .simpleEQ: audioEngine.simpleEQEnabled = enabled
        case .deMud: audioEngine.deMudEnabled = enabled
        case .delay: audioEngine.delayEnabled = enabled
        case .distortion: audioEngine.distortionEnabled = enabled
        case .tremolo: audioEngine.tremoloEnabled = enabled
        }
    }
}

// MARK: - Compact Parameters View

struct EffectParametersViewCompact: View {
    let effectType: EffectType
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        VStack(spacing: 10) {
            switch effectType {
            case .bassBoost:
                CompactSlider(label: "Amount", value: $audioEngine.bassBoostAmount, range: 0...1, format: .percent)

            case .pitchShift:
                CompactSlider(label: "Intensity", value: $audioEngine.nightcoreIntensity, range: 0...1, format: .percent)

            case .clarity:
                CompactSlider(label: "Amount", value: $audioEngine.clarityAmount, range: 0...1, format: .percent)

            case .deMud:
                CompactSlider(label: "Strength", value: $audioEngine.deMudStrength, range: 0...1, format: .percent)

            case .simpleEQ:
                CompactSlider(label: "Bass", value: $audioEngine.eqBass, range: -1...1, format: .db)
                CompactSlider(label: "Mids", value: $audioEngine.eqMids, range: -1...1, format: .db)
                CompactSlider(label: "Treble", value: $audioEngine.eqTreble, range: -1...1, format: .db)

            case .compressor:
                CompactSlider(label: "Strength", value: $audioEngine.compressorStrength, range: 0...1, format: .percent)

            case .reverb:
                CompactSlider(label: "Mix", value: $audioEngine.reverbMix, range: 0...1, format: .percent)
                CompactSlider(label: "Size", value: $audioEngine.reverbSize, range: 0...1, format: .percent)

            case .stereoWidth:
                CompactSlider(label: "Width", value: $audioEngine.stereoWidthAmount, range: 0...1, format: .percent)

            case .delay:
                CompactSlider(label: "Time", value: $audioEngine.delayTime, range: 0.01...2.0, format: .ms)
                CompactSlider(label: "Feedback", value: $audioEngine.delayFeedback, range: 0...1, format: .percent)
                CompactSlider(label: "Mix", value: $audioEngine.delayMix, range: 0...1, format: .percent)

            case .distortion:
                CompactSlider(label: "Drive", value: $audioEngine.distortionDrive, range: 0...1, format: .percent)
                CompactSlider(label: "Mix", value: $audioEngine.distortionMix, range: 0...1, format: .percent)

            case .tremolo:
                CompactSlider(label: "Rate", value: $audioEngine.tremoloRate, range: 0.1...20, format: .hz)
                CompactSlider(label: "Depth", value: $audioEngine.tremoloDepth, range: 0...1, format: .percent)
            }
        }
    }
}

struct CompactSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: ValueFormat

    enum ValueFormat {
        case percent
        case db
        case ms
        case hz
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formattedValue)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }

    private var formattedValue: String {
        switch format {
        case .percent:
            return "\(Int(value * 100))%"
        case .db:
            let db = value * 12.0
            return String(format: "%+.1f dB", db)
        case .ms:
            return String(format: "%.0f ms", value * 1000)
        case .hz:
            return String(format: "%.1f Hz", value)
        }
    }
}

// MARK: - Supporting Types

struct ChainedEffect: Identifiable {
    let id = UUID()
    let type: EffectType
}

#Preview {
    BeginnerView(audioEngine: AudioEngine())
}
