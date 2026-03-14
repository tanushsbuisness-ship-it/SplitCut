import Foundation
import SwiftData
import Observation

@Observable
final class ProjectsViewModel {

    func addProject(name: String, context: ModelContext) {
        let repo = LocalProjectRepository(context: context)
        let project = repo.createProject(name: name.isEmpty ? "Untitled" : name)
        FirebaseSyncService.shared.syncProject(project)
    }

    func deleteProjects(at offsets: IndexSet, from projects: [Project], context: ModelContext) {
        let repo = LocalProjectRepository(context: context)
        for offset in offsets {
            FirebaseSyncService.shared.deleteProject(id: projects[offset].id)
            repo.deleteProject(projects[offset])
        }
    }
}
