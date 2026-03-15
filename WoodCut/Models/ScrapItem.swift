import Foundation
import SwiftData

/// Represents a cut that has been made from a scrap piece
struct ScrapCut: Codable, Identifiable {
    let id: UUID
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let shape: PieceShape
    let pieceName: String
    let cutDate: Date
    
    init(id: UUID = UUID(), x: Double, y: Double, width: Double, height: Double, shape: PieceShape, pieceName: String, cutDate: Date = Date()) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.shape = shape
        self.pieceName = pieceName
        self.cutDate = cutDate
    }
}

/// Represents a free (usable) rectangle on a scrap piece
struct ScrapFreeRect: Codable, Identifiable {
    let id: UUID
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    
    var area: Double { width * height }
    
    init(id: UUID = UUID(), x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

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
    
    /// Internal storage for cuts as Data
    @Attribute(.externalStorage) private var cutsData: Data = Data()
    
    /// Internal storage for free rectangles as Data
    @Attribute(.externalStorage) private var freeRectsData: Data = Data()
    
    /// History of cuts made from this scrap piece
    var cuts: [ScrapCut] {
        get {
            guard !cutsData.isEmpty else {
                print("⚙️ ScrapItem.cuts getter: cutsData is empty")
                return []
            }
            do {
                let decoded = try JSONDecoder().decode([ScrapCut].self, from: cutsData)
                print("⚙️ ScrapItem.cuts getter: Successfully decoded \(decoded.count) cuts from \(cutsData.count) bytes")
                return decoded
            } catch {
                print("❌ ScrapItem.cuts getter: Failed to decode cuts: \(error)")
                print("   Data size: \(cutsData.count) bytes")
                if let dataString = String(data: cutsData, encoding: .utf8) {
                    print("   Data content (first 200 chars): \(String(dataString.prefix(200)))")
                }
                return []
            }
        }
        set {
            do {
                let encoded = try JSONEncoder().encode(newValue)
                cutsData = encoded
                print("✅ ScrapItem.cuts setter: Encoded \(newValue.count) cuts to \(encoded.count) bytes")
            } catch {
                print("❌ ScrapItem.cuts setter: Failed to encode cuts: \(error)")
                cutsData = Data()
            }
        }
    }
    
    /// Remaining free (usable) rectangles on this scrap piece
    /// If empty and no cuts exist, the entire scrap is available
    var freeRects: [ScrapFreeRect] {
        get {
            guard !freeRectsData.isEmpty else {
                // If no free rects defined but also no cuts, return the full scrap as one free rect
                if cuts.isEmpty {
                    print("⚙️ ScrapItem.freeRects getter: No data, no cuts → returning full scrap")
                    return [ScrapFreeRect(x: 0, y: 0, width: width, height: height)]
                }
                print("⚙️ ScrapItem.freeRects getter: No data but has cuts → returning empty")
                return []
            }
            do {
                let decoded = try JSONDecoder().decode([ScrapFreeRect].self, from: freeRectsData)
                print("⚙️ ScrapItem.freeRects getter: Successfully decoded \(decoded.count) free rects from \(freeRectsData.count) bytes")
                return decoded
            } catch {
                print("❌ ScrapItem.freeRects getter: Failed to decode free rects: \(error)")
                print("   Data size: \(freeRectsData.count) bytes")
                return []
            }
        }
        set {
            do {
                let encoded = try JSONEncoder().encode(newValue)
                freeRectsData = encoded
                print("✅ ScrapItem.freeRects setter: Encoded \(newValue.count) free rects to \(encoded.count) bytes")
            } catch {
                print("❌ ScrapItem.freeRects setter: Failed to encode free rects: \(error)")
                freeRectsData = Data()
            }
        }
    }

    init(
        name: String = "",
        width: Double = 24,
        height: Double = 48,
        thickness: Double? = nil,
        materialType: MaterialType = .sheet,
        notes: String = "",
        colorHex: String = "#E8D5A3",    // birch default
        cuts: [ScrapCut] = []
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
        self.cutsData = (try? JSONEncoder().encode(cuts)) ?? Data()
        // Initialize with full scrap as available if no cuts
        if cuts.isEmpty {
            let fullRect = ScrapFreeRect(x: 0, y: 0, width: width, height: height)
            self.freeRectsData = (try? JSONEncoder().encode([fullRect])) ?? Data()
        } else {
            self.freeRectsData = Data()
        }
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
    
    /// Add a cut to this scrap's history and update free rectangles
    /// - Parameters:
    ///   - cut: The cut that was made
    ///   - updatedFreeRects: The new set of free rectangles after this cut
    func addCut(_ cut: ScrapCut, updatedFreeRects: [ScrapFreeRect]) {
        var currentCuts = cuts
        currentCuts.append(cut)
        cuts = currentCuts
        freeRects = updatedFreeRects
    }
    
    /// Calculate the total remaining usable area
    var remainingArea: Double {
        freeRects.reduce(0) { $0 + $1.area }
    }
    
    /// Get the largest continuous free space (useful for UI display)
    var largestFreeRect: ScrapFreeRect? {
        freeRects.max(by: { $0.area < $1.area })
    }
}
