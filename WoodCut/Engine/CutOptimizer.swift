import Foundation

/// Guillotine-based rectangle packing optimizer.
///
/// Algorithm overview:
///   1. Expand piece quantities into individual demands.
///   2. Sort demands largest-area-first (First Fit Decreasing).
///   3. Reserve the smallest matching scrap item that can fulfill each demand.
///   4. For remaining demands, find the smallest free rectangle that fits (Best Area Fit).
///   5. If no open sheet fits, open the next compatible sheet from the material pool.
///   6. If the piece won't fit even on a fresh matching sheet, mark it unplaced.
///
/// The guillotine split produces two non-overlapping free rectangles:
///   - Right column: full height, to the right of the placed piece + kerf
///   - Top row:      above the placed piece + kerf, left column width
///
struct CutOptimizer {

    // MARK: - Public API

    static func optimize(project: Project, scrapItems: [ScrapItem] = []) -> CutPlan {
        let kerf = project.kerfWidth
        let trim = project.trimMargin
        let scrapUsageMode = project.scrapUsageMode

        let demands = expandPieces(project.pieces)
            .sorted { ($0.width * $0.height) > ($1.width * $1.height) }

        var scrapPool = scrapUsageMode == .ignoreScrap ? [] : buildScrapPool(from: scrapItems)
        var sheetPool = scrapUsageMode == .onlyScrap ? [] : buildSheetPool(from: project.materials, trim: trim)

        var scrapUsages: [ScrapUsage] = []
        var layouts: [SheetLayout] = []
        var freeRectSets: [[FreeRect]] = []
        var unplaced: [RequiredPieceDemand] = []

        for demand in demands {
            if let scrapMatch = bestFitScrap(demand: demand, scrapPool: scrapPool) {
                scrapUsages.append(scrapMatch.usage)
                scrapPool.remove(at: scrapMatch.index)
                continue
            }

            if scrapUsageMode == .onlyScrap {
                unplaced.append(demand)
                continue
            }

            var placed = false

            for i in layouts.indices {
                guard layout(layouts[i], matches: demand) else { continue }
                if let result = bestFitPlace(
                    demand: demand,
                    sheetIndex: i,
                    freeRects: freeRectSets[i],
                    kerf: kerf
                ) {
                    layouts[i].placements.append(result.placement)
                    freeRectSets[i] = result.updatedFreeRects
                    placed = true
                    break
                }
            }

            if !placed {
                let candidates = sheetPool.enumerated()
                    .filter { templateMatchesDemand($0.element, demand: demand) }
                    .sorted { left, right in
                        (left.element.width * left.element.height) < (right.element.width * right.element.height)
                    }

                let idx = layouts.count
                var openedSheet = false

                for candidate in candidates {
                    let template = candidate.element
                    let initialRect = FreeRect(x: 0, y: 0, width: template.width, height: template.height)

                    if let result = bestFitPlace(
                        demand: demand,
                        sheetIndex: idx,
                        freeRects: [initialRect],
                        kerf: kerf
                    ) {
                        sheetPool.remove(at: candidate.offset)
                        layouts.append(SheetLayout(
                            sheetIndex: idx,
                            materialId: template.materialId,
                            materialName: template.materialName,
                            materialColorHex: template.colorHex,
                            materialThickness: template.thickness,
                            materialType: template.materialType,
                            sheetWidth: template.width,
                            sheetHeight: template.height,
                            placements: [result.placement]
                        ))
                        freeRectSets.append(result.updatedFreeRects)
                        openedSheet = true
                        break
                    }
                }

                if !openedSheet {
                    unplaced.append(demand)
                }
            }
        }

        for i in layouts.indices {
            layouts[i].finalFreeRects = freeRectSets[i].map {
                LayoutFreeRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
            }
        }

        return CutPlan(sheetLayouts: layouts, scrapUsages: scrapUsages, unplacedPieces: unplaced)
    }

