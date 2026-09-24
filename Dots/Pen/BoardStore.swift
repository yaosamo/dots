import Foundation

/// What's saved of the whiteboard: its strokes and shapes in world points, plus its pan.
/// `origin` is where the board's top-left sat in world points when saved, so a board saved on one
/// screen size lines up on another (items keep their place relative to the board's corner).
struct BoardDocument: Codable {
    var version = 1
    var origin: CGPoint
    var offset: CGSize
    var strokes: [InkModel.Stroke]
    var shapes: [InkModel.Shape]
    var updatedAt = Date()

    /// The same board with its items shifted so the board's corner sits at `origin`.
    func moved(to origin: CGPoint) -> BoardDocument {
        let delta = CGSize(width: origin.x - self.origin.x, height: origin.y - self.origin.y)
        guard delta != .zero else { return self }
        var moved = self
        moved.origin = origin
        moved.strokes = strokes.map { $0.offset(by: delta) }
        moved.shapes = shapes.map { $0.offset(by: delta) }
        return moved
    }
}

/// Keeps the whiteboard between pen sessions and launches, as JSON in Application Support.
/// One board for now; see docs/whiteboard-storage-plan.md for history, export and sharing.
@MainActor
final class BoardStore {
    private static let saveDelay: TimeInterval = 1

    private let fileURL: URL
    private var pending: BoardDocument?
    private var saveWork: DispatchWorkItem?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Dots/Boards", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("current.json")
    }

    func load() -> BoardDocument? {
        // A board from an incompatible format fails to decode; start empty rather than crash.
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(BoardDocument.self, from: data)
    }

    /// Saves once changes have settled for a second, so a drag writes once, not per point.
    func scheduleSave(_ document: BoardDocument) {
        pending = document
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    /// Writes any pending change now, e.g. when the pen closes.
    func flush() {
        saveWork?.cancel()
        saveWork = nil
        guard let document = pending else { return }
        pending = nil
        guard let data = try? JSONEncoder().encode(document) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
