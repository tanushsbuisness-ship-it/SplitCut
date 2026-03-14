import SwiftUI
import SwiftData

/// Add or edit a single item in the Scrap Bin.
struct ScrapItemEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let existing: ScrapItem?

    @State private var name: String       = ""
    @State private var width: Double      = 24
    @State private var height: Double     = 48
    @State private var thickness: Double  = 0.75
    @State private var hasThickness: Bool = false
    @State private var materialType: MaterialType = .sheet
    @State private var notes: String      = ""
    @State private var colorHex: String   = MaterialColorPreset.defaultHex

    @State private var showingAR = false

    init(item: ScrapItem? = nil) {
        self.existing = item
        if let s = item {
            _name         = State(wrappedValue: s.name)
            _width        = State(wrappedValue: s.width)
            _height       = State(wrappedValue: s.height)
            _materialType = State(wrappedValue: s.materialType)
            _notes        = State(wrappedValue: s.notes)
            _hasThickness = State(wrappedValue: s.thickness != nil)
            _thickness    = State(wrappedValue: s.thickness ?? 0.75)
            _colorHex     = State(wrappedValue: s.colorHex)
        }
    }

    private var isValid: Bool { width > 0 && height > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scrap Info") {
                    TextField("Name (e.g. Leftover Oak Strip)", text: $name)
                    Picker("Type", selection: $materialType) {
                        ForEach(MaterialType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }

                // AR measuring button
                Section {
                    Button {
                        showingAR = true
                    } label: {
                        Label("Measure with AR Camera", systemImage: "arkit")
                    }
                } footer: {
                    Text("Point your camera at the piece and tap two points to measure each dimension.")
                }

                Section("Appearance") {
                    MaterialColorPicker(colorHex: $colorHex)
                }

                Section("Dimensions (inches)") {
                    dimField("Width",    value: $width,  placeholder: "24")
                    dimField("Length",   value: $height, placeholder: "48")
                }

                Section("Thickness (optional)") {
                    Toggle("Specify Thickness", isOn: $hasThickness)
                    if hasThickness {
                        dimField("Thickness", value: $thickness, placeholder: "0.75")
                    }
                }

                Section("Notes") {
                    TextField("e.g. from cabinet project, minor warp on one end",
                              text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle(existing == nil ? "Add Scrap" : "Edit Scrap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
            .fullScreenCover(isPresented: $showingAR) {
                ARMeasureSheet { measuredWidth, measuredLength in
                    width  = measuredWidth
                    height = measuredLength
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func dimField(_ label: String, value: Binding<Double>, placeholder: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(placeholder, value: value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                Text("\"").foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        if let s = existing {
            s.name         = name
            s.width        = width
            s.height       = height
            s.materialType = materialType
            s.notes        = notes
            s.thickness    = hasThickness ? thickness : nil
            s.colorHex     = colorHex
            FirebaseSyncService.shared.syncScrap(s)
        } else {
            let item = ScrapItem(
                name: name, width: width, height: height,
                thickness: hasThickness ? thickness : nil,
                materialType: materialType, notes: notes,
                colorHex: colorHex
            )
            modelContext.insert(item)
            FirebaseSyncService.shared.syncScrap(item)
            dismiss()
            return
        }
        dismiss()
    }
}

#Preview {
    ScrapItemEditorView()
        .modelContainer(SampleData.previewContainer)
}