    // MARK: - Private types

    private struct FreeRect {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    private struct PlacementResult {
        let placement: CutPlacement
        let updatedFreeRects: [FreeRect]
    }

    private struct ScrapMatchResult {
        let index: Int
        let usage: ScrapUsage
    }

    private struct SheetTemplate {
        let materialId: UUID
        let materialName: String
        let colorHex: String
        let thickness: Double?
        let materialType: MaterialType
        let width: Double
        let height: Double
    }

    private struct ScrapTemplate {
        let scrapId: UUID
        let scrapName: String
        let width: Double
        let height: Double
        let thickness: Double?
        let materialType: MaterialType
        let colorHex: String
    }

    // MARK: - Placement logic

    private static func bestFitPlace(
        demand: RequiredPieceDemand,
        sheetIndex: Int,
        freeRects: [FreeRect],
        kerf: Double
    ) -> PlacementResult? {
        if let result = placeOriented(
            demand: demand,
            w: demand.width,
            h: demand.height,
            sheetIndex: sheetIndex,
            freeRects: freeRects,
            kerf: kerf,
            rotated: false
        ) {
            return result
        }

        if demand.rotationAllowed && !demand.grainDirectionLocked {
            return placeOriented(
                demand: demand,
                w: demand.height,
                h: demand.width,
                sheetIndex: sheetIndex,
                freeRects: freeRects,
                kerf: kerf,
                rotated: true
            )
        }

        return nil
    }

    /// Best-Area-Fit: find the smallest free rect that accommodates (w+kerf) × (h+kerf).
    private static func placeOriented(
        demand: RequiredPieceDemand,
        w: Double,
        h: Double,
        sheetIndex: Int,
        freeRects: [FreeRect],
        kerf: Double,
        rotated: Bool
    ) -> PlacementResult? {
        let neededW = w + kerf
        let neededH = h + kerf

        var bestIdx: Int? = nil
        var bestArea = Double.infinity

        for (i, rect) in freeRects.enumerated() {
            if rect.width >= neededW && rect.height >= neededH {
                let area = rect.width * rect.height
                if area < bestArea {
                    bestArea = area
                    bestIdx = i
                }
            }
        }

        guard let idx = bestIdx else { return nil }

        let rect = freeRects[idx]
        let placement = CutPlacement(
            pieceId: demand.pieceId,
            pieceName: demand.pieceName,
            pieceShape: demand.shape,
            x: rect.x,
            y: rect.y,
            width: w,
            height: h,
            sheetIndex: sheetIndex,
            rotated: rotated
        )

        let rightRect = FreeRect(
            x: rect.x + neededW,
            y: rect.y,
            width: rect.width - neededW,
            height: rect.height
        )
        let topRect = FreeRect(
            x: rect.x,
            y: rect.y + neededH,
            width: neededW,
            height: rect.height - neededH
        )

        var updated = freeRects
        updated.remove(at: idx)
        if rightRect.width > kerf && rightRect.height > kerf { updated.append(rightRect) }
        if topRect.width > kerf && topRect.height > kerf { updated.append(topRect) }

        return PlacementResult(placement: placement, updatedFreeRects: updated)
    }

