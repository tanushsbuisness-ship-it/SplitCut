import SwiftUI
import SwiftData

struct PieceEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let project: Project
    private let existing: RequiredPiece?

    @State private var name: String = ""
    @State private var width: Double = 12
    @State private var height: Double = 12
    @State private var quantity: Int = 1
    @State private var thickness: Double = 0.75
    @State private var hasThickness: Bool = false
    @State private var materialType: MaterialType = .sheet
    @State private var colorHex: String = defaultMaterialColorHex
    @State private var shape: PieceShape = .rectangle
    @State private var rotationAllowed: Bool = true
    @State private var grainDirectionLocked: Bool = false

    init(piece: RequiredPiece? = nil, project: Project) {
        self.existing = piece
        self.project  = project
        if let p = piece {
            _name               = State(wrappedValue: p.name)
            _width              = State(wrappedValue: p.width)
            _height             = State(wrappedValue: p.height)
            _quantity           = State(wrappedValue: p.quantity)
            _hasThickness       = State(wrappedValue: p.thickness != nil)
            _thickness          = State(wrappedValue: p.thickness ?? 0.75)
            _materialType       = State(wrappedValue: p.materialType)
            _colorHex           = State(wrappedValue: p.colorHex)
            _shape              = State(wrappedValue: p.shape)
            _rotationAllowed    = State(wrappedValue: p.rotationAllowed)
            _grainDirectionLocked = State(wrappedValue: p.grainDirectionLocked)
        } else if let material = project.materials.first {
            _hasThickness = State(wrappedValue: material.thickness != nil)
            _thickness = State(wrappedValue: material.thickness ?? 0.75)
            _materialType = State(wrappedValue: material.materialType)
            _colorHex = State(wrappedValue: material.colorHex)
        }
    }

    private var isValid: Bool { width > 0 && height > 0 && quantity > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Piece Info") {
                    TextField("Name (e.g. Side Panel)", text: $name)
                }

                Section("Dimensions (inches)") {
                    Picker("Shape", selection: $shape) {
                        ForEach(PieceShape.allCases, id: \.self) { shape in
                            Text(shape.rawValue).tag(shape)
                        }
                    }
                    dimensionField("Width",    value: $width,    placeholder: "12")
                    if shapeRequiresHeight {
                        dimensionField(heightFieldLabel, value: $height, placeholder: "12")
                    }
                    LabeledContent("Quantity") {
                        TextField("1", value: $quantity, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Picker("Type", selection: $materialType) {
                        ForEach(MaterialType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    MaterialColorPicker(colorHex: $colorHex)
                    Toggle("Specify Thickness", isOn: $hasThickness)
                    if hasThickness {
                        dimensionField("Thickness", value: $thickness, placeholder: "0.75")
                    }
                } header: {
                    Text("Material Match")
                } footer: {
                    Text("Scrap reuse and material placement match this type, thickness, and color. Curved shapes are packed using their bounding rectangle.")
                }

                Section("Cutting Options") {
                    Toggle("Rotation Allowed", isOn: $rotationAllowed)
                    Toggle("Lock Grain Direction", isOn: $grainDirectionLocked)
                        .onChange(of: grainDirectionLocked) { _, locked in
                            // Locking grain implies rotation is not freely allowed
                            if locked { rotationAllowed = false }
                        }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Width × Height are in inches.", systemImage: "ruler")
                        Label("Enable Rotation Allowed if the piece can be cut in either orientation.", systemImage: "rotate.right")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existing == nil ? "Add Piece" : "Edit Piece")
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
        let storedHeight = normalizedHeight
        if let p = existing {
            p.name               = name
            p.width              = width
            p.height             = storedHeight
            p.quantity           = quantity
            p.thickness          = hasThickness ? thickness : nil
            p.materialType       = materialType
            p.colorHex           = colorHex
            p.shape              = shape
            p.rotationAllowed    = rotationAllowed
            p.grainDirectionLocked = grainDirectionLocked
        } else {
            let piece = RequiredPiece(
                name: name, width: width, height: storedHeight, quantity: quantity,
                thickness: hasThickness ? thickness : nil,
                materialType: materialType,
                colorHex: colorHex,
                shape: shape,
                rotationAllowed: rotationAllowed,
                grainDirectionLocked: grainDirectionLocked
            )
            modelContext.insert(piece)
            project.pieces.append(piece)
        }
        project.updatedAt = Date()
        FirebaseSyncService.shared.syncProject(project)
        dismiss()
    }

    private var shapeRequiresHeight: Bool {
        switch shape {
        case .rectangle, .triangle:
            return true
        case .circle, .semicircle, .quarterCircle:
            return false
        }
    }

    private var heightFieldLabel: String {
        switch shape {
        case .rectangle:
            return "Height"
        case .triangle:
            return "Height"
        case .circle:
            return "Diameter"
        case .semicircle:
            return "Diameter"
        case .quarterCircle:
            return "Radius"
        }
    }

    private var normalizedHeight: Double {
        switch shape {
        case .rectangle, .triangle:
            return height
        case .circle:
            return width
        case .semicircle:
            return width / 2
        case .quarterCircle:
            return width
        }
    }
}

#Preview {
    PieceEditorView(project: SampleData.sampleProject)
        .modelContainer(SampleData.previewContainer)
}
