import Foundation
import SwiftData

/// A saved cut plan that can be reviewed later
@Model
final class SavedPlan {
    var id: UUID = UUID()
    var projectId: UUID
    var projectName: String
    var createdAt: Date = Date()
    var notes: String = ""
    
    /// Serialized CutPlan data (stored as JSON)
    @Attribute(.externalStorage) private var planData: Data = Data()
    
    /// The actual cut plan
    var cutPlan: CutPlan? {
        get {
            guard !planData.isEmpty else { return nil }
            do {
                let decoded = try JSONDecoder().decode(SerializableCutPlan.self, from: planData)
                return decoded.toCutPlan()
            } catch {
                print("❌ Failed to decode saved plan: \(error)")
                return nil
            }
        }
        set {
            guard let plan = newValue else {
                planData = Data()
                return
            }
            do {
                let serializable = SerializableCutPlan(from: plan)
                planData = try JSONEncoder().encode(serializable)
            } catch {
                print("❌ Failed to encode saved plan: \(error)")
                planData = Data()
            }
        }
    }
    
    init(projectId: UUID, projectName: String, cutPlan: CutPlan, notes: String = "") {
        self.id = UUID()
        self.projectId = projectId
        self.projectName = projectName
        self.createdAt = Date()
        self.notes = notes
        
        // Encode the plan
        if let serializable = try? JSONEncoder().encode(SerializableCutPlan(from: cutPlan)) {
            self.planData = serializable
        }
    }
}

// MARK: - Serializable CutPlan (for JSON encoding)

/// A JSON-encodable version of CutPlan
struct SerializableCutPlan: Codable {
    let sheetLayouts: [SerializableSheetLayout]
    let scrapUsages: [SerializableScrapUsage]
    let unplacedPieces: [SerializableRequiredPieceDemand]
    
    init(from cutPlan: CutPlan) {
        self.sheetLayouts = cutPlan.sheetLayouts.map { SerializableSheetLayout(from: $0) }
        self.scrapUsages = cutPlan.scrapUsages.map { SerializableScrapUsage(from: $0) }
        self.unplacedPieces = cutPlan.unplacedPieces.map { SerializableRequiredPieceDemand(from: $0) }
    }
    
    func toCutPlan() -> CutPlan {
        CutPlan(
            sheetLayouts: sheetLayouts.map { $0.toSheetLayout() },
            scrapUsages: scrapUsages.map { $0.toScrapUsage() },
            unplacedPieces: unplacedPieces.map { $0.toRequiredPieceDemand() }
        )
    }
}

struct SerializableSheetLayout: Codable {
    let sheetIndex: Int
    let materialId: String
    let materialName: String
    let materialColorHex: String
    let materialThickness: Double?
    let materialType: String
    let sheetWidth: Double
    let sheetHeight: Double
    let placements: [SerializableCutPlacement]
    let finalFreeRects: [SerializableLayoutFreeRect]
    
    init(from layout: SheetLayout) {
        self.sheetIndex = layout.sheetIndex
        self.materialId = layout.materialId.uuidString
        self.materialName = layout.materialName
        self.materialColorHex = layout.materialColorHex
        self.materialThickness = layout.materialThickness
        self.materialType = layout.materialType.rawValue
        self.sheetWidth = layout.sheetWidth
        self.sheetHeight = layout.sheetHeight
        self.placements = layout.placements.map { SerializableCutPlacement(from: $0) }
        self.finalFreeRects = layout.finalFreeRects.map { SerializableLayoutFreeRect(from: $0) }
    }
    
    func toSheetLayout() -> SheetLayout {
        SheetLayout(
            sheetIndex: sheetIndex,
            materialId: UUID(uuidString: materialId) ?? UUID(),
            materialName: materialName,
            materialColorHex: materialColorHex,
            materialThickness: materialThickness,
            materialType: MaterialType(rawValue: materialType) ?? .sheet,
            sheetWidth: sheetWidth,
            sheetHeight: sheetHeight,
            placements: placements.map { $0.toCutPlacement() },
            finalFreeRects: finalFreeRects.map { $0.toLayoutFreeRect() }
        )
    }
}

struct SerializableCutPlacement: Codable {
    let pieceId: String
    let pieceName: String
    let pieceShape: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let sheetIndex: Int
    let rotated: Bool
    
    init(from placement: CutPlacement) {
        self.pieceId = placement.pieceId.uuidString
        self.pieceName = placement.pieceName
        self.pieceShape = placement.pieceShape.rawValue
        self.x = placement.x
        self.y = placement.y
        self.width = placement.width
        self.height = placement.height
        self.sheetIndex = placement.sheetIndex
        self.rotated = placement.rotated
    }
    
