import SwiftUI
import SwiftData

struct ProjectDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AdsManager.self) private var adsManager
    @Environment(PurchaseManager.self) private var purchaseManager
    @Query(sort: \ScrapItem.addedAt, order: .reverse) private var scrapItems: [ScrapItem]
    @State private var viewModel: ProjectDetailViewModel

    @State private var showingAddMaterial  = false
    @State private var showingAddPiece     = false
    @State private var showingResult       = false
    @State private var editingMaterial: MaterialItem?  = nil
    @State private var editingPiece: RequiredPiece?    = nil

    init(project: Project) {
        _viewModel = State(wrappedValue: ProjectDetailViewModel(project: project))
    }

    private var project: Project { viewModel.project }

    var body: some View {
        Form {
            materialsSection
            piecesSection
            settingsSection
            optimizeSection
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingAddMaterial) {
            MaterialEditorView(project: project)
        }
        .sheet(item: $editingMaterial) { mat in
            MaterialEditorView(material: mat, project: project)
        }
        .sheet(isPresented: $showingAddPiece) {
            PieceEditorView(project: project)
        }
        .sheet(item: $editingPiece) { piece in
            PieceEditorView(piece: piece, project: project)
        }
        .navigationDestination(isPresented: $showingResult) {
            if let plan = viewModel.cutPlan {
                OptimizationResultView(
                    cutPlan: plan,
                    projectName: project.name,
                    onPresented: {
                        await adsManager.trackCompletedCutAndPresentAdIfNeeded(
                            adsRemoved: purchaseManager.hasRemovedAds
                        )
                    }
                )
            }
        }
        .onDisappear {
            FirebaseSyncService.shared.syncProject(project)
        }
    }

    // MARK: - Sections

    private var materialsSection: some View {
        Section {
            ForEach(project.materials) { mat in
                Button { editingMaterial = mat } label: {
                    MaterialRowView(material: mat)
                }
                .tint(.primary)
            }
            .onDelete { viewModel.deleteMaterials(at: $0, context: modelContext) }

            Button { showingAddMaterial = true } label: {
                Label("Add Material", systemImage: "plus")
            }
        } header: {
            Text("Materials")
        } footer: {
            if project.materials.isEmpty {
                Text("Add the sheet goods or boards you have available.")
            }
        }
    }

    private var piecesSection: some View {
        Section {
            ForEach(project.pieces) { piece in
                Button { editingPiece = piece } label: {
                    PieceRowView(piece: piece)
                }
                .tint(.primary)
            }
            .onDelete { viewModel.deletePieces(at: $0, context: modelContext) }

            Button { showingAddPiece = true } label: {
                Label("Add Piece", systemImage: "plus")
            }
        } header: {
            Text("Required Pieces")
        } footer: {
            if project.pieces.isEmpty {
                Text("Add the pieces you need to cut from your materials.")
            }
        }
    }

    private var settingsSection: some View {
        Section("Settings") {
            inlineDoubleField(
                "Kerf Width",
                value: Binding(
                    get: { project.kerfWidth },
                    set: { project.kerfWidth = $0; project.updatedAt = Date() }
                ),
                placeholder: "0.125"
            )
            inlineDoubleField(
                "Trim Margin",
                value: Binding(
                    get: { project.trimMargin },
                    set: { project.trimMargin = $0; project.updatedAt = Date() }
                ),
                placeholder: "0"
            )
            Picker(
                "Scrap Usage",
                selection: Binding(
                    get: { project.scrapUsageMode },
                    set: {
                        project.scrapUsageMode = $0
                        project.updatedAt = Date()
                    }
                )
            ) {
                ForEach(ScrapUsageMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
        }
    }

    private var optimizeSection: some View {
        Section {
            Button {
                viewModel.optimize(using: scrapItems)
                if viewModel.cutPlan != nil { showingResult = true }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isOptimizing {
                        ProgressView()
                    } else {
                        Label("Optimize Cut Plan", systemImage: "scissors")
                            .font(.headline)
                    }
                    Spacer()
                }
            }
            .disabled(project.materials.isEmpty || project.pieces.isEmpty || viewModel.isOptimizing)
        } footer: {
            if project.materials.isEmpty || project.pieces.isEmpty {
                Text("Add at least one material and one piece to optimize.")
            } else {
                Text(scrapUsageSummary)
            }
        }
    }

    private var scrapUsageSummary: String {
        switch project.scrapUsageMode {
        case .useFirst:
            return "Matching scrap is used first. Sheet cutting then respects type, thickness, and color."
        case .onlyScrap:
            return "Only matching scrap will be used. Pieces without a scrap match will be left unplaced."
        case .ignoreScrap:
            return "Scrap is ignored. Only project materials will be used for cutting."
        }
    }

    // MARK: - Helper

    @ViewBuilder
    private func inlineDoubleField(_ label: String, value: Binding<Double>, placeholder: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(placeholder, value: value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                Text("\"").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Row subviews

struct MaterialRowView: View {
    let material: MaterialItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(material.displayName)
                .font(.body)
            HStack(spacing: 6) {
                Text("\(dimStr(material.width)) × \(dimStr(material.height))")
                Text("·")
                Text("Qty \(material.quantity)")
                if let t = material.thickness {
                    Text("·")
                    Text("\(dimStr(t)) thick")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct PieceRowView: View {
    let piece: RequiredPiece

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(piece.displayName).font(.body)
            HStack(spacing: 6) {
                Text(piece.shapeSummary)
                Text("·")
                Text("×\(piece.quantity)")
                Text("·")
                Text(piece.materialType.rawValue)
                if piece.rotationAllowed {
                    Image(systemName: "rotate.right").imageScale(.small)
                }
                if piece.grainDirectionLocked {
                    Image(systemName: "align.horizontal.left.fill").imageScale(.small)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: piece.colorHex))
                    .frame(width: 10, height: 10)
                Text(piece.materialSummary)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProjectDetailView(project: SampleData.sampleProject)
    }
    .modelContainer(SampleData.previewContainer)
}
