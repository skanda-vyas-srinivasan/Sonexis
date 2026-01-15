import SwiftUI

struct SavePresetDialog: View {
    @Binding var presetName: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Save Preset")
                .font(AppTypography.heading)
                .foregroundColor(AppColors.textPrimary)

            TextField("Preset Name", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(presetName.isEmpty)
            }
        }
        .padding()
        .frame(width: 350, height: 150)
        .background(AppColors.midPurple)
        .cornerRadius(16)
    }
}

