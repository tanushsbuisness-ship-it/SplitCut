import Foundation

// MARK: - Engine input types

/// One individual piece demand (after expanding quantity > 1)
struct RequiredPieceDemand {
    let pieceId: UUID
    let pieceName: String
    let width: Double
    let height: Double
    let shape: PieceShape
    let thickness: Double?
    let materialType: MaterialType
    let colorHex: String
    let rotationAllowed: Bool
    let grainDirectionLocked: Bool
}

// MARK: - Engine output types

/// A single piece placed on a sheet at (x, y)
struct CutPlacement: Identifiable {
    let id = UUID()
    let pieceId: UUID
    let pieceName: String
    let pieceShape: PieceShape
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let sheetIndex: Int
    let rotated: Bool
}

/// A remaining free rectangle on a sheet after all pieces have been packed.
/// Used by the result view to offer off-cuts for the Scrap Bin.
struct LayoutFreeRect: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    var area: Double { width * height }
}

struct ScrapUsage: Identifiable {
    let id = UUID()
    let scrapId: UUID
    let scrapName: String
    let scrapWidth: Double
    let scrapHeight: Double
    let pieceId: UUID
    let pieceName: String
    let pieceShape: PieceShape
    let pieceWidth: Double
    let pieceHeight: Double
    let rotated: Bool
    let materialType: MaterialType
    let thickness: Double?
    let colorHex: String
    /// Position where the piece was cut from the scrap (x, y coordinates)
    let cutX: Double
    let cutY: Double
    /// Updated free rectangles after this cut (for database persistence)
    let updatedFreeRects: [ScrapFreeRect]

    var scrapArea: Double { scrapWidth * scrapHeight }
    
    /// Convert this usage to a ScrapCut for recording on the ScrapItem
    func toScrapCut() -> ScrapCut {
        ScrapCut(
            x: cutX,
            y: cutY,
            width: pieceWidth,
            height: pieceHeight,
            shape: pieceShape,
            pieceName: pieceName
        )
    }
}

/// All placements on one physical sheet
struct SheetLayout: Identifiable {
    let id = UUID()
    let sheetIndex: Int
    let materialId: UUID
    let materialName: String
    let materialColorHex: String    // propagated from MaterialItem for diagram rendering
    let materialThickness: Double?
    let materialType: MaterialType
    let sheetWidth: Double
    let sheetHeight: Double
    var placements: [CutPlacement]
    /// Remaining free rectangles after all pieces have been packed.
    var finalFreeRects: [LayoutFreeRect] = []

    var usedArea: Double   { placements.reduce(0) { $0 + $1.width * $1.height } }
    var totalArea: Double  { sheetWidth * sheetHeight }
    var wasteArea: Double  { totalArea - usedArea }

    var wastePercentage: Double {
        guard totalArea > 0 else { return 0 }
        return (wasteArea / totalArea) * 100
    }

    /// The single largest remaining rectangle — best candidate for a scrap piece.
    var largestFreeRect: LayoutFreeRect? {
        finalFreeRects.max(by: { $0.area < $1.area })
    }
}

/// Full result returned by CutOptimizer
struct CutPlan {
    let sheetLayouts: [SheetLayout]
    let scrapUsages: [ScrapUsage]
    let unplacedPieces: [RequiredPieceDemand]

    var sheetsUsed: Int         { sheetLayouts.count }
    var totalPlacedPieces: Int  { sheetLayouts.reduce(0) { $0 + $1.placements.count } }
    var totalScrapPieces: Int   { scrapUsages.count }
    var totalFulfilledPieces: Int { totalPlacedPieces + totalScrapPieces }

    var overallWastePercentage: Double {
        let total = sheetLayouts.reduce(0.0) { $0 + $1.totalArea }
        let used  = sheetLayouts.reduce(0.0) { $0 + $1.usedArea }
        guard total > 0 else { return 0 }
        return ((total - used) / total) * 100
    }

    /// Human-readable cut instructions sorted top→bottom, left→right per sheet.
    var cutInstructions: [String] {
        var lines: [String] = []
        lines.append("Sheets used: \(sheetsUsed)")
        lines.append(String(format: "Estimated waste: %.1f%%", overallWastePercentage))
        lines.append("From scrap: \(totalScrapPieces)")
        if !unplacedPieces.isEmpty {
            lines.append("⚠️ \(unplacedPieces.count) piece(s) could not be placed — check sizes")
        }

        if !scrapUsages.isEmpty {
            lines.append("")
            lines.append("From Scrap Bin:")
            let sortedScrap = scrapUsages.sorted { left, right in
                if left.pieceName != right.pieceName {
                    return left.pieceName.localizedCompare(right.pieceName) == .orderedAscending
                }
                return left.scrapArea < right.scrapArea
            }
            for (n, usage) in sortedScrap.enumerated() {
                let dims = usage.rotated
                    ? "\(shapeDimensionText(shape: usage.pieceShape, width: usage.pieceHeight, height: usage.pieceWidth)) (rotated)"
                    : shapeDimensionText(shape: usage.pieceShape, width: usage.pieceWidth, height: usage.pieceHeight)
                lines.append("  \(n + 1). \"\(usage.pieceName)\" — \(dims) from \"\(usage.scrapName)\"")
            }
        }

        for layout in sheetLayouts {
            lines.append("")
            lines.append(
                "Sheet \(layout.sheetIndex + 1) — \(layout.materialName) " +
                "(\(dimStr(layout.sheetWidth)) × \(dimStr(layout.sheetHeight)))" +
                " · \(materialSummaryText(materialType: layout.materialType, thickness: layout.materialThickness, colorHex: layout.materialColorHex))"
            )
            let sorted = layout.placements.sorted {
                abs($0.y - $1.y) > 0.5 ? $0.y < $1.y : $0.x < $1.x
            }
            for (n, p) in sorted.enumerated() {
                let dims = p.rotated
                    ? "\(shapeDimensionText(shape: p.pieceShape, width: p.height, height: p.width)) (rotated)"
                    : shapeDimensionText(shape: p.pieceShape, width: p.width, height: p.height)
                lines.append("  \(n + 1). \"\(p.pieceName)\" — \(dims) @ (\(dimStr(p.x)), \(dimStr(p.y)))")
            }
            lines.append(String(format: "  Sheet waste: %.1f%%", layout.wastePercentage))
        }

        if !unplacedPieces.isEmpty {
            lines.append("")
            lines.append("Unplaced pieces:")
            for p in unplacedPieces {
                lines.append("  • \"\(p.pieceName)\" \(shapeDimensionText(shape: p.shape, width: p.width, height: p.height))")
            }
        }
        return lines
    }
}

// MARK: - Shared formatting helper

/// Format a dimension as inches. Whole number if exact, else 2 decimal places.
func dimStr(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
        ? "\(Int(value))\""
        : String(format: "%.2f\"", value)
}

func shapeDimensionText(shape: PieceShape, width: Double, height: Double) -> String {
    switch shape {
    case .rectangle:
        return "\(dimStr(width)) × \(dimStr(height))"
    case .triangle:
        return "Right triangle in \(dimStr(width)) × \(dimStr(height)) box"
    case .circle:
        return "Circle Ø \(dimStr(width))"
    case .semicircle:
        return "Semicircle Ø \(dimStr(width))"
    case .quarterCircle:
        return "Quarter circle r \(dimStr(width))"
    }
}
