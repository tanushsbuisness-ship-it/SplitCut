import SwiftUI
import SwiftData
internal import os

struct SavedPlansView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPlan.createdAt, order: .reverse) private var savedPlans: [SavedPlan]
    
    @State private var selectedPlan: SavedPlan? = nil
    @State private var planToDelete: SavedPlan? = nil
    @State private var showingDeleteAlert = false
    @State private var searchText = ""
    
    private var filteredPlans: [SavedPlan] {
        guard !searchText.isEmpty else { return savedPlans }
        return savedPlans.filter {
            $0.projectName.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if savedPlans.isEmpty {
                    emptyState
                } else {
                    plansList
                }
            }
            .navigationTitle("Saved Plans")
            .searchable(text: $searchText, prompt: "Search plans")
            .sheet(item: $selectedPlan) { plan in
                if let cutPlan = plan.cutPlan {
                    SavedPlanDetailView(
                        savedPlan: plan,
                        cutPlan: cutPlan
                    )
                } else {
                    Text("Unable to load plan")
                }
            }
            .alert("Delete Plan?", isPresented: $showingDeleteAlert, presenting: planToDelete) { plan in
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deletePlan(plan)
                }
            } message: { plan in
                Text("Are you sure you want to delete the plan for '\(plan.projectName)'?")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var plansList: some View {
        List {
            ForEach(filteredPlans) { plan in
                Button {
                    selectedPlan = plan
                } label: {
                    SavedPlanRow(plan: plan)
                }
                .tint(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        planToDelete = plan
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Saved Plans", systemImage: "bookmark.slash")
        } description: {
            Text("Cut plans you save will appear here for quick reference.")
        }
    }
    
    // MARK: - Actions
    
    private func deletePlan(_ plan: SavedPlan) {
        modelContext.delete(plan)
        try? modelContext.save()
    }
}

// MARK: - Saved Plan Row

struct SavedPlanRow: View {
    let plan: SavedPlan
    
    private var planSummary: String {
        guard let cutPlan = plan.cutPlan else { return "Unable to load" }
        var parts: [String] = []
        
        if cutPlan.sheetsUsed > 0 {
            parts.append("\(cutPlan.sheetsUsed) sheet\(cutPlan.sheetsUsed == 1 ? "" : "s")")
        }
        if cutPlan.totalScrapPieces > 0 {
            parts.append("\(cutPlan.totalScrapPieces) from scrap")
        }
        if cutPlan.unplacedPieces.count > 0 {
            parts.append("\(cutPlan.unplacedPieces.count) unplaced")
        }
        
        return parts.isEmpty ? "Empty plan" : parts.joined(separator: " · ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.projectName)
                .font(.headline)
            
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text(plan.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            
            Text(planSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if !plan.notes.isEmpty {
                Text(plan.notes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Saved Plan Detail View

private struct ExportedPDF: Identifiable {
    let id = UUID()
    let url: URL
}

struct SavedPlanDetailView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let savedPlan: SavedPlan
    let cutPlan: CutPlan
    
    @State private var editingNotes = false
    @State private var notesText = ""
    @State private var shareURL: ExportedPDF?
    @State private var isExporting = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(savedPlan.projectName)
                            .font(.title2.bold())
                        
                        HStack {
                            Image(systemName: "calendar")
                                .font(.caption)
                            Text(savedPlan.createdAt.formatted(date: .long, time: .shortened))
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                        
                        // Notes section
                        if editingNotes {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                TextField("Add notes...", text: $notesText, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(3...6)
                                
                                HStack {
                                    Button("Cancel") {
                                        notesText = savedPlan.notes
                                        editingNotes = false
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button("Save") {
                                        savedPlan.notes = notesText
                                        try? modelContext.save()
                                        editingNotes = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        } else {
                            Button {
                                notesText = savedPlan.notes
                                editingNotes = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Notes")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                        if savedPlan.notes.isEmpty {
                                            Text("Tap to add notes...")
                                                .font(.subheadline)
                                                .foregroundStyle(.tertiary)
                                        } else {
                                            Text(savedPlan.notes)
                                                .font(.subheadline)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Use the existing OptimizationResultView but in read-only mode
                    OptimizationResultContent(
                        cutPlan: cutPlan,
                        projectName: savedPlan.projectName,
                        isReadOnly: true
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            exportToPDF()
                        } label: {
                            Label("Export PDF", systemImage: "doc.fill")
                        }
                        
                        ShareLink(
                            item: cutPlan.cutInstructions.joined(separator: "\n"),
                            subject: Text("Cut Plan: \(savedPlan.projectName)")
                        ) {
                            Label("Share Instructions", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $shareURL) { exportedPDF in
                ActivityView(items: [exportedPDF.url])
            }
        }
    }
    
    private func exportToPDF() {
        isExporting = true
        Task {
            do {
                let pdfURL = try CutPlanPDFExporter.export(
                    cutPlan: cutPlan,
                    projectName: savedPlan.projectName,
                    mode: .singlePageA4
                )
                await MainActor.run {
                    shareURL = ExportedPDF(url: pdfURL)
                    isExporting = false
                }
                AppLogger.export.info("PDF export succeeded for plan: \(savedPlan.projectName)")
            } catch {
                await MainActor.run {
                    isExporting = false
                }
                AppLogger.export.error("PDF export failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Optimization Result Content (Reusable)

struct OptimizationResultContent: View {
    let cutPlan: CutPlan
    let projectName: String
    let isReadOnly: Bool
    
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 12
            ) {
                SummaryCard(
                    title: "Sheets",
                    value: "\(cutPlan.sheetsUsed)",
                    icon: "square.stack.3d.up"
                )
                SummaryCard(
                    title: "From Scrap",
                    value: "\(cutPlan.totalScrapPieces)",
                    icon: "tray.full"
                )
                SummaryCard(
                    title: "Waste",
                    value: String(format: "%.1f%%", cutPlan.overallWastePercentage),
                    icon: "chart.pie"
                )
            }
            .padding(.horizontal)
            
            if !cutPlan.unplacedPieces.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(cutPlan.unplacedPieces.count) piece(s) could not be placed")
                        .font(.subheadline)
                    Spacer()
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
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
        }
    }
    
    private var diagramsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !cutPlan.scrapUsages.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("From Scrap Bin")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    let grouped = Dictionary(grouping: cutPlan.scrapUsages, by: { $0.scrapId })
                    ForEach(Array(grouped.keys.sorted()), id: \.self) { scrapId in
                        if let usages = grouped[scrapId], let first = usages.first {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Color(hex: first.colorHex))
                                        .frame(width: 14, height: 14)
                                    Text("\(usages.count) piece(s) from \(first.scrapName)")
                                        .font(.subheadline.weight(.medium))
                                }
                                .padding(.horizontal)
                                
                                MultiScrapCutDiagramView(
                                    usages: usages,
                                    showOnScrap: true,
                                    materialWidth: first.scrapWidth,
                                    materialHeight: first.scrapHeight,
                                    scrapId: scrapId
                                )
                                .aspectRatio(first.scrapWidth / first.scrapHeight, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.separator), lineWidth: 1)
                                )
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        }
                    }
                }
            }
            
            if !cutPlan.sheetLayouts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("New Sheets")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(cutPlan.sheetLayouts) { layout in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: layout.materialColorHex))
                                    .frame(width: 14, height: 14)
                                Text("Sheet \(layout.sheetIndex + 1) — \(layout.materialName)")
                                    .font(.headline)
                                Spacer()
                                Text(String(format: "%.1f%% waste", layout.wastePercentage))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            
                            CutDiagramView(layout: layout)
                                .aspectRatio(layout.sheetWidth / layout.sheetHeight, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.separator), lineWidth: 1)
                                )
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding(.top, 16)
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(cutPlan.cutInstructions.enumerated()), id: \.offset) { _, instruction in
                Text(instruction)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    SavedPlansView()
        .modelContainer(SampleData.previewContainer)
}
