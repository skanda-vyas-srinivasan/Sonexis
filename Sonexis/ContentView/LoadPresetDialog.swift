import SwiftUI
import UniformTypeIdentifiers

struct LoadPresetDialog: View {
    @ObservedObject var presetManager: PresetManager
    let tutorialStep: TutorialStep
    let onApply: (SavedPreset) -> Void
    let onCancel: () -> Void
    @State private var searchText = ""
    @State private var showImportPicker = false
    @State private var showExportPicker = false
    @State private var exportDocument: PresetExportDocument?
    @State private var exportFilename = "Preset.sonexis"
    @State private var fileError: String?
    @State private var pendingImport: SavedPreset?
    @State private var showImportConflict = false
    @State private var deletingPreset: SavedPreset?
    @State private var showDeleteConfirm = false
    @State private var renamingPreset: SavedPreset?
    @State private var renameText = ""

    private var canManage: Bool { tutorialStep == .inactive }

    var body: some View {
        let filtered = presetManager.presets.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
        VStack(alignment: .leading, spacing: 12) {
            if tutorialStep == .buildLoad || tutorialStep == .buildCloseLoad {
                LoadPresetTutorialCard(tutorialStep: tutorialStep)
            }
            HStack {
                PresetDialogHeader(title: "Load preset")
                PresetDialogActionButton(title: "Import", tint: AppColors.neonCyan,
                    isPrimary: false, isEnabled: canManage) {
                    showImportPicker = true
                }
            }
            PresetDialogTextField(text: $searchText, placeholder: "Search presets",
                systemImage: "magnifyingglass", tint: AppColors.neonCyan)

            if filtered.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 22))
                    Text(presetManager.presets.isEmpty ? "No saved presets yet" : "No matching presets")
                        .font(AppTypography.body)
                    Text(presetManager.presets.isEmpty ? "Save your current chain or import a preset." : "Try a different name or clear your search.")
                        .font(AppTypography.caption)
                        .multilineTextAlignment(.center)
                    if !searchText.isEmpty {
                        PresetDialogActionButton(title: "Clear search", tint: AppColors.neonCyan,
                            isPrimary: false) { searchText = "" }
                    }
                }
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(filtered) { preset in
                            LoadPresetRow(preset: preset,
                                isDisabled: tutorialStep == .buildCloseLoad,
                                canManage: canManage,
                                onApply: { onApply(preset) },
                                onRename: {
                                    renameText = preset.name
                                    renamingPreset = preset
                                },
                                onExport: { beginExport(preset) },
                                onDelete: {
                                    deletingPreset = preset
                                    showDeleteConfirm = true
                                })
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                PresetDialogActionButton(title: "Cancel", tint: AppColors.textMuted,
                    isPrimary: false, action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 438, height: 500)
        .sonexisFloatingPanel(tint: AppColors.neonCyan, cornerRadius: 12, glowOpacity: 0)
        .fileImporter(isPresented: $showImportPicker,
            allowedContentTypes: [.sonexisPreset, .json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importPreset(url) }
            case .failure(let error): fileError = "Import failed: \(error.localizedDescription)"
            }
        }
        .fileExporter(isPresented: $showExportPicker, document: exportDocument,
            contentType: .sonexisPreset, defaultFilename: exportFilename) { result in
            if case .failure(let error) = result { fileError = "Export failed: \(error.localizedDescription)" }
        }
        .alert("Preset operation failed", isPresented: Binding(
            get: { renamingPreset == nil && (fileError != nil || presetManager.saveError != nil) },
            set: { if !$0 { fileError = nil; presetManager.saveError = nil } }
        )) {
            Button("OK", role: .cancel) { fileError = nil; presetManager.saveError = nil }
        } message: { Text(fileError ?? presetManager.saveError ?? "") }
        .alert("Replace existing preset?", isPresented: $showImportConflict) {
            Button("Replace", role: .destructive) { finishImport(replace: true) }
            Button("Keep Both") { finishImport(replace: false) }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("A preset named \"\(pendingImport?.name ?? "")\" already exists. Keep Both imports a separately named copy.")
        }
        .alert("Delete preset?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let preset = deletingPreset { presetManager.deletePreset(preset) }
                deletingPreset = nil
            }
            Button("Cancel", role: .cancel) { deletingPreset = nil }
        } message: {
            Text("Delete \"\(deletingPreset?.name ?? "")\" from your library? The chain currently on the canvas will stay open.")
        }
        .sheet(item: $renamingPreset) { preset in
            SavePresetDialog(presetName: $renameText, errorMessage: presetManager.saveError,
                title: "Rename preset", actionTitle: "Rename",
                onSave: {
                    if presetManager.renamePreset(id: preset.id, name: renameText) {
                        renamingPreset = nil
                        searchText = ""
                    }
                }, onCancel: { renamingPreset = nil; presetManager.saveError = nil })
        }
    }

    private func beginExport(_ preset: SavedPreset) {
        do {
            exportDocument = PresetExportDocument(data: try encodePresetExportData(preset))
            let safeName = preset.name.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            exportFilename = "\(safeName).sonexis"
            showExportPicker = true
        } catch { fileError = "Export failed: \(error.localizedDescription)" }
    }

    private func importPreset(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let preset = try decodePresetImportData(Data(contentsOf: url))
            if presetManager.presets.contains(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) {
                pendingImport = preset
                showImportConflict = true
            } else if presetManager.addPreset(preset) { searchText = "" }
        } catch { fileError = "Import failed: \(error.localizedDescription)" }
    }

    private func finishImport(replace: Bool) {
        guard let preset = pendingImport else { return }
        var imported = preset
        if !replace {
            var suffix = 2
            var name = "\(preset.name) (\(suffix))"
            while presetManager.presets.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                suffix += 1
                name = "\(preset.name) (\(suffix))"
            }
            imported = SavedPreset(name: name, graph: preset.graph)
        }
        if presetManager.addPreset(imported, overwriteExistingNamed: replace ? preset.name : nil) {
            pendingImport = nil
            searchText = ""
        }
    }
}

private struct LoadPresetTutorialCard: View {
    let tutorialStep: TutorialStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tutorialStep == .buildLoad ? "cursorarrow.click" : "xmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.neonCyan)
                .frame(width: 26, height: 26)
                .background(AppColors.controlPurpleRaised.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(tutorialStep == .buildLoad ? "Load a preset" : "Close this window")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary.opacity(0.94))

                Text(tutorialStep == .buildLoad ? "Choose any row to apply it." : "Press Cancel to continue.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.deepBlack.opacity(0.34))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppColors.neonCyan.opacity(0.38), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct LoadPresetRow: View {
    let preset: SavedPreset
    let isDisabled: Bool
    let canManage: Bool
    let onApply: () -> Void
    let onRename: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onApply) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.neonCyan)
                    .frame(width: 34, height: 34)
                    .background(AppColors.controlPurple)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("\(preset.graph.nodes.count) effects")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("Load \(preset.name)")
        .contextMenu {
            if canManage {
                Button("Rename", action: onRename)
                Button("Export", action: onExport)
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
        .help(canManage ? "\(preset.name) — Click to load; right-click for Rename, Export, or Delete" : preset.name)
        .background(isHovered ? AppColors.controlPurpleRaised.opacity(0.38) : AppColors.deepBlack.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(isDisabled ? 0.42 : 1)
        .onHover { isHovered = $0 }
    }
}
