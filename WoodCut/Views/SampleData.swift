import Foundation
import SwiftData

/// Provides an in-memory ModelContainer pre-populated with sample data for Xcode Previews.
@MainActor
enum SampleData {

    static var previewContainer: ModelContainer = {
        let schema = Schema([Project.self, MaterialItem.self, RequiredPiece.self, ScrapItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        insertBookshelfProject(into: container.mainContext)
        return container
    }()

    // MARK: - Sample projects

    static func insertBookshelfProject(into context: ModelContext) {
        let p = Project(name: "Bookshelf", kerfWidth: 0.125, trimMargin: 0)
        context.insert(p)

        let ply = MaterialItem(
            name: "3/4\" Birch Ply",
            width: 48, height: 96,
            quantity: 2, thickness: 0.75,
            materialType: .sheet,
            colorHex: "#E8D5A3"     // birch
        )
        context.insert(ply)
        p.materials.append(ply)

        let pieceDefs: [(String, Double, Double, Int)] = [
            ("Side Panel",  11.25, 72,    2),
            ("Shelf",       34.5,  11.25, 4),
            ("Top/Bottom",  36,    11.25, 2),
            ("Back Panel",  36,    60,    1),
        ]
        for (name, w, h, qty) in pieceDefs {
            let piece = RequiredPiece(
                name: name, width: w, height: h, quantity: qty,
                thickness: 0.75,
                materialType: .sheet,
                colorHex: "#E8D5A3",
                shape: .rectangle,
                rotationAllowed: true, grainDirectionLocked: false
            )
            context.insert(piece)
            p.pieces.append(piece)
        }
    }

    /// Fetch the first project in the preview container (for previews that need a Project).
    static var sampleProject: Project {
        let ctx = previewContainer.mainContext
        let all = (try? ctx.fetch(FetchDescriptor<Project>())) ?? []
        return all.first!
    }
}
