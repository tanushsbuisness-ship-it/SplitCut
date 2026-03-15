import SwiftUI
import SwiftData
import UIKit
internal import os

struct OptimizationResultView: View {

    let cutPlan: CutPlan
    let project: Project
    let onPresented: (() async -> Void)?

    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab  = 0
    /// Tracks which sheet layouts have had their off-cut saved (shows ✓ instead of button).
    @State private var savedLayoutIds: Set<UUID> = []
    /// Tracks which scrap pieces have been updated with new cuts
    @State private var savedScrapIds: Set<UUID> = []
    /// Tracks which scrap usages should show on new piece instead of scrap piece
    @State private var showOnNewPiece: Set<UUID> = []
    @State private var hasHandledPresentation = false
    @State private var shareURL: ExportedPDF?
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var showingSavePlanSuccess = false
    
    private var projectName: String { project.name }
    

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
                    Button {
                        savePlan()
                    } label: {
                        Label("Save Plan", systemImage: "bookmark.fill")
                    }
                    
                    Divider()
                    
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
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .disabled(isExporting)
            }
        }
        .sheet(item: $shareURL) { exported in
            ActivityView(items: [exported.url])
        }
        .alert("Plan Saved!", isPresented: $showingSavePlanSuccess) {
            Button("OK") { }
        } message: {
            Text("You can view your saved plans in the Plans tab.")
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
    
    // MARK: - Actions
    
    private func savePlan() {
        let savedPlan = SavedPlan(
            projectId: project.id,
            projectName: project.name,
            cutPlan: cutPlan,
            notes: ""
        )
        
        modelContext.insert(savedPlan)
        
        do {
            try modelContext.save()
            showingSavePlanSuccess = true
            AppLogger.app.info("Plan saved successfully: \(projectName)")
        } catch {
            AppLogger.app.error("Failed to save plan: \(error.localizedDescription)")
            exportError = "Failed to save plan: \(error.localizedDescription)"
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

            // Group usages by scrap ID to show all cuts from the same scrap together
            ForEach(groupedScrapUsages, id: \.scrapId) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: group.colorHex))
                            .frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(group.usages.count) piece(s) from \(group.scrapName)")
                                .font(.subheadline.weight(.semibold))
                            Text("\(dimStr(group.scrapWidth)) × \(dimStr(group.scrapHeight))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Use Scrap")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    // List all pieces being cut from this scrap
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(group.usages.enumerated()), id: \.offset) { index, usage in
                            HStack(spacing: 6) {
                                Text("\(index + 1).")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(usage.pieceName)
                                    .font(.caption)
                                Text("—")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(shapeDimensionText(shape: usage.pieceShape, width: usage.pieceWidth, height: usage.pieceHeight))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if usage.rotated {
                                    Image(systemName: "rotate.right")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    Text(materialSummaryText(materialType: group.materialType, thickness: group.thickness, colorHex: group.colorHex))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    // Cut diagram showing all pieces on scrap or new piece
                    if showOnNewPiece.contains(group.scrapId) {
                        // Show on a new full-size piece from project materials
                        if let matchingMaterial = findMatchingMaterial(for: group.usages.first!) {
                            MultiScrapCutDiagramView(
                                usages: group.usages,
                                showOnScrap: false,
                                materialWidth: matchingMaterial.width,
                                materialHeight: matchingMaterial.height,
                                scrapId: group.scrapId
                            )
                            .aspectRatio(matchingMaterial.width / matchingMaterial.height, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                        } else {
                            // No matching material available
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                Text("No matching material in project")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    } else {
                        // Show on the scrap piece (default)
                        MultiScrapCutDiagramView(
                            usages: group.usages,
                            showOnScrap: true,
                            materialWidth: group.scrapWidth,
                            materialHeight: group.scrapHeight,
                            scrapId: group.scrapId
                        )
                        .aspectRatio(group.scrapWidth / group.scrapHeight, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                    }
                    
                    HStack {
                        // Toggle button
                        Button {
                            if showOnNewPiece.contains(group.scrapId) {
                                showOnNewPiece.remove(group.scrapId)
                            } else {
                                showOnNewPiece.insert(group.scrapId)
                            }
                        } label: {
                            Label(
                                showOnNewPiece.contains(group.scrapId) ? "Show on Scrap" : "Show on New Piece",
                                systemImage: showOnNewPiece.contains(group.scrapId) ? "tray.full" : "square.stack"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                        .disabled(showOnNewPiece.contains(group.scrapId) && findMatchingMaterial(for: group.usages.first!) == nil)
                        
                        Spacer()
                        
                        // Update scrap button
                        if !savedScrapIds.contains(group.scrapId) {
                            Button {
                                updateScrapWithCuts(scrapId: group.scrapId, usages: group.usages)
                            } label: {
                                Label("Update Scrap Bin", systemImage: "tray.and.arrow.down")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        } else {
                            Label("Scrap Updated", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    /// Group scrap usages by scrap ID so multiple cuts from the same scrap show together
    private var groupedScrapUsages: [GroupedScrapUsage] {
        let grouped = Dictionary(grouping: cutPlan.scrapUsages, by: { $0.scrapId })
        return grouped.map { (scrapId, usages) in
            let first = usages.first!
            return GroupedScrapUsage(
                scrapId: scrapId,
                scrapName: first.scrapName,
                scrapWidth: first.scrapWidth,
                scrapHeight: first.scrapHeight,
                materialType: first.materialType,
                thickness: first.thickness,
                colorHex: first.colorHex,
                usages: usages
            )
        }.sorted { $0.scrapName < $1.scrapName }
    }
    
    private func updateScrapWithCuts(scrapId: UUID, usages: [ScrapUsage]) {
        // Find the scrap item in the database
        let fetchDescriptor = FetchDescriptor<ScrapItem>(
            predicate: #Predicate { $0.id == scrapId }
        )
        
        guard let scrapItem = try? modelContext.fetch(fetchDescriptor).first else {
            AppLogger.scrap.warning("Could not find scrap item with id: \(scrapId.uuidString)")
            return
        }
        
        AppLogger.scrap.info("Updating scrap '\(scrapItem.displayName)' with \(usages.count) new cuts")
        
        // Get existing cuts
        var allCuts = scrapItem.cuts
        
        // Add all new cuts
        for usage in usages {
            let cut = usage.toScrapCut()
            allCuts.append(cut)
        }
        
        // Update cuts array
        scrapItem.cuts = allCuts
        
        // Use free rects from the LAST usage (cumulative state after all cuts)
        if let lastUsage = usages.last {
            scrapItem.freeRects = lastUsage.updatedFreeRects
        }
        
        // Force save to database
        do {
            try modelContext.save()
            AppLogger.scrap.info("Scrap saved successfully: \(scrapItem.displayName) now has \(scrapItem.cuts.count) cuts, \(scrapItem.freeRects.count) free rects")
        } catch {
            AppLogger.scrap.error("Failed to save scrap: \(error.localizedDescription)")
        }
        
        // Sync to Firebase
        FirebaseSyncService.shared.syncScrap(scrapItem)
        savedScrapIds.insert(scrapId)
    }

    // MARK: - Off-cut save button
    
    /// Find a material from the project that matches the scrap usage requirements
    private func findMatchingMaterial(for usage: ScrapUsage) -> MaterialItem? {
        project.materials.first { material in
            material.materialType == usage.materialType &&
            materialThicknessMatches(material.thickness, usage.thickness) &&
            normalizedMaterialColorHex(material.colorHex) == normalizedMaterialColorHex(usage.colorHex)
        }
    }

    @ViewBuilder
    private func saveOffCutRow(for layout: SheetLayout) -> some View {
        // Show if there's a meaningful remaining piece (>2% of sheet area or larger than 3"x3")
        if let rect = layout.largestFreeRect,
           rect.area > layout.totalArea * 0.02 || (rect.width >= 3 && rect.height >= 3) {

            HStack {
                if savedLayoutIds.contains(layout.id) {
                    Label(
                        "Sheet saved to Scrap Bin with cuts",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.green)
                } else {
                    Button {
                        saveOffCut(from: layout, rect: rect)
                    } label: {
                        HStack {
                            Image(systemName: "tray.and.arrow.down")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save leftover sheet → Scrap Bin")
                                Text("Remaining: \(dimStr(rect.width)) × \(dimStr(rect.height))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                Spacer()
            }
        }
    }

    private func saveOffCut(from layout: SheetLayout, rect: LayoutFreeRect) {
        // Save the FULL sheet dimensions with all cuts recorded
        // This preserves the actual L-shaped or irregular piece shape
        
        AppLogger.scrap.info("Saving off-cut from sheet \(layout.sheetIndex + 1)")
        
        // Convert all placements to ScrapCut format
        let cuts = layout.placements.map { placement in
            ScrapCut(
                x: placement.x,
                y: placement.y,
                width: placement.width,
                height: placement.height,
                shape: placement.pieceShape,
                pieceName: placement.pieceName
            )
        }
        
        // Convert free rectangles to ScrapFreeRect format
        let freeRects = layout.finalFreeRects.map { freeRect in
            ScrapFreeRect(
                x: freeRect.x,
                y: freeRect.y,
                width: freeRect.width,
                height: freeRect.height
            )
        }
        
        let scrap = ScrapItem(
            name: "Off-cut – \(layout.materialName)",
            width: layout.sheetWidth,  // Full original sheet width
            height: layout.sheetHeight, // Full original sheet height
            thickness: layout.materialThickness,
            materialType: layout.materialType,
            notes: "From \(projectName), Sheet \(layout.sheetIndex + 1)",
            colorHex: layout.materialColorHex,
            cuts: cuts  // All cuts made from this sheet
        )
        
        // Set the free rectangles to match the current state
        scrap.freeRects = freeRects
        
        modelContext.insert(scrap)
        
        // Explicitly save to database
        do {
            try modelContext.save()
            AppLogger.scrap.info("Off-cut saved from sheet \(layout.sheetIndex + 1) with \(cuts.count) cuts and \(freeRects.count) free rects")
        } catch {
            AppLogger.scrap.error("Failed to save off-cut: \(error.localizedDescription)")
        }
        
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

// MARK: - Scrap Cut Diagram

/// Renders a visual diagram showing how to cut a piece from a scrap item.
/// Can show either the cut on the scrap piece or on a new full-size piece.
struct ScrapCutDiagramView: View {
    let usage: ScrapUsage
    let showOnScrap: Bool
    let materialWidth: Double
    let materialHeight: Double
    
    private var baseColor: Color { Color(hex: usage.colorHex) }
    private var preset: MaterialColorPreset? { MaterialColorPreset.preset(for: usage.colorHex) }
    
    // Piece fill color (matching CutDiagramView palette)
    private var pieceColor: Color {
        Color(red: 0.33, green: 0.62, blue: 0.80).opacity(0.78)  // steel blue
    }
    
    private var pieceStrokeColor: Color {
        Color(red: 0.33, green: 0.62, blue: 0.80)
    }
    
    var body: some View {
        if showOnScrap {
            scrapDiagram
        } else {
            newPieceDiagram
        }
    }
    
    // MARK: - Scrap Diagram (piece on scrap background)
    
    private var scrapDiagram: some View {
        Canvas { context, size in
            let scaleX = size.width / materialWidth
            let scaleY = size.height / materialHeight
            let scale = min(scaleX, scaleY)
            
            let drawW = materialWidth * scale
            let drawH = materialHeight * scale
            let scrapRect = CGRect(x: 0, y: 0, width: drawW, height: drawH)
            
            // 1. Scrap background
            context.fill(Path(scrapRect), with: .color(baseColor))
            
            // 2. Wood grain (if applicable)
            if let grainColor = preset?.grainColor {
                drawGrain(context: context, width: drawW, height: drawH, color: grainColor)
            }
            
            // 3. Scrap border
            context.stroke(Path(scrapRect), with: .color(.primary.opacity(0.8)), lineWidth: 2)
            
            // 4. Piece placement (at origin by default, accounting for rotation)
            let pieceW = usage.rotated ? usage.pieceHeight : usage.pieceWidth
            let pieceH = usage.rotated ? usage.pieceWidth : usage.pieceHeight
            
            let pieceRect = CGRect(
                x: 0,
                y: 0,
                width: pieceW * scale,
                height: pieceH * scale
            )
            
            let piecePath = path(for: usage.pieceShape, in: pieceRect)
            
            // 5. Draw the actual piece to keep
            context.fill(piecePath, with: .color(pieceColor))
            context.stroke(piecePath, with: .color(pieceStrokeColor), lineWidth: 2.5)
            
            // 6. Label if large enough
            if pieceRect.width >= 30 && pieceRect.height >= 18 {
                let fontSize = min(pieceRect.height * 0.25, 14.0)
                let labelText = usage.pieceShape == .rectangle
                    ? usage.pieceName
                    : "\(usage.pieceName)\n\(usage.pieceShape.rawValue)"
                let label = Text(labelText)
                    .font(.system(size: max(fontSize, 8), weight: .semibold))
                    .foregroundStyle(Color.primary)
                context.draw(label, in: pieceRect.insetBy(dx: 4, dy: 3))
            }
            
            // 7. Rotation indicator if rotated
            if usage.rotated {
                let rotationLabel = Text("↻ Rotated")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.orange)
                let rotationRect = CGRect(
                    x: drawW - 60,
                    y: 5,
                    width: 55,
                    height: 15
                )
                context.draw(rotationLabel, in: rotationRect)
            }
        }
    }
    
    // MARK: - New Piece Diagram (just the piece itself)
    
    private var newPieceDiagram: some View {
        Canvas { context, size in
            let pieceW = usage.pieceWidth
            let pieceH = usage.pieceHeight
            
            // Use the actual material dimensions for the background
            let scaleX = size.width / materialWidth
            let scaleY = size.height / materialHeight
            let scale = min(scaleX, scaleY)
            
            let drawW = materialWidth * scale
            let drawH = materialHeight * scale
            let fullRect = CGRect(x: 0, y: 0, width: drawW, height: drawH)
            
            // 1. Background (full material sheet)
            context.fill(Path(fullRect), with: .color(baseColor))
            
            // 2. Wood grain (if applicable)
            if let grainColor = preset?.grainColor {
                drawGrain(context: context, width: drawW, height: drawH, color: grainColor)
            }
            
            // 3. Border for the full sheet
            context.stroke(Path(fullRect), with: .color(.primary.opacity(0.8)), lineWidth: 2)
            
            // 4. The cut piece (at origin)
            let pieceRect = CGRect(x: 0, y: 0, width: pieceW * scale, height: pieceH * scale)
            let piecePath = path(for: usage.pieceShape, in: pieceRect)
            
            // 5. Fill the piece area slightly darker to show it's the cut area
            context.fill(piecePath, with: .color(pieceColor.opacity(0.3)))
            
            // 6. Draw cut line around the shape
            context.stroke(piecePath, with: .color(.red), 
                          style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
            
            // 7. Label
            if pieceRect.width >= 30 && pieceRect.height >= 18 {
                let fontSize = min(pieceRect.height * 0.25, 14.0)
                let labelText = usage.pieceShape == .rectangle
                    ? "\(usage.pieceName)\nCut along red line"
                    : "\(usage.pieceName)\n\(usage.pieceShape.rawValue)\nCut along red line"
                let label = Text(labelText)
                    .font(.system(size: max(fontSize, 7), weight: .semibold))
                    .foregroundStyle(Color.primary)
                context.draw(label, in: pieceRect.insetBy(dx: 4, dy: 3))
            }
            
            // 8. Dimension labels
            drawDimensionLabels(context: context, rect: pieceRect, shape: usage.pieceShape)
        }
    }
    
    /// Draw dimension labels for the cut
    private func drawDimensionLabels(context: GraphicsContext, rect: CGRect, shape: PieceShape) {
        let widthLabel = Text(dimStr(usage.pieceWidth))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.blue)
        
        let heightLabel = Text(dimStr(usage.pieceHeight))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.blue)
        
        // Width dimension (bottom)
        let widthRect = CGRect(
            x: rect.midX - 25,
            y: rect.maxY - 15,
            width: 50,
            height: 12
        )
        context.draw(widthLabel, in: widthRect)
        
        // Height dimension (right side, rotated)
        var heightContext = context
        heightContext.translateBy(x: rect.maxX - 15, y: rect.midY)
        heightContext.rotate(by: .degrees(-90))
        let heightRect = CGRect(x: -25, y: 0, width: 50, height: 12)
        heightContext.draw(heightLabel, in: heightRect)
    }
    
    // MARK: - Helpers
    
    private func path(for shape: PieceShape, in rect: CGRect) -> Path {
        switch shape {
        case .rectangle:
            return Path(rect)
        case .triangle:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
            return path
        case .circle:
            return Path(ellipseIn: rect)
        case .semicircle:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.midX, y: rect.maxY),
                radius: rect.width / 2,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.closeSubpath()
            return path
        case .quarterCircle:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX, y: rect.maxY),
                radius: rect.width,
                startAngle: .degrees(0),
                endAngle: .degrees(-90),
                clockwise: true
            )
            path.closeSubpath()
            return path
        }
    }
    
    private func drawGrain(context: GraphicsContext, width: CGFloat, height: CGFloat, color: Color) {
        let spacing: CGFloat = 3.5
        let lineCount = Int(height / spacing) + 1
        let segmentCount = max(Int(width / 8), 10)
        
        for i in 0..<lineCount {
            let yBase = CGFloat(i) * spacing
            let amp = CGFloat(0.55 + 0.25 * sin(Double(i) * 0.41))
            let freq = 0.55 + 0.15 * sin(Double(i) * 0.17)
            let phase = Double(i) * 1.3
            
            var path = Path()
            path.move(to: CGPoint(x: 0, y: yBase))
            for s in 1...segmentCount {
                let x = width * CGFloat(s) / CGFloat(segmentCount)
                let y = yBase + amp * CGFloat(sin(Double(s) * freq + phase))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(color.opacity(0.30)), lineWidth: 0.55)
        }
    }
}

// MARK: - Grouped Scrap Usage

struct GroupedScrapUsage {
    let scrapId: UUID
    let scrapName: String
    let scrapWidth: Double
    let scrapHeight: Double
    let materialType: MaterialType
    let thickness: Double?
    let colorHex: String
    let usages: [ScrapUsage]
}

// MARK: - Multi Scrap Cut Diagram

/// Renders multiple cuts from the same scrap piece in one diagram
struct MultiScrapCutDiagramView: View {
    let usages: [ScrapUsage]
    let showOnScrap: Bool
    let materialWidth: Double
    let materialHeight: Double
    let scrapId: UUID
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var existingCuts: [ScrapCut] = []
    
    private var baseColor: Color { Color(hex: usages.first?.colorHex ?? "#E8D5A3") }
    private var preset: MaterialColorPreset? { MaterialColorPreset.preset(for: usages.first?.colorHex ?? "#E8D5A3") }
    
    // Theme-based cut fill color
    private var cutFillColor: Color {
        colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95)
    }
    
    // Color palette for different pieces
    private let palette: [Color] = [
        Color(red: 0.33, green: 0.62, blue: 0.80),  // steel blue
        Color(red: 0.95, green: 0.61, blue: 0.22),  // amber
        Color(red: 0.38, green: 0.73, blue: 0.49),  // sage green
        Color(red: 0.83, green: 0.37, blue: 0.37),  // coral
        Color(red: 0.63, green: 0.48, blue: 0.80),  // lavender
        Color(red: 0.90, green: 0.80, blue: 0.28),  // gold
    ]
    
    var body: some View {
        Canvas { context, size in
            if showOnScrap {
                drawOnScrap(context: context, size: size)
            } else {
                drawOnNewPiece(context: context, size: size)
            }
        }
        .task {
            // Load existing cuts from the scrap item when showing on scrap
            if showOnScrap {
                loadExistingCuts()
            }
        }
    }
    
    /// Draw pieces on the original scrap (showing existing cuts)
    private func drawOnScrap(context: GraphicsContext, size: CGSize) {
        let scaleX = size.width / materialWidth
        let scaleY = size.height / materialHeight
        let scale = min(scaleX, scaleY)
        
        let drawW = materialWidth * scale
        let drawH = materialHeight * scale
        let bgRect = CGRect(x: 0, y: 0, width: drawW, height: drawH)
        
        // 1. Background
        context.fill(Path(bgRect), with: .color(baseColor))
        
        // 2. Wood grain (if applicable)
        if let grainColor = preset?.grainColor {
            drawGrain(context: context, width: drawW, height: drawH, color: grainColor)
        }
        
        // 3. Fill old cut areas with theme color (material removed)
        for cut in existingCuts {
            let cutRect = CGRect(
                x: cut.x * scale,
                y: cut.y * scale,
                width: cut.width * scale,
                height: cut.height * scale
            )
            let cutPath = path(for: cut.shape, in: cutRect)
            
            // Fill with theme color to show material is gone
            context.fill(cutPath, with: .color(cutFillColor))
        }
        
        // 4. Border
        context.stroke(Path(bgRect), with: .color(.primary.opacity(0.8)), lineWidth: 2)
        
        // 5. Draw new pieces (the ones being cut now)
        for (index, usage) in usages.enumerated() {
            let pieceW = usage.rotated ? usage.pieceHeight : usage.pieceWidth
            let pieceH = usage.rotated ? usage.pieceWidth : usage.pieceHeight
            
            let pieceRect = CGRect(
                x: usage.cutX * scale,
                y: usage.cutY * scale,
                width: pieceW * scale,
                height: pieceH * scale
            )
            
            let piecePath = path(for: usage.pieceShape, in: pieceRect)
            let color = palette[index % palette.count]
            
            // Fill and stroke
            context.fill(piecePath, with: .color(color.opacity(0.78)))
            context.stroke(piecePath, with: .color(color), lineWidth: 2)
            
            // Label if large enough
            if pieceRect.width >= 24 && pieceRect.height >= 14 {
                let fontSize = min(pieceRect.height * 0.22, 11.0)
                let labelText = Text("\(index + 1). \(usage.pieceName)")
                    .font(.system(size: max(fontSize, 7), weight: .semibold))
                    .foregroundStyle(Color.primary)
                context.draw(labelText, in: pieceRect.insetBy(dx: 3, dy: 2))
            }
        }
    }
    
    /// Draw pieces repositioned on a new sheet (packed from origin)
    private func drawOnNewPiece(context: GraphicsContext, size: CGSize) {
        // Calculate bounding box of all pieces
        var totalWidth: Double = 0
        var totalHeight: Double = 0
        
        // Simple layout: stack pieces vertically with small gaps
        let gap: Double = 0.5
        var positions: [(x: Double, y: Double, width: Double, height: Double)] = []
        var currentY: Double = 0
        
        for usage in usages {
            let pieceW = usage.rotated ? usage.pieceHeight : usage.pieceWidth
            let pieceH = usage.rotated ? usage.pieceWidth : usage.pieceHeight
            
            positions.append((x: 0, y: currentY, width: pieceW, height: pieceH))
            totalWidth = max(totalWidth, pieceW)
            currentY += pieceH + gap
        }
        totalHeight = currentY - gap // Remove last gap
        
        // Scale to fit canvas
        let scaleX = size.width / totalWidth
        let scaleY = size.height / totalHeight
        let scale = min(scaleX, scaleY) * 0.9 // 90% to add padding
        
        let drawW = totalWidth * scale
        let drawH = totalHeight * scale
        
        // Center on canvas
        let offsetX = (size.width - drawW) / 2
        let offsetY = (size.height - drawH) / 2
        
        let bgRect = CGRect(x: offsetX, y: offsetY, width: drawW, height: drawH)
        
        // 1. Background
        context.fill(Path(bgRect), with: .color(baseColor))
        
        // 2. Wood grain (if applicable)
        if let grainColor = preset?.grainColor {
            var grainContext = context
            grainContext.translateBy(x: offsetX, y: offsetY)
            drawGrain(context: grainContext, width: drawW, height: drawH, color: grainColor)
        }
        
        // 3. Border
        context.stroke(Path(bgRect), with: .color(.primary.opacity(0.8)), lineWidth: 2)
        
        // 4. Draw pieces in their new positions
        for (index, position) in positions.enumerated() {
            let usage = usages[index]
            
            let pieceRect = CGRect(
                x: offsetX + position.x * scale,
                y: offsetY + position.y * scale,
                width: position.width * scale,
                height: position.height * scale
            )
            
            let piecePath = path(for: usage.pieceShape, in: pieceRect)
            let color = palette[index % palette.count]
            
            // Fill and stroke
            context.fill(piecePath, with: .color(color.opacity(0.78)))
            context.stroke(piecePath, with: .color(color), lineWidth: 2)
            
            // Label if large enough
            if pieceRect.width >= 24 && pieceRect.height >= 14 {
                let fontSize = min(pieceRect.height * 0.22, 11.0)
                let labelText = Text("\(index + 1). \(usage.pieceName)")
                    .font(.system(size: max(fontSize, 7), weight: .semibold))
                    .foregroundStyle(Color.primary)
                context.draw(labelText, in: pieceRect.insetBy(dx: 3, dy: 2))
            }
        }
    }
    
    private func loadExistingCuts() {
        let fetchDescriptor = FetchDescriptor<ScrapItem>(
            predicate: #Predicate { $0.id == scrapId }
        )
        
        if let scrapItem = try? modelContext.fetch(fetchDescriptor).first {
            existingCuts = scrapItem.cuts
        }
    }
    
    private func path(for shape: PieceShape, in rect: CGRect) -> Path {
        switch shape {
        case .rectangle:
            return Path(rect)
        case .triangle:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
            return path
        case .circle:
            return Path(ellipseIn: rect)
        case .semicircle:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.midX, y: rect.maxY),
                radius: rect.width / 2,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.closeSubpath()
            return path
        case .quarterCircle:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX, y: rect.maxY),
                radius: rect.width,
                startAngle: .degrees(0),
                endAngle: .degrees(-90),
                clockwise: true
            )
            path.closeSubpath()
            return path
        }
    }
    
    private func drawGrain(context: GraphicsContext, width: CGFloat, height: CGFloat, color: Color) {
        let spacing: CGFloat = 3.5
        let lineCount = Int(height / spacing) + 1
        let segmentCount = max(Int(width / 8), 10)
        
        for i in 0..<lineCount {
            let yBase = CGFloat(i) * spacing
            let amp = CGFloat(0.55 + 0.25 * sin(Double(i) * 0.41))
            let freq = 0.55 + 0.15 * sin(Double(i) * 0.17)
            let phase = Double(i) * 1.3
            
            var path = Path()
            path.move(to: CGPoint(x: 0, y: yBase))
            for s in 1...segmentCount {
                let x = width * CGFloat(s) / CGFloat(segmentCount)
                let y = yBase + amp * CGFloat(sin(Double(s) * freq + phase))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(color.opacity(0.30)), lineWidth: 0.55)
        }
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
        OptimizationResultView(cutPlan: plan, project: project, onPresented: nil)
    }
    .modelContainer(SampleData.previewContainer)
}
