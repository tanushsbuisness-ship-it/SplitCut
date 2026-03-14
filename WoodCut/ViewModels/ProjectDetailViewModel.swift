import Foundation
import SwiftData
import Observation

@Observable
final class ProjectDetailViewModel {

    var project: Project
    var isOptimizing: Bool = false
    var cutPlan: CutPlan? = nil

    init(project: Project) {
        self.project = project
    }

    // MARK: - Materials

    func addMaterial(_ material: MaterialItem, context: ModelContext) {
        context.insert(material)
        project.materials.append(material)
        project.updatedAt = Date()
        FirebaseSyncService.shared.syncProject(project)
    }

    func deleteMaterials(at offsets: IndexSet, context: ModelContext) {
        let toDelete = offsets.map { project.materials[$0] }
        for item in toDelete {
            project.materials.removeAll { $0.id == item.id }
            context.delete(item)
        }
        project.updatedAt = Date()
        FirebaseSyncService.shared.syncProject(project)
    }

    // MARK: - Pieces

    func addPiece(_ piece: RequiredPiece, context: ModelContext) {
        context.insert(piece)
        project.pieces.append(piece)
        project.updatedAt = Date()
        FirebaseSyncService.shared.syncProject(project)
    }

    func deletePieces(at offsets: IndexSet, context: ModelContext) {
        let toDelete = offsets.map { project.pieces[$0] }
        for item in toDelete {
            project.pieces.removeAll { $0.id == item.id }
            context.delete(item)
        }
        project.updatedAt = Date()
        FirebaseSyncService.shared.syncProject(project)
    }

    // MARK: - Optimization

    /// Runs the optimizer synchronously. For typical woodworking projects
    /// (< 200 pieces) this completes in milliseconds on-device.
    func optimize(using scrapItems: [ScrapItem]) {
        guard !project.materials.isEmpty, !project.pieces.isEmpty else { return }
        isOptimizing = true
        cutPlan = CutOptimizer.optimize(project: project, scrapItems: scrapItems)
        isOptimizing = false
    }
}
