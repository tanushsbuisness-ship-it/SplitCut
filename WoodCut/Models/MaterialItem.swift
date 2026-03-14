import Foundation
import SwiftData

enum MaterialType: String, Codable, CaseIterable {
    case sheet = "Sheet"
    case board = "Board"
    case fabric = "Fabric"
}

struct MaterialPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let width: Double
    let height: Double
    let materialType: MaterialType
}

extension MaterialPreset {
    static let common: [MaterialPreset] = [
        .init(id: "sheet-4x8", name: "Plywood 4 × 8", width: 48, height: 96, materialType: .sheet),
        .init(id: "sheet-5x5", name: "Baltic Birch 5 × 5", width: 60, height: 60, materialType: .sheet),
        .init(id: "sheet-4x10", name: "Sheet 4 × 10", width: 48, height: 120, materialType: .sheet),
        .init(id: "sheet-49x97", name: "MDF 49 × 97", width: 49, height: 97, materialType: .sheet),
        .init(id: "board-1x4x8", name: "Board 1 × 4 × 8", width: 3.5, height: 96, materialType: .board),
        .init(id: "board-1x6x8", name: "Board 1 × 6 × 8", width: 5.5, height: 96, materialType: .board),
        .init(id: "board-2x4x8", name: "Board 2 × 4 × 8", width: 3.5, height: 96, materialType: .board),
        .init(id: "fabric-yard", name: "Fabric Yard", width: 36, height: 58, materialType: .fabric),
        .init(id: "fabric-bolt", name: "Fabric Bolt", width: 54, height: 360, materialType: .fabric),
        .init(id: "fabric-wide-bolt", name: "Wide Fabric Bolt", width: 60, height: 360, materialType: .fabric),
    ]
}

let defaultMaterialColorHex = "#E8D5A3"
private let materialThicknessTolerance = 0.001

func normalizedMaterialColorHex(_ hex: String) -> String {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? defaultMaterialColorHex : trimmed.uppercased()
}

func materialThicknessMatches(_ lhs: Double?, _ rhs: Double?) -> Bool {
    switch (lhs, rhs) {
    case let (left?, right?):
        return abs(left - right) <= materialThicknessTolerance
    case (nil, nil):
        return true
    default:
        return false
    }
}

func materialAttributesMatch(
    materialType: MaterialType,
    thickness: Double?,
    colorHex: String,
    requiredType: MaterialType,
    requiredThickness: Double?,
    requiredColorHex: String
) -> Bool {
    materialType == requiredType &&
    materialThicknessMatches(thickness, requiredThickness) &&
    normalizedMaterialColorHex(colorHex) == normalizedMaterialColorHex(requiredColorHex)
}

func materialSummaryText(materialType: MaterialType, thickness: Double?, colorHex: String) -> String {
    var parts = [materialType.rawValue]
    if let thickness {
        parts.append("\(dimStr(thickness)) thick")
    }
    parts.append(normalizedMaterialColorHex(colorHex))
    return parts.joined(separator: " · ")
}

@Model
final class MaterialItem {
    var id: UUID = UUID()
    var name: String = ""
    var width: Double = 48       // inches
    var height: Double = 96      // inches (length for boards)
    var quantity: Int = 1
    var thickness: Double? = nil // inches, optional
    var materialType: MaterialType = MaterialType.sheet
    /// Hex color string used for diagram rendering (e.g. "#E8D5A3" for birch).
    var colorHex: String = defaultMaterialColorHex

    /// Back-reference to owning project (required for SwiftData relationship tracking)
    var project: Project?

    init(
        name: String = "",
        width: Double = 48,
        height: Double = 96,
        quantity: Int = 1,
        thickness: Double? = nil,
        materialType: MaterialType = .sheet,
        colorHex: String = defaultMaterialColorHex
    ) {
        self.id = UUID()
        self.name = name
        self.width = width
        self.height = height
        self.quantity = quantity
        self.thickness = thickness
        self.materialType = materialType
        self.colorHex = colorHex
    }

    /// Display label: custom name if set, else type name
    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? materialType.rawValue : name
    }

    var materialSummary: String {
        materialSummaryText(materialType: materialType, thickness: thickness, colorHex: colorHex)
    }
}
