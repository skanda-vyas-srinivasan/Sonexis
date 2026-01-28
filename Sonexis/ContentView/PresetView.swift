import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var sonexisPreset: UTType {
        UTType(filenameExtension: "sonexis") ?? UTType(exportedAs: "com.sonexis.preset")
    }
}

struct PresetExportFile: Codable {
    let version: Int
    let preset: SavedPreset
    let exportedAt: Date
}

enum PresetImportError: LocalizedError {
    case invalidFormat
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "The selected file is not a valid Sonexis preset."
        case .unsupportedVersion(let version):
            return "Preset format version \(version) is not supported."
        }
    }
}

struct PresetExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.sonexisPreset, .json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
        if data.isEmpty {
            throw PresetImportError.invalidFormat
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

func encodePresetExportData(_ preset: SavedPreset) throws -> Data {
    let exportFile = PresetExportFile(version: 1, preset: preset, exportedAt: Date())
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(exportFile)
}

func decodePresetImportData(_ data: Data) throws -> SavedPreset {
    let isoDecoder = JSONDecoder()
    isoDecoder.dateDecodingStrategy = .iso8601

    if let exportFile = try? isoDecoder.decode(PresetExportFile.self, from: data) {
        guard exportFile.version == 1 else {
            throw PresetImportError.unsupportedVersion(exportFile.version)
        }
        return exportFile.preset
    }

    if let preset = try? isoDecoder.decode(SavedPreset.self, from: data) {
        return preset
    }

    let defaultDecoder = JSONDecoder()
    if let exportFile = try? defaultDecoder.decode(PresetExportFile.self, from: data) {
        guard exportFile.version == 1 else {
            throw PresetImportError.unsupportedVersion(exportFile.version)
        }
        return exportFile.preset
    }

    if let preset = try? defaultDecoder.decode(SavedPreset.self, from: data) {
        return preset
    }

    throw PresetImportError.invalidFormat
}



struct PresetView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var presetManager: PresetManager
    let onPresetApplied: (SavedPreset) -> Void
    @ObservedObject var tutorial: TutorialController
    @State private var searchText = ""
    @State private var showImportPicker = false
    @State private var showExportPicker = false
    @State private var exportDocument: PresetExportDocument?
    @State private var exportFilename = "Preset.sonexis"
    @State private var fileErrorMessage: String?
    @State private var showFileError = false
    @State private var pendingImportPreset: SavedPreset?
    @State private var showImportConflict = false
    @State private var showRenameDialog = false
    @State private var renamePresetName = ""

    var body: some View {
        let filteredPresets = presetManager.presets.filter { preset in
            searchText.isEmpty || preset.name.lowercased().contains(searchText.lowercased())
        }

        VStack {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppColors.neonCyan)
                    TextField("Search presets...", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(AppColors.textPrimary)
                }
                .padding(10)
                .background(AppColors.midPurple)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.neonCyan.opacity(0.6), lineWidth: 1)
                )
                .cornerRadius(10)
                .frame(maxWidth: 420)

                Spacer()

                Button {
                    showImportPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.neonCyan)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(AppColors.midPurple)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.neonCyan.opacity(0.6), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if filteredPresets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.textMuted)
                    Text("No saved presets")
                        .font(AppTypography.heading)
                        .foregroundColor(AppColors.textSecondary)
                    Text("Create effect chains in Beginner or Advanced mode, then save them as presets")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(filteredPresets) { preset in
                            PresetCard(
                                preset: preset,
                                onApply: {
                                    audioEngine.requestGraphLoad(preset.graph)
                                    onPresetApplied(preset)
                                },
                                onExport: {
                                    beginExport(preset)
                                },
                                onDelete: {
                                    presetManager.deletePreset(preset)
                                },
                                isDisabled: tutorial.step == .presetsExplore || tutorial.step == .presetsBack
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
        .allowsHitTesting(!tutorial.isActive || (tutorial.step != .presetsExplore && tutorial.step != .presetsBack))
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.sonexisPreset, .json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                handleImport(urls: urls)
            case .failure(let error):
                presentFileError(message: "Import failed: \(error.localizedDescription)")
            }
        }
        .fileExporter(
            isPresented: $showExportPicker,
            document: exportDocument,
            contentType: .sonexisPreset,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                presentFileError(message: "Export failed: \(error.localizedDescription)")
            }
        }
        .alert("Import Failed", isPresented: $showFileError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fileErrorMessage ?? "Something went wrong.")
        }
        .alert("Preset Already Exists", isPresented: $showImportConflict) {
            Button("Overwrite", role: .destructive) {
                overwriteImportPreset()
            }
            Button("Change Name") {
                startRenameImport()
            }
            Button("Cancel", role: .cancel) {
                pendingImportPreset = nil
            }
        } message: {
            Text("A preset named \"\(pendingImportPreset?.name ?? "this preset")\" already exists.")
        }
        .sheet(isPresented: $showRenameDialog) {
            RenamePresetDialog(
                presetName: $renamePresetName,
                onSave: {
                    commitRenameImport()
                },
                onCancel: {
                    showRenameDialog = false
                    pendingImportPreset = nil
                }
            )
        }
    }

    private func beginExport(_ preset: SavedPreset) {
        do {
            let data = try encodePresetExportData(preset)
            exportDocument = PresetExportDocument(data: data)
            exportFilename = "\(preset.name).sonexis"
            showExportPicker = true
        } catch {
            presentFileError(message: "Export failed: \(error.localizedDescription)")
        }
    }

    private func handleImport(urls: [URL]) {
        guard let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let preset = try decodePresetImportData(data)
            processImportedPreset(preset)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            presentFileError(message: "Import failed: \(message)")
        }
    }

    private func processImportedPreset(_ preset: SavedPreset) {
        if presetManager.presets.contains(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) {
            pendingImportPreset = preset
            showImportConflict = true
            return
        }

        presetManager.addPreset(preset)
    }

    private func overwriteImportPreset() {
        guard let preset = pendingImportPreset else { return }
        presetManager.addPreset(preset, overwriteExistingNamed: preset.name)
        pendingImportPreset = nil
    }

    private func startRenameImport() {
        renamePresetName = pendingImportPreset?.name ?? ""
        showRenameDialog = true
    }

    private func commitRenameImport() {
        guard let preset = pendingImportPreset else { return }
        let trimmedName = renamePresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if presetManager.presets.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            presentFileError(message: "A preset named \"\(trimmedName)\" already exists.")
            return
        }

        let renamedPreset = SavedPreset(
            id: preset.id,
            name: trimmedName,
            graph: preset.graph,
            createdDate: preset.createdDate
        )
        presetManager.addPreset(renamedPreset)
        pendingImportPreset = nil
        showRenameDialog = false
    }

    private func presentFileError(message: String) {
        fileErrorMessage = message
        showFileError = true
    }
}