    private static func bestFitScrap(
        demand: RequiredPieceDemand,
        scrapPool: [ScrapTemplate]
    ) -> ScrapMatchResult? {
        var bestIndex: Int? = nil
        var bestUsage: ScrapUsage? = nil
        var bestArea = Double.infinity

        for (index, scrap) in scrapPool.enumerated() {
            guard scrapMatchesDemand(scrap, demand: demand) else { continue }

            let orientations: [(width: Double, height: Double, rotated: Bool)] = [
                (demand.width, demand.height, false),
                (demand.height, demand.width, true),
            ]

            for option in orientations {
                if option.rotated && (!demand.rotationAllowed || demand.grainDirectionLocked) {
                    continue
                }
                guard scrap.width >= option.width, scrap.height >= option.height else {
                    continue
                }

                let area = scrap.width * scrap.height
                if area < bestArea {
                    bestArea = area
                    bestIndex = index
                    bestUsage = ScrapUsage(
                        scrapId: scrap.scrapId,
                        scrapName: scrap.scrapName,
                        scrapWidth: scrap.width,
                        scrapHeight: scrap.height,
                        pieceId: demand.pieceId,
                        pieceName: demand.pieceName,
                        pieceShape: demand.shape,
                        pieceWidth: demand.width,
                        pieceHeight: demand.height,
                        rotated: option.rotated,
                        materialType: demand.materialType,
                        thickness: demand.thickness,
                        colorHex: demand.colorHex
                    )
                }
                break
            }
        }

        guard let bestIndex, let bestUsage else { return nil }
        return ScrapMatchResult(index: bestIndex, usage: bestUsage)
    }

    // MARK: - Expansion helpers

    static func expandPieces(_ pieces: [RequiredPiece]) -> [RequiredPieceDemand] {
        pieces.flatMap { piece in
            (0..<max(1, piece.quantity)).map { _ in
                RequiredPieceDemand(
                    pieceId: piece.id,
                    pieceName: piece.displayName,
                    width: piece.width,
                    height: piece.height,
                    shape: piece.shape,
                    thickness: piece.thickness,
                    materialType: piece.materialType,
                    colorHex: piece.colorHex,
                    rotationAllowed: piece.rotationAllowed,
                    grainDirectionLocked: piece.grainDirectionLocked
                )
            }
        }
    }

    private static func buildSheetPool(
        from materials: [MaterialItem],
        trim: Double
    ) -> [SheetTemplate] {
        materials.flatMap { material in
            let usableW = max(material.width - trim * 2, 0)
            let usableH = max(material.height - trim * 2, 0)
            return (0..<max(1, material.quantity)).map { _ in
                SheetTemplate(
                    materialId: material.id,
                    materialName: material.displayName,
                    colorHex: material.colorHex,
                    thickness: material.thickness,
                    materialType: material.materialType,
                    width: usableW,
                    height: usableH
                )
            }
        }
    }

    private static func buildScrapPool(from scrapItems: [ScrapItem]) -> [ScrapTemplate] {
        scrapItems.compactMap { scrap in
            guard scrap.width > 0, scrap.height > 0 else { return nil }
            return ScrapTemplate(
                scrapId: scrap.id,
                scrapName: scrap.displayName,
                width: scrap.width,
                height: scrap.height,
                thickness: scrap.thickness,
                materialType: scrap.materialType,
                colorHex: scrap.colorHex
            )
        }
    }

    private static func templateMatchesDemand(_ template: SheetTemplate, demand: RequiredPieceDemand) -> Bool {
        materialAttributesMatch(
            materialType: template.materialType,
            thickness: template.thickness,
            colorHex: template.colorHex,
            requiredType: demand.materialType,
            requiredThickness: demand.thickness,
            requiredColorHex: demand.colorHex
        )
    }

    private static func scrapMatchesDemand(_ scrap: ScrapTemplate, demand: RequiredPieceDemand) -> Bool {
        materialAttributesMatch(
            materialType: scrap.materialType,
            thickness: scrap.thickness,
            colorHex: scrap.colorHex,
            requiredType: demand.materialType,
            requiredThickness: demand.thickness,
            requiredColorHex: demand.colorHex
        )
    }

    private static func layout(_ layout: SheetLayout, matches demand: RequiredPieceDemand) -> Bool {
        materialAttributesMatch(
            materialType: layout.materialType,
            thickness: layout.materialThickness,
            colorHex: layout.materialColorHex,
            requiredType: demand.materialType,
            requiredThickness: demand.thickness,
            requiredColorHex: demand.colorHex
        )
    }
}
