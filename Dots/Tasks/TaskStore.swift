import Foundation

/// Subtasks are one level deep and stored flat: a subtask belongs to the nearest task above it
/// that isn't one, so a task and its subtasks always sit together in the list.
struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
    var createdAt = Date()
    var isSubtask = false
    /// Tasks with subtasks only: the subtasks are folded away.
    var isCollapsed = false
}

extension TaskItem {
    private enum CodingKeys: String, CodingKey {
        case id, title, isDone, createdAt, isSubtask, isCollapsed
    }

    /// Lists saved before subtasks have no `isSubtask` or `isCollapsed`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isSubtask = try container.decodeIfPresent(Bool.self, forKey: .isSubtask) ?? false
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
    }
}

/// Newest-first task stack, persisted as JSON in Application Support.
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = [] {
        didSet { save() }
    }

    private let fileURL: URL
    /// Deleted tasks (each with its subtasks) and where they were, newest last, for ⌘Z.
    /// Kept while Dots runs.
    private var deleted: [(tasks: [TaskItem], index: Int)] = []
    private static let undoLimit = 50

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Dots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("tasks.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([TaskItem].self, from: data) {
            // An empty task is a new one that was still being typed when Dots quit.
            tasks = Self.promotingOrphans(saved.filter { !$0.title.isEmpty })
        }
    }

    var hasCompleted: Bool { tasks.contains(where: \.isDone) }

    func task(_ id: TaskItem.ID) -> TaskItem? {
        tasks.first { $0.id == id }
    }

    /// The rows on screen: collapsed tasks hide their subtasks, and so does a task being dragged
    /// (they travel with it). A dragged subtask always shows, even under a collapsed task.
    func visibleTasks(dragging dragged: TaskItem.ID? = nil) -> [TaskItem] {
        var visible: [TaskItem] = []
        var hidesSubtasks = false
        for task in tasks {
            if !task.isSubtask {
                hidesSubtasks = task.isCollapsed || task.id == dragged
                visible.append(task)
            } else if !hidesSubtasks || task.id == dragged {
                visible.append(task)
            }
        }
        return visible
    }

    /// How many subtasks each task with subtasks has.
    var subtaskCounts: [TaskItem.ID: Int] {
        var counts: [TaskItem.ID: Int] = [:]
        var parent: TaskItem.ID?
        for task in tasks {
            if !task.isSubtask {
                parent = task.id
            } else if let parent {
                counts[parent, default: 0] += 1
            }
        }
        return counts
    }

    func hasSubtasks(_ id: TaskItem.ID) -> Bool {
        guard let index = index(of: id) else { return false }
        return Self.family(at: index, in: tasks).count > 1
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.insert(TaskItem(title: trimmed), at: 0)
    }

    /// Return on a task: a new, empty task right after it, at its level. After a task with its
    /// subtasks showing, it's the first of them. It stays empty only while being typed into.
    func insertEmpty(after id: TaskItem.ID) -> TaskItem.ID? {
        guard let index = index(of: id) else { return nil }
        let anchor = tasks[index]
        let family = Self.family(at: index, in: tasks)
        var task = TaskItem(title: "")
        task.isSubtask = anchor.isSubtask || (!anchor.isCollapsed && family.count > 1)
        tasks.insert(task, at: task.isSubtask ? index + 1 : family.upperBound)
        return task.id
    }

    /// Checking a task checks its subtasks too; unchecking a subtask unchecks its task.
    func toggle(_ id: TaskItem.ID) {
        guard let index = index(of: id) else { return }
        var list = tasks
        let isDone = !list[index].isDone
        if list[index].isSubtask {
            list[index].isDone = isDone
            if !isDone, let parent = Self.parentIndex(of: index, in: list) { list[parent].isDone = false }
        } else if isDone {
            for member in Self.family(at: index, in: list) { list[member].isDone = true }
        } else {
            list[index].isDone = false
        }
        tasks = list
    }

    /// An empty title keeps the old one.
    func rename(_ id: TaskItem.ID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(of: id), tasks[index].title != trimmed else { return }
        tasks[index].title = trimmed
    }

    func setCollapsed(_ id: TaskItem.ID, _ isCollapsed: Bool) {
        guard let index = index(of: id), !tasks[index].isSubtask, tasks[index].isCollapsed != isCollapsed else { return }
        tasks[index].isCollapsed = isCollapsed
    }

    /// Tab: makes the task a subtask of the task above. Its own subtasks go with it, one level up.
    func indent(_ id: TaskItem.ID) {
        guard let index = index(of: id), index > 0, !tasks[index].isSubtask else { return }
        var list = tasks
        list[index].isSubtask = true
        list[index].isCollapsed = false
        if let parent = Self.parentIndex(of: index, in: list) { list[parent].isCollapsed = false }
        tasks = list
    }

    /// ⇧Tab: the subtask becomes a task where it is, and the subtasks below it become its own,
    /// the same as dragging it out to the left.
    func outdent(_ id: TaskItem.ID) {
        guard let index = index(of: id), tasks[index].isSubtask else { return }
        tasks[index].isSubtask = false
    }

    /// Drag and drop: puts `id` (with its subtasks) right after the row `anchor` shows as, or at the
    /// top when nil, as a subtask or a task. After a collapsed task means after its hidden subtasks.
    func place(_ id: TaskItem.ID, after anchor: TaskItem.ID?, asSubtask: Bool) {
        guard let index = index(of: id), anchor != id else { return }
        var list = tasks
        let range = Self.family(at: index, in: list)
        var moved = Array(list[range])
        list.removeSubrange(range)
        moved[0].isSubtask = asSubtask && anchor != nil
        if moved[0].isSubtask { moved[0].isCollapsed = false }

        var destination = 0
        if let anchor, let anchorIndex = list.firstIndex(where: { $0.id == anchor }) {
            let anchorTask = list[anchorIndex]
            destination = !anchorTask.isSubtask && anchorTask.isCollapsed
                ? Self.family(at: anchorIndex, in: list).upperBound
                : anchorIndex + 1
        }
        list.insert(contentsOf: moved, at: destination)
        if list != tasks { tasks = list }
    }

    /// After a drop: a subtask that landed under a collapsed task unfolds it.
    func reveal(_ id: TaskItem.ID) {
        guard let index = index(of: id), tasks[index].isSubtask,
              let parent = Self.parentIndex(of: index, in: tasks) else { return }
        setCollapsed(tasks[parent].id, false)
    }

    /// Deleting a task deletes its subtasks. `undoable`: ⌘Z can bring them back.
    func delete(_ id: TaskItem.ID, undoable: Bool = true) {
        guard let index = index(of: id) else { return }
        let family = Self.family(at: index, in: tasks)
        if undoable {
            deleted.append((Array(tasks[family]), family.lowerBound))
            if deleted.count > Self.undoLimit { deleted.removeFirst() }
        }
        var list = tasks
        list.removeSubrange(family)
        tasks = Self.promotingOrphans(list)
    }

    var canRestore: Bool { !deleted.isEmpty }

    /// ⌘Z: puts the last deleted task (and its subtasks) back where it was. Returns its id.
    func restoreDeleted() -> TaskItem.ID? {
        guard let last = deleted.popLast() else { return nil }
        var list = tasks
        list.insert(contentsOf: last.tasks, at: min(last.index, list.count))
        tasks = Self.promotingOrphans(list)
        return last.tasks.first?.id
    }

    func clearCompleted() {
        var kept: [TaskItem] = []
        var parentRemoved = false
        for var task in tasks {
            if !task.isSubtask { parentRemoved = task.isDone }
            if task.isDone { continue }
            // A subtask still open under a task that's cleared carries on as a task.
            if task.isSubtask && parentRemoved { task.isSubtask = false }
            kept.append(task)
        }
        tasks = kept
    }

    private func index(of id: TaskItem.ID) -> Int? {
        tasks.firstIndex { $0.id == id }
    }

    /// The task at `index` and its subtasks; just the one row for a subtask.
    private static func family(at index: Int, in list: [TaskItem]) -> Range<Int> {
        guard !list[index].isSubtask else { return index..<index + 1 }
        var end = index + 1
        while end < list.count, list[end].isSubtask { end += 1 }
        return index..<end
    }

    private static func parentIndex(of index: Int, in list: [TaskItem]) -> Int? {
        list[..<index].lastIndex { !$0.isSubtask }
    }

    /// Subtasks with no task above them become tasks.
    private static func promotingOrphans(_ list: [TaskItem]) -> [TaskItem] {
        var list = list
        for index in list.indices {
            guard list[index].isSubtask else { break }
            list[index].isSubtask = false
        }
        return list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