struct PresetCard: View {
    let preset: SavedPreset
    let onApply: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    let isDisabled: Bool
    @State private var isHovered = false
    @State private var isMenuHovered = false
    @State private var showDeleteConfirm = false
    @State private var showMenu = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onApply) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.name)
                            .font(AppTypography.heading)
                            .foregroundColor(AppColors.textPrimary)
                        Text("\(preset.graph.nodes.count) effects")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.neonCyan)
                    }
                    Spacer(minLength: 12)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)

            Button {
                showMenu = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isMenuHovered ? AppColors.neonCyan.opacity(0.22) : AppColors.darkPurple)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isMenuHovered ? AppColors.neonCyan : AppColors.gridLines, lineWidth: isMenuHovered ? 2 : 1)
                        )
                        .shadow(color: isMenuHovered ? AppColors.neonCyan.opacity(0.5) : .clear, radius: 10)

                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isMenuHovered ? AppColors.neonCyan : AppColors.textSecondary)
                }
                .frame(width: 48)
                .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isHovered ? 1.0 : 0.0)
            .allowsHitTesting(isHovered && !isDisabled)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isMenuHovered = hovering
                }
            }
            .popover(isPresented: $showMenu, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        showMenu = false
                        onExport()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }

                    Divider()
                        .background(AppColors.gridLines)

                    Button(role: .destructive) {
                        showMenu = false
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textPrimary)
                .padding(12)
                .background(AppColors.darkPurple)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.neonCyan.opacity(0.4), lineWidth: 1)
                )
                .cornerRadius(12)
                .padding(6)
            }
        }
        .background(isHovered ? AppColors.midPurple : AppColors.darkPurple)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isMenuHovered ? AppColors.neonCyan : (isHovered ? AppColors.neonPink : AppColors.gridLines),
                    lineWidth: (isHovered || isMenuHovered) ? 2 : 1
                )
        )
        .cornerRadius(12)
        .shadow(color: AppColors.neonPink.opacity(isHovered ? 0.4 : 0), radius: 12)
        .opacity(isDisabled ? 0.4 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .alert("Delete preset?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

struct RenamePresetDialog: View {
    @Binding var presetName: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Preset")
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

                Button("Import") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 350, height: 150)
        .background(AppColors.midPurple)
        .cornerRadius(16)
    }
}

// CanvasView is now in CanvasView.swift

// Preview disabled to avoid build-time macro errors.
