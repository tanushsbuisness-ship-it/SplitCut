import Foundation
import SwiftData

/// SwiftData-backed implementation of ProjectRepository.
final class LocalProjectRepository: ProjectRepository {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func createProject(
        name: String,
        kerfWidth: Double = 0.125,
        trimMargin: Double = 0.0
    ) -> Project {
        let project = Project(name: name, kerfWidth: kerfWidth, trimMargin: trimMargin)
        context.insert(project)
        return project
    }

    func deleteProject(_ project: Project) {
        context.delete(project)
    }

    /// SwiftData auto-saves on context lifecycle events, but call this
    /// when you need an immediate, explicit save (e.g. before app termination).
    func saveChanges() throws {
        try context.save()
    }
}
