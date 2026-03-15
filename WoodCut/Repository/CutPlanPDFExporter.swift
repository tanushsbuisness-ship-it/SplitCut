import Foundation
import SwiftUI
import UIKit

enum CutPlanPDFMode: String, CaseIterable {
    case singlePageA4 = "A4 Fit"
    case tiledFullScaleA4 = "A4 Full Scale"

    var fileSuffix: String {
        switch self {
        case .singlePageA4:
            return "a4-fit"
        case .tiledFullScaleA4:
            return "a4-full-scale"
        }
    }

    var printHint: String {
        switch self {
        case .singlePageA4:
            return "Scaled to fit one A4 page per board or scrap piece."
        case .tiledFullScaleA4:
            return "Print at 100% or Actual Size. Do not use Fit to Page."
        }
    }
}

struct CutPlanPDFExporter {
    private static let a4PageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private static let pageMargins = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
    private static let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 24, weight: .bold),
        .foregroundColor: UIColor.label,
    ]
    private static let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: UIColor.secondaryLabel,
    ]
    private static let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: UIColor.label,
    ]
    private static let sectionAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: UIColor.label,
    ]

    static func export(cutPlan: CutPlan, projectName: String, mode: CutPlanPDFMode) throws -> URL {
        let surfaces = printableSurfaces(from: cutPlan)
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: a4PageRect, format: format)
        let data = renderer.pdfData { rendererContext in
            if surfaces.isEmpty {
                drawEmptyStatePage(in: rendererContext, projectName: projectName, mode: mode)
                return
            }

            for surface in surfaces {
                switch mode {
                case .singlePageA4:
                    drawSinglePageDiagram(for: surface, projectName: projectName, mode: mode, in: rendererContext)
                case .tiledFullScaleA4:
                    drawTiledDiagram(for: surface, projectName: projectName, mode: mode, in: rendererContext)
                }
                drawInstructionPage(for: surface, projectName: projectName, mode: mode, in: rendererContext)
            }
        }

        let sanitizedProjectName = projectName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedProjectName)-\(mode.fileSuffix).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func printableSurfaces(from cutPlan: CutPlan) -> [PrintableSurface] {
        var surfaces = cutPlan.scrapUsages.map { usage in
            PrintableSurface(
                title: "Scrap — \(usage.scrapName)",
                subtitle: "\(dimStr(usage.scrapWidth)) × \(dimStr(usage.scrapHeight)) · \(materialSummaryText(materialType: usage.materialType, thickness: usage.thickness, colorHex: usage.colorHex))",
                width: usage.scrapWidth,
                height: usage.scrapHeight,
                materialColorHex: usage.colorHex,
                grainColorHex: MaterialColorPreset.preset(for: usage.colorHex)?.grainHex,
                placements: [
                    PrintablePlacement(
                        name: usage.pieceName,
                        shape: usage.pieceShape,
                        x: 0,
                        y: 0,
                        width: usage.rotated ? usage.pieceHeight : usage.pieceWidth,
                        height: usage.rotated ? usage.pieceWidth : usage.pieceHeight
                    ),
                ],
                instructionLines: [
                    "Take \"\(usage.pieceName)\" from \"\(usage.scrapName)\".",
                    "Piece size: \(dimStr(usage.pieceWidth)) × \(dimStr(usage.pieceHeight))\(usage.rotated ? " (rotate on scrap)" : "").",
                    "Scrap size: \(dimStr(usage.scrapWidth)) × \(dimStr(usage.scrapHeight)).",
                ]
            )
        }

        surfaces += cutPlan.sheetLayouts.map { layout in
            let sortedPlacements = layout.placements.sorted {
                abs($0.y - $1.y) > 0.5 ? $0.y < $1.y : $0.x < $1.x
            }
            return PrintableSurface(
                title: "Sheet \(layout.sheetIndex + 1) — \(layout.materialName)",
                subtitle: "\(dimStr(layout.sheetWidth)) × \(dimStr(layout.sheetHeight)) · \(materialSummaryText(materialType: layout.materialType, thickness: layout.materialThickness, colorHex: layout.materialColorHex))",
                width: layout.sheetWidth,
                height: layout.sheetHeight,
                materialColorHex: layout.materialColorHex,
                grainColorHex: MaterialColorPreset.preset(for: layout.materialColorHex)?.grainHex,
                placements: sortedPlacements.map {
                    PrintablePlacement(name: $0.pieceName, shape: $0.pieceShape, x: $0.x, y: $0.y, width: $0.width, height: $0.height)
                },
                instructionLines: sortedPlacements.enumerated().map { index, placement in
                    "Cut \(index + 1): \"\(placement.pieceName)\" — \(dimStr(placement.width)) × \(dimStr(placement.height)) @ (\(dimStr(placement.x)), \(dimStr(placement.y)))."
                } + [String(format: "Estimated waste: %.1f%%", layout.wastePercentage)]
            )
        }

        return surfaces
    }

    private static func drawEmptyStatePage(in rendererContext: UIGraphicsPDFRendererContext, projectName: String, mode: CutPlanPDFMode) {
        rendererContext.beginPage()
        let titleRect = CGRect(x: pageMargins.left, y: pageMargins.top, width: a4PageRect.width - pageMargins.left - pageMargins.right, height: 32)
        NSString(string: projectName).draw(in: titleRect, withAttributes: titleAttributes)
        NSString(string: mode.printHint).draw(
            in: CGRect(x: pageMargins.left, y: titleRect.maxY + 8, width: titleRect.width, height: 20),
            withAttributes: subtitleAttributes
        )
        NSString(string: "No cut lines were generated for this plan.").draw(
            in: CGRect(x: pageMargins.left, y: titleRect.maxY + 48, width: titleRect.width, height: 24),
            withAttributes: sectionAttributes
        )
    }

    private static func drawSinglePageDiagram(
        for surface: PrintableSurface,
        projectName: String,
        mode: CutPlanPDFMode,
        in rendererContext: UIGraphicsPDFRendererContext
    ) {
        rendererContext.beginPage()
        let contentRect = drawHeader(for: surface, projectName: projectName, mode: mode)
        let diagramRect = contentRect.insetBy(dx: 0, dy: 12)
        let scale = min(diagramRect.width / surface.width, diagramRect.height / surface.height)
        let drawSize = CGSize(width: surface.width * scale, height: surface.height * scale)
        let origin = CGPoint(
            x: diagramRect.minX + (diagramRect.width - drawSize.width) / 2,
            y: diagramRect.minY + (diagramRect.height - drawSize.height) / 2
        )
        drawSurface(surface, in: CGRect(origin: origin, size: drawSize), pointsPerInch: scale)
        drawFooter(mode: mode, pageLabel: "Diagram")
    }

    private static func drawTiledDiagram(
        for surface: PrintableSurface,
        projectName: String,
        mode: CutPlanPDFMode,
        in rendererContext: UIGraphicsPDFRendererContext
    ) {
        let headerHeight: CGFloat = 78
        let footerHeight: CGFloat = 28
        let contentRect = a4PageRect.inset(by: pageMargins)
        let tileRect = CGRect(
            x: contentRect.minX,
            y: contentRect.minY + headerHeight,
            width: contentRect.width,
            height: contentRect.height - headerHeight - footerHeight
        )
        let cols = max(1, Int(ceil((surface.width * 72) / tileRect.width)))
        let rows = max(1, Int(ceil((surface.height * 72) / tileRect.height)))

        for row in 0..<rows {
            for col in 0..<cols {
                rendererContext.beginPage()
                _ = drawHeader(
                    for: surface,
                    projectName: projectName,
                    mode: mode,
                    tileLabel: "Tile \(row + 1)-\(col + 1) of \(rows)x\(cols)"
                )
                let tileOrigin = CGPoint(x: CGFloat(col) * tileRect.width, y: CGFloat(row) * tileRect.height)
                guard let context = UIGraphicsGetCurrentContext() else { continue }
                context.saveGState()
                context.clip(to: tileRect)
                context.translateBy(x: tileRect.minX - tileOrigin.x, y: tileRect.minY - tileOrigin.y)
                drawSurface(
                    surface,
                    in: CGRect(x: 0, y: 0, width: surface.width * 72, height: surface.height * 72),
                    pointsPerInch: 72
                )
                context.restoreGState()
                drawTileGuides(in: tileRect, row: row, col: col, rows: rows, cols: cols)
                drawFooter(mode: mode, pageLabel: "Tile \(row + 1)-\(col + 1)")
            }
        }
    }

    private static func drawInstructionPage(
        for surface: PrintableSurface,
        projectName: String,
        mode: CutPlanPDFMode,
        in rendererContext: UIGraphicsPDFRendererContext
    ) {
        rendererContext.beginPage()
        let contentRect = drawHeader(
            for: surface,
            projectName: projectName,
            mode: mode,
            tileLabel: "Instructions"
        )
        let title = "Instructions for \(surface.title)"
        NSString(string: title).draw(
            in: CGRect(x: contentRect.minX, y: contentRect.minY + 12, width: contentRect.width, height: 24),
            withAttributes: sectionAttributes
        )

        let intro = mode == .tiledFullScaleA4
            ? "These instructions follow the tiled diagram pages. Print double-sided with Actual Size if you want this page on the back of the last tile."
            : "This page is placed after the scaled diagram page so it can print on the back side when duplex printing."
        NSString(string: intro).draw(
            in: CGRect(x: contentRect.minX, y: contentRect.minY + 42, width: contentRect.width, height: 42),
            withAttributes: subtitleAttributes
        )

        var cursorY = contentRect.minY + 96
        for (index, line) in surface.instructionLines.enumerated() {
            let rect = CGRect(x: contentRect.minX, y: cursorY, width: contentRect.width, height: 40)
            NSString(string: "\(index + 1). \(line)").draw(in: rect, withAttributes: bodyAttributes)
            cursorY += 28
        }

        drawFooter(mode: mode, pageLabel: "Instructions")
    }

    @discardableResult
    private static func drawHeader(
        for surface: PrintableSurface,
        projectName: String,
        mode: CutPlanPDFMode,
        tileLabel: String? = nil
    ) -> CGRect {
        let contentRect = a4PageRect.inset(by: pageMargins)
        NSString(string: projectName).draw(
            in: CGRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: 28),
            withAttributes: titleAttributes
        )
        NSString(string: surface.title).draw(
            in: CGRect(x: contentRect.minX, y: contentRect.minY + 30, width: contentRect.width, height: 22),
            withAttributes: sectionAttributes
        )
        NSString(string: surface.subtitle).draw(
            in: CGRect(x: contentRect.minX, y: contentRect.minY + 52, width: contentRect.width, height: 18),
            withAttributes: subtitleAttributes
        )
        let detail = tileLabel.map { "\(mode.printHint) · \($0)" } ?? mode.printHint
        NSString(string: detail).draw(
            in: CGRect(x: contentRect.minX, y: contentRect.minY + 68, width: contentRect.width, height: 18),
            withAttributes: subtitleAttributes
        )

        return CGRect(
            x: contentRect.minX,
            y: contentRect.minY + 92,
            width: contentRect.width,
            height: contentRect.height - 120
        )
    }

    private static func drawFooter(mode: CutPlanPDFMode, pageLabel: String) {
        let rect = CGRect(x: pageMargins.left, y: a4PageRect.height - pageMargins.bottom - 16, width: a4PageRect.width - pageMargins.left - pageMargins.right, height: 16)
        let footer = "\(pageLabel) · \(mode == .tiledFullScaleA4 ? "Print at Actual Size" : "Scaled PDF")"
        NSString(string: footer).draw(in: rect, withAttributes: subtitleAttributes)
    }

    private static func drawTileGuides(in rect: CGRect, row: Int, col: Int, rows: Int, cols: Int) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        UIColor.systemBlue.setStroke()
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.stroke(rect.insetBy(dx: 2, dy: 2))
        context.restoreGState()

        let badgeRect = CGRect(x: rect.maxX - 82, y: rect.minY + 8, width: 74, height: 20)
        UIBezierPath(roundedRect: badgeRect, cornerRadius: 10).addClip()
        UIColor.systemBlue.withAlphaComponent(0.14).setFill()
        UIRectFill(badgeRect)
        NSString(string: "\(row + 1)-\(col + 1)").draw(
            in: badgeRect.insetBy(dx: 10, dy: 3),
            withAttributes: subtitleAttributes
        )
    }

    private static func drawSurface(_ surface: PrintableSurface, in rect: CGRect, pointsPerInch: CGFloat) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()

        let baseColor = UIColor(hex: surface.materialColorHex)
        baseColor.setFill()
        context.fill(rect)

        if let grainColorHex = surface.grainColorHex {
            drawGrain(in: rect, color: UIColor(hex: grainColorHex))
        }

        UIColor.label.withAlphaComponent(0.85).setStroke()
        context.setLineWidth(1.5)
        context.stroke(rect)

        for (index, placement) in surface.placements.enumerated() {
            let pieceRect = CGRect(
                x: rect.minX + placement.x * pointsPerInch,
                y: rect.minY + placement.y * pointsPerInch,
                width: placement.width * pointsPerInch,
                height: placement.height * pointsPerInch
            )
            let fill = UIColor(CutDiagramView.palette[index % CutDiagramView.palette.count]).withAlphaComponent(0.78)
            let stroke = UIColor(CutDiagramView.palette[index % CutDiagramView.palette.count])
            let piecePath = bezierPath(for: placement.shape, in: pieceRect)
            fill.setFill()
            piecePath.fill()
            stroke.setStroke()
            context.setLineWidth(1.0)
            piecePath.lineWidth = 1.0
            piecePath.stroke()

            if pieceRect.width >= 48, pieceRect.height >= 20 {
                let labelRect = pieceRect.insetBy(dx: 6, dy: 6)
                let labelText = placement.shape == .rectangle
                    ? placement.name
                    : "\(placement.name)\n\(placement.shape.rawValue)"
                NSString(string: labelText).draw(
                    in: labelRect,
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: max(9, min(18, pieceRect.height * 0.18)), weight: .medium),
                        .foregroundColor: UIColor.label,
                    ]
                )
            }
        }

        context.restoreGState()
    }

    private static func drawGrain(in rect: CGRect, color: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        color.withAlphaComponent(0.22).setStroke()
        context.setLineWidth(0.55)

        let spacing: CGFloat = 8
        let lineCount = Int(rect.height / spacing) + 1
        let segmentCount = max(Int(rect.width / 16), 10)

        for i in 0..<lineCount {
            let yBase = rect.minY + CGFloat(i) * spacing
            let amp = CGFloat(1.2 + 0.4 * sin(Double(i) * 0.41))
            let freq = 0.55 + 0.15 * sin(Double(i) * 0.17)
            let phase = Double(i) * 1.3

            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX, y: yBase))
            for segment in 1...segmentCount {
                let x = rect.minX + rect.width * CGFloat(segment) / CGFloat(segmentCount)
                let y = yBase + amp * CGFloat(sin(Double(segment) * freq + phase))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.stroke()
        }

        context.restoreGState()
    }

    private static func bezierPath(for shape: PieceShape, in rect: CGRect) -> UIBezierPath {
        switch shape {
        case .rectangle:
            return UIBezierPath(rect: rect)
        case .triangle:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.close()
            return path
        case .circle:
            return UIBezierPath(ovalIn: rect)
        case .semicircle:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addArc(
                withCenter: CGPoint(x: rect.midX, y: rect.maxY),
                radius: rect.width / 2,
                startAngle: .pi,
                endAngle: 0,
                clockwise: true
            )
            path.close()
            return path
        case .quarterCircle:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addArc(
                withCenter: CGPoint(x: rect.minX, y: rect.maxY),
                radius: rect.width,
                startAngle: 0,
                endAngle: -.pi / 2,
                clockwise: false
            )
            path.close()
            return path
        }
    }
}

private struct PrintableSurface {
    let title: String
    let subtitle: String
    let width: Double
    let height: Double
    let materialColorHex: String
    let grainColorHex: String?
    let placements: [PrintablePlacement]
    let instructionLines: [String]
}

private struct PrintablePlacement {
    let name: String
    let shape: PieceShape
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private extension UIColor {
    convenience init(hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard raw.count == 6, let value = UInt64(raw, radix: 16) else {
            self.init(white: 0.6, alpha: 1)
            return
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
