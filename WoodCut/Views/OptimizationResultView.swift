import SwiftUI
import SwiftData
import UIKit

struct OptimizationResultView: View {

    let cutPlan: CutPlan
    let projectName: String
    let onPresented: (() async -> Void)?

    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab  = 0
    /// Tracks which sheet layouts have had their off-cut saved (shows ✓ instead of button).
    @State private var savedLayoutIds: Set<UUID> = []
    @State private var hasHandledPresentation = false
    @State private var shareURL: ExportedPDF?
    @State private var exportError: String?
    @State private var isExporting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryGrid
                    .padding(.horizontal)
                    .padding(.top)

                Divider().padding(.vertical, 12)

                Picker("View Mode", selection: $selectedTab) {
                    Text("Diagrams").tag(0)
                    Text("Instructions").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if selectedTab == 0 {
                    diagramsSection
                } else {
                    instructionsSection
                }

                Spacer(minLength: 32)
            }
        }
        .navigationTitle(projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Share A4 PDF") {
                        exportPDF(mode: .singlePageA4, action: .share)
                    }
                    Button("Print A4 PDF") {
                        exportPDF(mode: .singlePageA4, action: .print)
                    }
                    Button("Share Full-Scale A4 PDF") {
                        exportPDF(mode: .tiledFullScaleA4, action: .share)
                    }
                    Button("Print Full-Scale A4 PDF") {
                        exportPDF(mode: .tiledFullScaleA4, action: .print)
                    }
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(isExporting)
            }
        }
        .sheet(item: $shareURL) { exported in
            ActivityView(items: [exported.url])
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .task {
            guard !hasHandledPresentation else { return }
            hasHandledPresentation = true
            await onPresented?()
        }
    }

    private func exportPDF(mode: CutPlanPDFMode, action: ExportAction) {
        guard !isExporting else { return }
        isExporting = true
        exportError = nil

        Task {
            do {
                let url = try CutPlanPDFExporter.export(cutPlan: cutPlan, projectName: projectName, mode: mode)
                await MainActor.run {
                    isExporting = false
                    switch action {
                    case .share:
                        shareURL = ExportedPDF(url: url)
                    case .print:
                        PrintController.present(url: url, jobName: "\(projectName) \(mode.rawValue)")
                    }
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Summary cards

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Sheets Used",
                     value: "\(cutPlan.sheetsUsed)",
                     icon: "square.stack.3d.up")
            StatCard(title: "From Scrap",
                     value: "\(cutPlan.totalScrapPieces)",
                     icon: "tray.full",
                     accent: cutPlan.totalScrapPieces > 0 ? .green : .secondary)
            StatCard(title: "Est. Waste",
                     value: String(format: "%.1f%%", cutPlan.overallWastePercentage),
                     icon: "trash",
                     accent: wasteColor)
            StatCard(title: "Cut Pieces",
                     value: "\(cutPlan.totalPlacedPieces)",
                     icon: "scissors")
            StatCard(title: "Unplaced",
                     value: "\(cutPlan.unplacedPieces.count)",
                     icon: cutPlan.unplacedPieces.isEmpty
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill",
                     accent: cutPlan.unplacedPieces.isEmpty ? .green : .orange)
        }
    }

    private var wasteColor: Color {
        switch cutPlan.overallWastePercentage {
        case ..<15:  return .green
        case 15..<30: return .orange
        default:     return .red
        }
    }

    // MARK: - Diagrams

    private var diagramsSection: some View {
        LazyVStack(spacing: 24) {
            if !cutPlan.scrapUsages.isEmpty {
                scrapSection
                    .padding(.horizontal)
            }

            ForEach(cutPlan.sheetLayouts) { layout in
                VStack(alignment: .leading, spacing: 8) {
                    // Header row
                    HStack(spacing: 8) {
                        // Material color swatch
                        Circle()
                            .fill(Color(hex: layout.materialColorHex))
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.12), radius: 1)
                        Text("Sheet \(layout.sheetIndex + 1) — \(layout.materialName)")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.1f%% waste", layout.wastePercentage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(dimStr(layout.sheetWidth)) × \(dimStr(layout.sheetHeight))  ·  \(layout.placements.count) piece(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Cut diagram
                    CutDiagramView(layout: layout)
                        .aspectRatio(layout.sheetWidth / layout.sheetHeight, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separator), lineWidth: 1)
                        )

                    // Save off-cut row
                    saveOffCutRow(for: layout)
                }
                .padding(.horizontal)
            }

            if cutPlan.sheetLayouts.isEmpty && cutPlan.scrapUsages.isEmpty {
                ContentUnavailableView(
                    "No Sheets Used",
                    systemImage: "tray",
                    description: Text("No pieces were placed. Check that your materials are large enough.")
                )
                .padding()
            }
        }
        .padding(.top, 16)
    }

    private var scrapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use Scrap First")
                .font(.headline)

            ForEach(cutPlan.scrapUsages) { usage in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: usage.colorHex))
                            .frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(usage.pieceName)
                                .font(.subheadline.weight(.semibold))
                            Text("Take from \(usage.scrapName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(usage.rotated ? "Rotate Piece" : "Use Scrap")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text("\(shapeDimensionText(shape: usage.pieceShape, width: usage.pieceWidth, height: usage.pieceHeight))  from  \(dimStr(usage.scrapWidth)) × \(dimStr(usage.scrapHeight))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(materialSummaryText(materialType: usage.materialType, thickness: usage.thickness, colorHex: usage.colorHex))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Off-cut save button

    @ViewBuilder
    private func saveOffCutRow(for layout: SheetLayout) -> some View {
        // Only show if there's a meaningful remaining piece (>5% of sheet area)
        if let rect = layout.largestFreeRect,
           rect.area > layout.totalArea * 0.05 {

            HStack {
                if savedLayoutIds.contains(layout.id) {
                    Label(
                        "Off-cut saved to Scrap Bin  (\(dimStr(rect.width)) × \(dimStr(rect.height)))",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                    Button {
                        saveOffCut(from: layout, rect: rect)
                    } label: {
                        Label(
                            "Save off-cut  \(dimStr(rect.width)) × \(dimStr(rect.height))  → Scrap Bin",
                            systemImage: "tray.and.arrow.down"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
                Spacer()
            }
        }
    }

    private func saveOffCut(from layout: SheetLayout, rect: LayoutFreeRect) {
        let scrap = ScrapItem(
            name: "Off-cut – \(layout.materialName)",
            width: rect.width,
            height: rect.height,
            thickness: layout.materialThickness,
            materialType: layout.materialType,
            notes: "From \(projectName), Sheet \(layout.sheetIndex + 1)",
            colorHex: layout.materialColorHex
        )
        modelContext.insert(scrap)
        FirebaseSyncService.shared.syncScrap(scrap)
        savedLayoutIds.insert(layout.id)
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(cutPlan.cutInstructions.enumerated()), id: \.offset) { _, line in
                instructionRow(line)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func instructionRow(_ line: String) -> some View {
        if line.isEmpty {
            Spacer().frame(height: 8)
        } else if line.hasPrefix("Sheet ") || line.hasPrefix("From Scrap Bin") {
            Text(line)
                .font(.headline)
                .padding(.top, 4)
        } else if line.hasPrefix("⚠️") || line.hasPrefix("Unplaced") {
            Text(line)
                .font(.subheadline)
                .foregroundStyle(.orange)
        } else if line.hasPrefix("Sheets used") || line.hasPrefix("Estimated") || line.hasPrefix("From scrap") {
            Text(line)
                .font(.subheadline.bold())
        } else {
            Text(line)
                .font(.body)
                .foregroundStyle(line.hasPrefix("  Sheet waste") ? .secondary : .primary)
        }
    }
}

private enum ExportAction {
    case share
    case print
}

private struct ExportedPDF: Identifiable {
    let id = UUID()
    let url: URL
}

private enum PrintController {
    static func present(url: URL, jobName: String) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = jobName
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    let project = SampleData.sampleProject
    let plan = CutOptimizer.optimize(project: project)
    return NavigationStack {
        OptimizationResultView(cutPlan: plan, projectName: project.name, onPresented: nil)
    }
    .modelContainer(SampleData.previewContainer)
}