    func toCutPlacement() -> CutPlacement {
        CutPlacement(
            pieceId: UUID(uuidString: pieceId) ?? UUID(),
            pieceName: pieceName,
            pieceShape: PieceShape(rawValue: pieceShape) ?? .rectangle,
            x: x,
            y: y,
            width: width,
            height: height,
            sheetIndex: sheetIndex,
            rotated: rotated
        )
    }
}

struct SerializableLayoutFreeRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    
    init(from rect: LayoutFreeRect) {
        self.x = rect.x
        self.y = rect.y
        self.width = rect.width
        self.height = rect.height
    }
    
    func toLayoutFreeRect() -> LayoutFreeRect {
        LayoutFreeRect(x: x, y: y, width: width, height: height)
    }
}

struct SerializableScrapUsage: Codable {
    let scrapId: String
    let scrapName: String
    let scrapWidth: Double
    let scrapHeight: Double
    let pieceId: String
    let pieceName: String
    let pieceShape: String
    let pieceWidth: Double
    let pieceHeight: Double
    let rotated: Bool
    let materialType: String
    let thickness: Double?
    let colorHex: String
    let cutX: Double
    let cutY: Double
    let updatedFreeRects: [SerializableScrapFreeRect]
    
    init(from usage: ScrapUsage) {
        self.scrapId = usage.scrapId.uuidString
        self.scrapName = usage.scrapName
        self.scrapWidth = usage.scrapWidth
        self.scrapHeight = usage.scrapHeight
        self.pieceId = usage.pieceId.uuidString
        self.pieceName = usage.pieceName
        self.pieceShape = usage.pieceShape.rawValue
        self.pieceWidth = usage.pieceWidth
        self.pieceHeight = usage.pieceHeight
        self.rotated = usage.rotated
        self.materialType = usage.materialType.rawValue
        self.thickness = usage.thickness
        self.colorHex = usage.colorHex
        self.cutX = usage.cutX
        self.cutY = usage.cutY
        self.updatedFreeRects = usage.updatedFreeRects.map { SerializableScrapFreeRect(from: $0) }
    }
    
    func toScrapUsage() -> ScrapUsage {
        ScrapUsage(
            scrapId: UUID(uuidString: scrapId) ?? UUID(),
            scrapName: scrapName,
            scrapWidth: scrapWidth,
            scrapHeight: scrapHeight,
            pieceId: UUID(uuidString: pieceId) ?? UUID(),
            pieceName: pieceName,
            pieceShape: PieceShape(rawValue: pieceShape) ?? .rectangle,
            pieceWidth: pieceWidth,
            pieceHeight: pieceHeight,
            rotated: rotated,
            materialType: MaterialType(rawValue: materialType) ?? .sheet,
            thickness: thickness,
            colorHex: colorHex,
            cutX: cutX,
            cutY: cutY,
            updatedFreeRects: updatedFreeRects.map { $0.toScrapFreeRect() }
        )
    }
}

struct SerializableScrapFreeRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    
    init(from rect: ScrapFreeRect) {
        self.x = rect.x
        self.y = rect.y
        self.width = rect.width
        self.height = rect.height
    }
    
    func toScrapFreeRect() -> ScrapFreeRect {
        ScrapFreeRect(x: x, y: y, width: width, height: height)
    }
}

struct SerializableRequiredPieceDemand: Codable {
    let pieceId: String
    let pieceName: String
    let width: Double
    let height: Double
    let shape: String
    let thickness: Double?
    let materialType: String
    let colorHex: String
    let rotationAllowed: Bool
    let grainDirectionLocked: Bool
    
    init(from demand: RequiredPieceDemand) {
        self.pieceId = demand.pieceId.uuidString
        self.pieceName = demand.pieceName
        self.width = demand.width
        self.height = demand.height
        self.shape = demand.shape.rawValue
        self.thickness = demand.thickness
        self.materialType = demand.materialType.rawValue
        self.colorHex = demand.colorHex
        self.rotationAllowed = demand.rotationAllowed
        self.grainDirectionLocked = demand.grainDirectionLocked
    }
    
    func toRequiredPieceDemand() -> RequiredPieceDemand {
        RequiredPieceDemand(
            pieceId: UUID(uuidString: pieceId) ?? UUID(),
            pieceName: pieceName,
            width: width,
            height: height,
            shape: PieceShape(rawValue: shape) ?? .rectangle,
            thickness: thickness,
            materialType: MaterialType(rawValue: materialType) ?? .sheet,
            colorHex: colorHex,
            rotationAllowed: rotationAllowed,
            grainDirectionLocked: grainDirectionLocked
        )
    }
}
