import Foundation

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
    var createdAt = Date()
}

/// Newest-first task stack, persisted as JSON in Application Support.
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = [] {
        didSet { save() }
    }

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Dots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("tasks.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([TaskItem].self, from: data) {
            tasks = saved
        }
    }

    var openCount: Int { tasks.filter { !$0.isDone }.count }
    var hasCompleted: Bool { tasks.contains(where: \.isDone) }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.insert(TaskItem(title: trimmed), at: 0)
    }

    func toggle(_ id: TaskItem.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isDone.toggle()
    }

    /// An empty title keeps the old one.
    func rename(_ id: TaskItem.ID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].title != trimmed else { return }
        tasks[index].title = trimmed
    }

    func delete(_ id: TaskItem.ID) {
        tasks.removeAll { $0.id == id }
    }

    func clearCompleted() {
        tasks.removeAll(where: \.isDone)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
