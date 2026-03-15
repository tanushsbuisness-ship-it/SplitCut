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
    /// Also records cuts on scrap items for visual tracking.
    func optimize(using scrapItems: [ScrapItem], context: ModelContext) {
        guard !project.materials.isEmpty, !project.pieces.isEmpty else { return }
        isOptimizing = true
        cutPlan = CutOptimizer.optimize(project: project, scrapItems: scrapItems)
        
        // Record cuts on the scrap items
        if let plan = cutPlan {
            recordCutsOnScrapItems(plan: plan, scrapItems: scrapItems, context: context)
        }
        
        isOptimizing = false
    }
    
    /// Records all cuts made on scrap items so they show up in the scrap bin
    private func recordCutsOnScrapItems(plan: CutPlan, scrapItems: [ScrapItem], context: ModelContext) {
        // Group scrap usages by scrap ID
        let usagesByScrapId = Dictionary(grouping: plan.scrapUsages, by: { $0.scrapId })
        
        for (scrapId, usages) in usagesByScrapId {
            // Find the scrap item in our list
            guard let scrapItem = scrapItems.first(where: { $0.id == scrapId }) else {
                continue
            }
            
            // Add all cuts to this scrap item
            // Important: The optimizer already calculated the cumulative free rects
            // The last usage in the list will have the final state after all cuts
            for usage in usages {
                let cut = usage.toScrapCut()
                // Use the free rects from this specific usage (they're cumulative)
                scrapItem.addCut(cut, updatedFreeRects: usage.updatedFreeRects)
            }
            
            // Sync to Firebase
            FirebaseSyncService.shared.syncScrap(scrapItem)
        }
    }
}
