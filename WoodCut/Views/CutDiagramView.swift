import SwiftUI

/// Renders a scaled visual layout of pieces placed on one sheet,
/// with material color and optional wood grain texture.
///
/// Usage: apply `.aspectRatio(layout.sheetWidth / layout.sheetHeight, contentMode: .fit)` on the parent.
struct CutDiagramView: View {

    let layout: SheetLayout

    /// Stable color palette for piece fills — indexed by insertion order, never random.
    static let palette: [Color] = [
        Color(red: 0.33, green: 0.62, blue: 0.80),  // steel blue
        Color(red: 0.95, green: 0.61, blue: 0.22),  // amber
        Color(red: 0.38, green: 0.73, blue: 0.49),  // sage green
        Color(red: 0.83, green: 0.37, blue: 0.37),  // coral
        Color(red: 0.63, green: 0.48, blue: 0.80),  // lavender
        Color(red: 0.90, green: 0.80, blue: 0.28),  // gold
        Color(red: 0.43, green: 0.72, blue: 0.82),  // sky
        Color(red: 0.78, green: 0.55, blue: 0.40),  // terracotta
    ]

    /// Stable color index per unique pieceId (by order of first appearance).
    private var colorMap: [UUID: Int] {
        var map: [UUID: Int] = [:]
        var counter = 0
        for p in layout.placements {
            if map[p.pieceId] == nil {
                map[p.pieceId] = counter % Self.palette.count
                counter += 1
            }
        }
        return map
    }

    private var baseColor: Color { Color(hex: layout.materialColorHex) }
    private var preset: MaterialColorPreset? { MaterialColorPreset.preset(for: layout.materialColorHex) }

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width  / layout.sheetWidth
            let scaleY = size.height / layout.sheetHeight
            let scale  = min(scaleX, scaleY)

            let drawW = layout.sheetWidth  * scale
            let drawH = layout.sheetHeight * scale
            let sheetRect = CGRect(x: 0, y: 0, width: drawW, height: drawH)

            // ── 1. Sheet background ──────────────────────────────────────────
            context.fill(Path(sheetRect), with: .color(baseColor))

            // ── 2. Wood grain lines (only for preset wood types) ─────────────
            if let grainColor = preset?.grainColor {
                drawGrain(context: context, width: drawW, height: drawH, color: grainColor)
            }

            // ── 3. Sheet border ──────────────────────────────────────────────
            context.stroke(Path(sheetRect), with: .color(.primary.opacity(0.8)), lineWidth: 2)

            // ── 4. Placed pieces ─────────────────────────────────────────────
            let cMap = colorMap
            for placement in layout.placements {
                let rect = CGRect(
                    x: placement.x * scale,
                    y: placement.y * scale,
                    width:  placement.width  * scale,
                    height: placement.height * scale
                )
                let colorIdx    = cMap[placement.pieceId] ?? 0
                let fillColor   = Self.palette[colorIdx].opacity(0.78)
                let strokeColor = Self.palette[colorIdx]
                let piecePath = path(for: placement.pieceShape, in: rect)

                context.fill(piecePath, with: .color(fillColor))
                context.stroke(piecePath, with: .color(strokeColor), lineWidth: 1.5)

                // Label if the rectangle is large enough to read
                if rect.width >= 24 && rect.height >= 14 {
                    let fontSize = min(rect.height * 0.22, 12.0)
                    let labelText = placement.pieceShape == .rectangle
                        ? placement.pieceName
                        : "\(placement.pieceName)\n\(placement.pieceShape.rawValue)"
                    let label = Text(labelText)
                        .font(.system(size: max(fontSize, 7), weight: .medium))
                        .foregroundStyle(Color.primary)
                    context.draw(label, in: rect.insetBy(dx: 3, dy: 2))
                }
            }
        }
    }

    private func path(for shape: PieceShape, in rect: CGRect) -> Path {
        switch shape {
        case .rectangle:
            return Path(rect)
        case .triangle:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
            return path
        case .circle:
            return Path(ellipseIn: rect)
        case .semicircle:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.midX, y: rect.maxY),
                radius: rect.width / 2,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.closeSubpath()
            return path
        case .quarterCircle:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX, y: rect.maxY),
                radius: rect.width,
                startAngle: .degrees(0),
                endAngle: .degrees(-90),
                clockwise: true
            )
            path.closeSubpath()
            return path
        }
    }

    // MARK: - Grain drawing

    /// Draws deterministic wavy horizontal lines to simulate wood grain.
    /// Line count and waviness scale with the diagram size.
    private func drawGrain(context: GraphicsContext, width: CGFloat, height: CGFloat, color: Color) {
        let spacing: CGFloat = 3.5
        let lineCount = Int(height / spacing) + 1
        let segmentCount = max(Int(width / 8), 10)   // one vertex every ~8 pts

        for i in 0..<lineCount {
            let yBase = CGFloat(i) * spacing
            // Two slightly different amplitude/frequency per line for organic feel
            let amp    = CGFloat(0.55 + 0.25 * sin(Double(i) * 0.41))
            let freq   = 0.55 + 0.15 * sin(Double(i) * 0.17)
            let phase  = Double(i) * 1.3

            var path = Path()
            path.move(to: CGPoint(x: 0, y: yBase))
            for s in 1...segmentCount {
                let x   = width * CGFloat(s) / CGFloat(segmentCount)
                let y   = yBase + amp * CGFloat(sin(Double(s) * freq + phase))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(color.opacity(0.30)), lineWidth: 0.55)
        }
    }
}

// MARK: - Preview

#Preview {
    let layout = SheetLayout(
        sheetIndex: 0,
        materialId: UUID(),
        materialName: "3/4\" Birch Ply",
        materialColorHex: "#E8D5A3",
        materialThickness: 0.75,
        materialType: .sheet,
        sheetWidth: 48, sheetHeight: 96,
        placements: [
            CutPlacement(pieceId: UUID(), pieceName: "Side Panel", pieceShape: .rectangle,
                         x: 0,    y: 0,    width: 11.25, height: 72,    sheetIndex: 0, rotated: false),
            CutPlacement(pieceId: UUID(), pieceName: "Shelf", pieceShape: .rectangle,
                         x: 11.5, y: 0,    width: 34.5,  height: 11.25, sheetIndex: 0, rotated: false),
            CutPlacement(pieceId: UUID(), pieceName: "Shelf", pieceShape: .rectangle,
                         x: 11.5, y: 11.5, width: 34.5,  height: 11.25, sheetIndex: 0, rotated: false),
            CutPlacement(pieceId: UUID(), pieceName: "Top/Bottom", pieceShape: .rectangle,
                         x: 11.5, y: 23,   width: 36,    height: 11.25, sheetIndex: 0, rotated: false),
        ]
    )
    CutDiagramView(layout: layout)
        .aspectRatio(48.0 / 96.0, contentMode: .fit)
        .padding()
        .background(Color(.systemBackground))
}
