import SwiftUI
import SwiftData

// MARK: - Scrap Bin (main tab)

struct ScrapBinView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScrapItem.addedAt, order: .reverse) private var items: [ScrapItem]

    @State private var showingAdd      = false
    @State private var editingItem: ScrapItem? = nil
    @State private var previewItem: ScrapItem? = nil
    @State private var searchText     = ""

    private var filtered: [ScrapItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    scrapList
                }
            }
            .navigationTitle("Scrap Bin")
            .searchable(text: $searchText, prompt: "Search scrap")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                ScrapItemEditorView()
            }
            .sheet(item: $editingItem) { item in
                ScrapItemEditorView(item: item)
            }
            .sheet(item: $previewItem) { item in
                ScrapPreviewSheet(item: item, onEdit: {
                    previewItem = nil
                    editingItem = item
                })
            }
        }
    }

    // MARK: - Subviews

    private var scrapList: some View {
        List {
            ForEach(filtered) { item in
                Button { previewItem = item } label: {
                    ScrapRowView(item: item)
                }
                .tint(.primary)
            }
            .onDelete(perform: deleteItems)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Scrap Yet", systemImage: "tray")
        } description: {
            Text("Add leftover pieces here so you can reuse them in future projects.")
        } actions: {
            Button {
                showingAdd = true
            } label: {
                Label("Add Scrap Piece", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Actions

    private func deleteItems(at offsets: IndexSet) {
        for idx in offsets {
            FirebaseSyncService.shared.deleteScrap(id: filtered[idx].id)
            modelContext.delete(filtered[idx])
        }
    }
}

// MARK: - Row

struct ScrapRowView: View {
    let item: ScrapItem

    var body: some View {
        HStack(spacing: 12) {
            // Visual preview of scrap piece
            ScrapPiecePreview(item: item)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                .id("\(item.id)-\(item.cuts.count)")  // Force redraw when cuts change
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.displayName).font(.body)
                    Spacer()
                    Text(item.materialType.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                HStack(spacing: 6) {
                    Text("\(dimStr(item.width)) × \(dimStr(item.height))")
                    if let t = item.thickness {
                        Text("·")
                        Text("\(dimStr(t)) thick")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Scrap Piece Preview

/// Small visual representation of a scrap piece
struct ScrapPiecePreview: View {
    let item: ScrapItem
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var baseColor: Color { Color(hex: item.colorHex) }
    private var preset: MaterialColorPreset? { MaterialColorPreset.preset(for: item.colorHex) }
    
    // Theme-based cut fill color
    private var cutFillColor: Color {
        colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95)
    }
    
    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / item.width
            let scaleY = size.height / item.height
            let scale = min(scaleX, scaleY)
            
            let drawW = item.width * scale
            let drawH = item.height * scale
            let rect = CGRect(x: 0, y: 0, width: drawW, height: drawH)
            
            // 1. Background
            context.fill(Path(rect), with: .color(baseColor))
            
            // 2. Wood grain (if applicable)
            if let grainColor = preset?.grainColor {
                drawGrain(context: context, width: drawW, height: drawH, color: grainColor)
            }
            
            // 3. Fill cut areas with theme color (material removed)
            for cut in item.cuts {
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
            context.stroke(Path(rect), with: .color(.primary.opacity(0.5)), lineWidth: 1)
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
        let spacing: CGFloat = 2.5
        let lineCount = Int(height / spacing) + 1
        let segmentCount = max(Int(width / 6), 6)
        
        for i in 0..<lineCount {
            let yBase = CGFloat(i) * spacing
            let amp = CGFloat(0.4 + 0.2 * sin(Double(i) * 0.41))
            let freq = 0.55 + 0.15 * sin(Double(i) * 0.17)
            let phase = Double(i) * 1.3
            
            var path = Path()
            path.move(to: CGPoint(x: 0, y: yBase))
            for s in 1...segmentCount {
                let x = width * CGFloat(s) / CGFloat(segmentCount)
                let y = yBase + amp * CGFloat(sin(Double(s) * freq + phase))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(color.opacity(0.25)), lineWidth: 0.4)
        }
    }
}

// MARK: - Picker sheet (used from MaterialEditorView)

struct ScrapPickerSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ScrapItem.addedAt, order: .reverse) private var items: [ScrapItem]

    let onSelected: (ScrapItem) -> Void

    @State private var searchText = ""

    private var filtered: [ScrapItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Scrap Bin is Empty",
                        systemImage: "tray",
                        description: Text("Add pieces to the Scrap Bin tab first.")
                    )
                } else {
                    List(filtered) { item in
                        Button {
                            onSelected(item)
                            dismiss()
                        } label: {
                            ScrapRowView(item: item)
                        }
                        .tint(.primary)
                    }
                    .searchable(text: $searchText, prompt: "Search")
                }
            }
            .navigationTitle("Pick from Scrap Bin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Scrap Preview Sheet

struct ScrapPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ScrapItem
    let onEdit: () -> Void
    
    private var baseColor: Color { Color(hex: item.colorHex) }
    private var preset: MaterialColorPreset? { MaterialColorPreset.preset(for: item.colorHex) }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Large preview
                    ScrapPiecePreview(item: item)
                        .aspectRatio(item.width / item.height, contentMode: .fit)
                        .frame(maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 10)
                        .padding()
                        .id("\(item.id)-\(item.cuts.count)")  // Force redraw when cuts change
                    
                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        DetailRow(label: "Dimensions", value: "\(dimStr(item.width)) × \(dimStr(item.height))")
                        
                        if let thickness = item.thickness {
                            DetailRow(label: "Thickness", value: dimStr(thickness))
                        }
                        
                        DetailRow(label: "Material Type", value: item.materialType.rawValue)
                        
                        if let preset = preset {
                            DetailRow(label: "Color", value: preset.name)
                        }
                        
                        if !item.cuts.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Cut History")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                ForEach(item.cuts) { cut in
                                    HStack {
                                        Image(systemName: "scissors")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                        Text(cut.pieceName)
                                            .font(.caption)
                                        Spacer()
                                        Text("\(dimStr(cut.width)) × \(dimStr(cut.height))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.tertiarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        } else {
                            Text("No cuts yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if !item.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.notes)
                                    .font(.body)
                            }
                        }
                        
                        DetailRow(label: "Added", value: item.addedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        onEdit()
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body)
        }
    }
}

#Preview("Scrap Bin") {
    ScrapBinView()
        .modelContainer(SampleData.previewContainer)
}
