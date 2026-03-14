import SwiftUI
import SwiftData

struct MaterialEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let project: Project
    private let existing: MaterialItem?

    @State private var name: String       = ""
    @State private var width: Double      = 48
    @State private var height: Double     = 96
    @State private var quantity: Int      = 1
    @State private var thickness: Double  = 0.75
    @State private var hasThickness: Bool = true
    @State private var materialType: MaterialType = .sheet

    @State private var colorHex: String   = MaterialColorPreset.defaultHex
    @State private var showingAR         = false
    @State private var showingScrapPicker = false
    @State private var selectedPresetID = ""

    init(material: MaterialItem? = nil, project: Project) {
        self.existing = material
        self.project  = project
        if let m = material {
            _name         = State(wrappedValue: m.name)
            _width        = State(wrappedValue: m.width)
            _height       = State(wrappedValue: m.height)
            _quantity     = State(wrappedValue: m.quantity)
            _materialType = State(wrappedValue: m.materialType)
            _hasThickness = State(wrappedValue: m.thickness != nil)
            _thickness    = State(wrappedValue: m.thickness ?? 0.75)
            _colorHex     = State(wrappedValue: m.colorHex)
        }
    }

    private var isValid: Bool { width > 0 && height > 0 && quantity > 0 }

    var body: some View {
        NavigationStack {
            Form {
                // Quick-fill sources
                Section {
                    Button {
                        showingAR = true
                    } label: {
                        Label("Measure with AR Camera", systemImage: "arkit")
                    }

                    Button {
                        showingScrapPicker = true
                    } label: {
                        Label("Pick from Scrap Bin", systemImage: "tray")
                    }
                } header: {
                    Text("Quick Fill")
                } footer: {
                    Text("Measure a physical board with AR, reuse a saved scrap piece, or start from a common stock size.")
                }

                Section("Material Info") {
                    TextField("Name (e.g. 3/4\" Birch Ply)", text: $name)
                    Picker("Type", selection: $materialType) {
                        ForEach(MaterialType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .onChange(of: materialType) { _, newType in
                        if let selectedPreset = MaterialPreset.common.first(where: { $0.id == selectedPresetID }),
                           selectedPreset.materialType != newType {
                            selectedPresetID = ""
                        }
                    }
                    Picker("Common Size", selection: $selectedPresetID) {
                        Text("Custom").tag("")
                        ForEach(MaterialPreset.common.filter { $0.materialType == materialType }) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .onChange(of: selectedPresetID) { _, newValue in
                        guard let preset = MaterialPreset.common.first(where: { $0.id == newValue }) else { return }
                        width = preset.width
                        height = preset.height
                        materialType = preset.materialType
                        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            name = preset.name
                        }
                    }
                }

                Section("Dimensions (inches)") {
                    dimensionField("Width",           value: $width,    placeholder: "48")
                    dimensionField("Height / Length", value: $height,   placeholder: "96")
                    LabeledContent("Quantity") {
                        TextField("1", value: $quantity, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }

                Section("Appearance") {
                    MaterialColorPicker(colorHex: $colorHex)
                }

                Section("Thickness (optional)") {
                    Toggle("Specify Thickness", isOn: $hasThickness)
                    if hasThickness {
                        dimensionField("Thickness", value: $thickness, placeholder: "0.75")
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Material" : "Edit Material")
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
            // AR measuring — full-screen so camera gets maximum space
            .fullScreenCover(isPresented: $showingAR) {
                ARMeasureSheet { measuredWidth, measuredLength in
                    width  = measuredWidth
                    height = measuredLength
                }
            }
            // Scrap picker sheet
            .sheet(isPresented: $showingScrapPicker) {
                ScrapPickerSheet { scrap in
                    name         = scrap.displayName
                    width        = scrap.width
                    height       = scrap.height
                    materialType = scrap.materialType
                    colorHex     = scrap.colorHex
                    if let t = scrap.thickness {
                        thickness    = t
                        hasThickness = true
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func dimensionField(_ label: String, value: Binding<Double>, placeholder: String) -> some View {
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
        if let mat = existing {
            mat.name         = name
            mat.width        = width
            mat.height       = height
            mat.quantity     = quantity
            mat.materialType = materialType
            mat.thickness    = hasThickness ? thickness : nil
            mat.colorHex     = colorHex
        } else {
            let mat = MaterialItem(
                name: name, width: width, height: height,
                quantity: quantity,
                thickness: hasThickness ? thickness : nil,
                materialType: materialType,
                colorHex: colorHex
            )
            modelContext.insert(mat)
            project.materials.append(mat)
        }
        project.updatedAt = Date()
        FirebaseSyncService.shared.syncProject(project)
        dismiss()
    }
}

#Preview {
    MaterialEditorView(project: SampleData.sampleProject)
        .modelContainer(SampleData.previewContainer)
}
