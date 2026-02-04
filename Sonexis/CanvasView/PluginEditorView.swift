import SwiftUI

struct PluginEditorFallbackView: View {
    @ObservedObject var audioEngine: AudioEngine
    let nodeId: UUID
    @State private var searchText = ""
    @State private var parameters: [PluginParameter] = []

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(AppColors.neonCyan)
                TextField("Search parameters...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Button(action: refreshParameters) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(12)
            .background(AppColors.darkPurple)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.neonCyan.opacity(0.5), lineWidth: 1)
            )
            .cornerRadius(10)

            ScrollView {
                LazyVStack(spacing: 12) {
                    if filteredParameters.isEmpty {
                        Text("No editable parameters available.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textMuted)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(filteredParameters, id: \.id) { param in
                            ParameterRow(
                                parameter: param,
                                onChange: { newValue in
                                    updateParameter(param, value: newValue)
                                }
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(20)
        .background(AppGradients.background)
        .onAppear(perform: refreshParameters)
        .onReceive(Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()) { _ in
            refreshParameters()
        }
    }

    private var filteredParameters: [PluginParameter] {
        if searchText.isEmpty { return parameters }
        return parameters.filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }

    private func refreshParameters() {
        parameters = audioEngine.pluginParameters(for: nodeId)
    }

    private func updateParameter(_ parameter: PluginParameter, value: Double) {
        if let index = parameters.firstIndex(where: { $0.id == parameter.id }) {
            parameters[index].value = value
        }
        audioEngine.setPluginParameter(for: nodeId, parameterId: parameter.id, value: value)
    }
}

private struct ParameterRow: View {
    let parameter: PluginParameter
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(parameter.name)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text(formattedValue)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textMuted)
            }

            Slider(value: Binding(
                get: { parameter.value },
                set: { onChange($0) }
            ), in: parameter.minValue...parameter.maxValue)
            .tint(AppColors.neonCyan)
            .disabled(parameter.isReadOnly)
        }
        .padding(10)
        .background(AppColors.deepBlack.opacity(0.6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.gridLines, lineWidth: 1)
        )
    }

    private var formattedValue: String {
        if let unit = parameter.unitName, !unit.isEmpty {
            return String(format: "%.2f %@", parameter.value, unit)
        }
        return String(format: "%.2f", parameter.value)
    }
}
