import Foundation

struct DotTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var isDone: Bool
}

final class TaskStore: ObservableObject {
    @Published private(set) var items: [DotTask]
    @Published var draft: String = ""

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.yaosamo.Dots.tasks"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.items = Self.load(from: defaults, key: storageKey)
    }

    @discardableResult
    func add(_ title: String) -> DotTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let item = DotTask(id: UUID(), title: trimmed, isDone: false)
        items.append(item)
        persist()
        return item
    }

    func addDraft() {
        guard add(draft) != nil else { return }
        draft = ""
    }

    func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
        persist()
    }

    func remove(_ id: UUID) {
        let before = items.count
        items.removeAll { $0.id == id }
        guard items.count != before else { return }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [DotTask] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([DotTask].self, from: data)) ?? []
    }
}
