import SwiftUI
import SwiftData

struct ProjectsView: View {
    let onSignOut: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    @State private var viewModel = ProjectsViewModel()
    @State private var showingAdd = false
    @State private var showingMonetization = false
    @State private var newName: String = ""

    init(onSignOut: (() -> Void)? = nil) {
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                if let onSignOut {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Sign Out", action: onSignOut)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !purchaseManager.hasRemovedAds {
                        Button {
                            showingMonetization = true
                        } label: {
                            Image(systemName: "crown")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingMonetization) {
                MonetizationView()
            }
            .sheet(isPresented: $showingAdd) {
                addProjectSheet
            }
        }
    }

    // MARK: - Subviews

    private var projectList: some View {
        List {
            ForEach(projects) { project in
                NavigationLink {
                    ProjectDetailView(project: project)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name).font(.body)
                        HStack(spacing: 6) {
                            Text("\(project.materials.count) material(s)")
                            Text("·")
                            Text("\(project.pieces.count) piece(s)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete { viewModel.deleteProjects(at: $0, from: projects, context: modelContext) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Projects", systemImage: "folder.badge.plus")
        } description: {
            Text("Tap the button below or the + at the top to create your first cut plan project.")
        } actions: {
            Button {
                showingAdd = true
            } label: {
                Label("New Project", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var addProjectSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $newName)
                } footer: {
                    Text("e.g. \"Bookshelf\", \"Cabinet Doors\", \"Workbench\"")
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newName = ""
                        showingAdd = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.addProject(name: newName, context: modelContext)
                        newName = ""
                        showingAdd = false
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    ProjectsView()
        .modelContainer(SampleData.previewContainer)
}
