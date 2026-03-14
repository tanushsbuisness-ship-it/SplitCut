import Foundation
import SwiftData

enum PieceShape: String, Codable, CaseIterable {
    case rectangle = "Rectangle"
    case triangle = "Triangle"
    case circle = "Circle"
    case semicircle = "Semicircle"
    case quarterCircle = "Quarter Circle"
}

@Model
final class RequiredPiece {
    var id: UUID = UUID()
    var name: String = ""
    var width: Double = 12       // inches
    var height: Double = 12      // inches
    var quantity: Int = 1
    var thickness: Double? = nil // inches, optional
    var materialType: MaterialType = MaterialType.sheet
    var colorHex: String = defaultMaterialColorHex
    var shapeRaw: String = PieceShape.rectangle.rawValue
    var rotationAllowed: Bool = true
    var grainDirectionLocked: Bool = false

    /// Back-reference to owning project (required for SwiftData relationship tracking)
    var project: Project?

    init(
        name: String = "",
        width: Double = 12,
        height: Double = 12,
        quantity: Int = 1,
        thickness: Double? = nil,
        materialType: MaterialType = .sheet,
        colorHex: String = defaultMaterialColorHex,
        shape: PieceShape = .rectangle,
        rotationAllowed: Bool = true,
        grainDirectionLocked: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.width = width
        self.height = height
        self.quantity = quantity
        self.thickness = thickness
        self.materialType = materialType
        self.colorHex = colorHex
        self.shapeRaw = shape.rawValue
        self.rotationAllowed = rotationAllowed
        self.grainDirectionLocked = grainDirectionLocked
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Unnamed Piece" : name
    }

    var materialSummary: String {
        materialSummaryText(materialType: materialType, thickness: thickness, colorHex: colorHex)
    }

    var shape: PieceShape {
        get { PieceShape(rawValue: shapeRaw) ?? .rectangle }
        set { shapeRaw = newValue.rawValue }
    }

    var shapeSummary: String {
        shapeDimensionText(shape: shape, width: width, height: height)
    }

    func matchesMaterial(type: MaterialType, thickness: Double?, colorHex: String) -> Bool {
        materialAttributesMatch(
            materialType: type,
            thickness: thickness,
            colorHex: colorHex,
            requiredType: materialType,
            requiredThickness: self.thickness,
            requiredColorHex: self.colorHex
        )
    }
}
