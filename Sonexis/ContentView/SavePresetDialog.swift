import SwiftUI

struct SavePresetDialog: View {
    @Binding var presetName: String
    let onSave: () -> Void
    let onCancel: () -> Void

    private var canSave: Bool {
        !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PresetDialogHeader(
                title: "Save preset"
            )

            PresetDialogTextField(
                text: $presetName,
                placeholder: "Preset name",
                systemImage: nil,
                tint: AppColors.neonPink
            )

            HStack(spacing: 12) {
                Spacer()

                PresetDialogActionButton(
                    title: "Cancel",
                    tint: AppColors.textMuted,
                    isPrimary: false,
                    action: onCancel
                )
                .keyboardShortcut(.cancelAction)

                PresetDialogActionButton(
                    title: "Save",
                    tint: AppColors.neonPink,
                    isPrimary: true,
                    isEnabled: canSave,
                    action: onSave
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 368)
        .sonexisFloatingPanel(tint: AppColors.neonPink, cornerRadius: 12, glowOpacity: 0)
    }
}

struct PresetDialogHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textPrimary.opacity(0.95))

            Spacer()
        }
    }
}

struct PresetDialogTextField: View {
    @Binding var text: String
    let placeholder: String
    let systemImage: String?
    let tint: Color
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isFocused ? tint : AppColors.textMuted)
                    .frame(width: 18)
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .focused($isFocused)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(AppColors.deepBlack.opacity(0.42))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isFocused ? tint.opacity(0.52) : AppColors.controlStrokeSoft.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct PresetDialogActionButton: View {
    let title: String
    let tint: Color
    let isPrimary: Bool
    var isEnabled: Bool = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(foregroundColor)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(fill)
                .overlay(stroke)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }

    private var foregroundColor: Color {
        if isPrimary {
            return AppColors.textPrimary.opacity(0.96)
        }
        return AppColors.textSecondary
    }

    private var fill: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isPrimary ? tint.opacity(isHovered ? 0.24 : 0.17) : AppColors.controlPurple.opacity(isHovered ? 0.46 : 0.30))
    }

    private var stroke: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(isPrimary ? tint.opacity(isHovered ? 0.66 : 0.48) : AppColors.controlStrokeSoft.opacity(isHovered ? 0.68 : 0.48), lineWidth: 1)
    }
}
