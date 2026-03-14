import SwiftUI
import SwiftData

// MARK: - Scrap Bin (main tab)

struct ScrapBinView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScrapItem.addedAt, order: .reverse) private var items: [ScrapItem]

    @State private var showingAdd      = false
    @State private var editingItem: ScrapItem? = nil
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
        }
    }

    // MARK: - Subviews

    private var scrapList: some View {
        List {
            ForEach(filtered) { item in
                Button { editingItem = item } label: {
                    ScrapRowView(item: item)
                }
                .tint(.primary)
            }
            .onDelete(perform: deleteItems)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Scrap Yet",
            systemImage: "tray",
            description: Text("Add leftover pieces here so you can reuse them in future projects.\nTap + or measure a piece with AR.")
        )
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
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                // Color swatch
                ZStack {
                    Circle()
                        .fill(Color(hex: item.colorHex))
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.12), radius: 1.5)
                    if let preset = MaterialColorPreset.preset(for: item.colorHex),
                       let gc = preset.grainColor {
                        GrainIndicatorView(color: gc)
                            .frame(width: 14, height: 14)
                            .clipShape(Circle())
                    }
                }
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
        .padding(.vertical, 2)
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

#Preview("Scrap Bin") {
    ScrapBinView()
        .modelContainer(SampleData.previewContainer)
}
