import Foundation
import SwiftData

/// A leftover piece of material stored in the Scrap Bin for reuse in future projects.
@Model
final class ScrapItem {
    var id: UUID = UUID()
    var name: String = ""
    var width: Double = 24       // inches
    var height: Double = 48      // inches (length for boards)
    var thickness: Double? = nil // inches, optional
    var materialType: MaterialType = MaterialType.sheet
    var notes: String = ""
    var addedAt: Date = Date()
    /// Hex color string for diagram rendering, carried from the source material.
    var colorHex: String = defaultMaterialColorHex

    init(
        name: String = "",
        width: Double = 24,
        height: Double = 48,
        thickness: Double? = nil,
        materialType: MaterialType = .sheet,
        notes: String = "",
        colorHex: String = "#E8D5A3"    // birch default
    ) {
        self.id = UUID()
        self.name = name
        self.width = width
        self.height = height
        self.thickness = thickness
        self.materialType = materialType
        self.notes = notes
        self.addedAt = Date()
        self.colorHex = colorHex
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? materialType.rawValue : name
    }

    /// Convert this scrap item into a MaterialItem for use in a project.
    func toMaterialItem(quantity: Int = 1) -> MaterialItem {
        MaterialItem(
            name: displayName,
            width: width,
            height: height,
            quantity: quantity,
            thickness: thickness,
            materialType: materialType,
            colorHex: colorHex
        )
    }
}
