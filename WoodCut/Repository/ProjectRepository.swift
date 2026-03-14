import Foundation
import SwiftData

/// Abstraction over project persistence.
/// Conforming to this protocol allows swapping LocalProjectRepository
/// for a cloud-backed implementation without touching ViewModels.
protocol ProjectRepository {
    func createProject(name: String, kerfWidth: Double, trimMargin: Double) -> Project
    func deleteProject(_ project: Project)
    func saveChanges() throws
}
