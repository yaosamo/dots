import Foundation

struct DotTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var isDone: Bool
}

enum TaskSelectionDirection {
    case up
    case down
}

final class TaskStore: ObservableObject {
    @Published private(set) var items: [DotTask]
    @Published var draft: String = "" {
        didSet {
            if draft != oldValue {
                selectedTaskID = nil
            }
        }
    }
    @Published private(set) var editingTaskID: UUID? = nil
    @Published private(set) var selectedTaskID: UUID? = nil

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
        items.insert(item, at: items.startIndex)
        persist()
        return item
    }

    func addDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let editingTaskID,
           let index = items.firstIndex(where: { $0.id == editingTaskID }) {
            items[index].title = trimmed
            self.editingTaskID = nil
            persist()
            draft = ""
            return
        }

        guard add(trimmed) != nil else { return }
        draft = ""
    }

    var visibleItems: [DotTask] {
        items
    }

    @discardableResult
    func moveTaskSelection(_ direction: TaskSelectionDirection) -> Bool {
        guard editingTaskID == nil else { return false }

        let candidates = visibleItems
        guard !candidates.isEmpty else {
            selectedTaskID = nil
            return false
        }

        guard let selectedTaskID,
              let currentIndex = candidates.firstIndex(where: { $0.id == selectedTaskID })
        else {
            self.selectedTaskID = direction == .up ? candidates.last?.id : candidates.first?.id
            return true
        }

        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = max(candidates.startIndex, currentIndex - 1)
        case .down:
            nextIndex = min(candidates.index(before: candidates.endIndex), currentIndex + 1)
        }
        self.selectedTaskID = candidates[nextIndex].id
        return true
    }

    func clearTaskSelection() {
        selectedTaskID = nil
    }

    @discardableResult
    func editSelectedTask() -> Bool {
        guard let selectedTaskID,
              visibleItems.contains(where: { $0.id == selectedTaskID })
        else {
            self.selectedTaskID = nil
            return false
        }

        return editTask(selectedTaskID)
    }

    @discardableResult
    func editTask(_ id: UUID) -> Bool {
        guard let task = visibleItems.first(where: { $0.id == id }) else {
            return false
        }

        selectedTaskID = nil
        editingTaskID = task.id
        draft = task.title
        return true
    }

    @discardableResult
    func handleBackspaceOnEmptyDraft() -> Bool {
        guard draft.isEmpty else { return false }

        if let editingTaskID {
            self.editingTaskID = nil
            items.removeAll { $0.id == editingTaskID }
            persist()
            _ = recallPreviousTask()
            return true
        }

        return recallPreviousTask()
    }

    @discardableResult
    func handleBackspaceOnAddDraft() -> Bool {
        guard editingTaskID == nil else { return false }
        return recallPreviousTask()
    }

    private func recallPreviousTask() -> Bool {
        guard let previous = items.first else { return false }
        selectedTaskID = nil
        editingTaskID = previous.id
        draft = previous.title
        return true
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
        if editingTaskID == id {
            editingTaskID = nil
            draft = ""
        }
        if selectedTaskID == id {
            selectedTaskID = nil
        }
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
