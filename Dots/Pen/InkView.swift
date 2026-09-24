import SwiftUI

/// What's drawn on one screen, in top-left-origin points: brush strokes plus whiteboard shapes.
/// Every change takes a snapshot first, so ⌘Z undoes drawing, moving, erasing and clearing alike.
@MainActor
final class InkModel: ObservableObject {
    struct Stroke: Identifiable {
        let id = UUID()
        let brush: Brush
        /// What the stroke Canvas paints: the brush's ink, or the board color for the marker.
        /// Shader brushes only read its alpha.
        let color: Color
        var points: [CGPoint]
        /// Kept up to date as points arrive, so layers can be sized without rescanning points.
        var bounds: CGRect
        var isFinished = false
    }

    struct Shape: Identifiable {
        enum Kind { case rectangle, ellipse, arrow, line, text }

        let id = UUID()
        let kind: Kind
        var start: CGPoint
        var end: CGPoint
        var color: BoardColor
        var text = ""

        var bounds: CGRect {
            kind == .text ? CGRect(origin: start, size: BoardText.size(of: text)) : CGRect(start: start, end: end)
        }
    }

    private struct Snapshot {
        let strokes: [Stroke]
        let shapes: [Shape]
    }

    /// Mouse events arrive far faster than needed; closer samples add cost, not detail.
    private static let minPointSpacing: CGFloat = 1
    /// A spotlight smaller than this (a click, a flick) is dropped instead of dimming the screen.
    private static let minSpotlightSize: CGFloat = 12
    /// A shape smaller than this was a click, not a drag.
    private static let minShapeSize: CGFloat = 4
    /// How close a click or the eraser has to come to count as touching something.
    private static let hitTolerance: CGFloat = 8

    @Published private(set) var strokes: [Stroke] = []
    @Published private(set) var shapes: [Shape] = []
    @Published var selectedID: UUID?
    /// Shader brushes animate against this.
    let startDate = Date()
    private var isDrawing = false
    private var isDrawingShape = false
    private var history: [Snapshot] = []
    private var didErase = false

    /// One layer per brush, so each shader runs once over all of its strokes.
    var brushesInUse: [Brush] {
        Brush.allCases.filter { brush in !brush.isSpotlight && strokes.contains { $0.brush == brush } }
    }

    var finishedSpotlights: [Stroke] {
        strokes.filter { $0.brush.isSpotlight && $0.isFinished }
    }

    /// The spotlight outline being drawn right now, if any.
    var drawingSpotlight: Stroke? {
        guard isDrawing, let last = strokes.last, last.brush.isSpotlight else { return nil }
        return last
    }

    var selectedBounds: CGRect? {
        guard let selectedID else { return nil }
        return shapes.first { $0.id == selectedID }?.bounds ?? strokes.first { $0.id == selectedID }?.bounds
    }

    // MARK: Strokes

    func begin(at point: CGPoint, brush: Brush, color: Color) {
        checkpoint()
        strokes.append(Stroke(brush: brush, color: color, points: [point], bounds: CGRect(origin: point, size: .zero)))
        isDrawing = true
    }

    func extend(to point: CGPoint) {
        guard isDrawing, let last = strokes.last?.points.last,
              hypot(point.x - last.x, point.y - last.y) >= Self.minPointSpacing else { return }
        let index = strokes.count - 1
        strokes[index].points.append(point)
        strokes[index].bounds = strokes[index].bounds.union(CGRect(origin: point, size: .zero))
    }

    func end() {
        guard isDrawing, let last = strokes.last else { return }
        isDrawing = false
        if last.brush.isSpotlight,
           max(last.bounds.width, last.bounds.height) < Self.minSpotlightSize {
            strokes.removeLast()
            history.removeLast()
            return
        }
        strokes[strokes.count - 1].isFinished = true
    }

    // MARK: Shapes

    func beginShape(_ kind: Shape.Kind, at point: CGPoint, color: BoardColor) {
        checkpoint()
        shapes.append(Shape(kind: kind, start: point, end: point, color: color))
        isDrawingShape = true
    }

    func updateShape(to point: CGPoint) {
        guard isDrawingShape, !shapes.isEmpty else { return }
        shapes[shapes.count - 1].end = point
    }

    func endShape() {
        guard isDrawingShape, let last = shapes.last else { return }
        isDrawingShape = false
        if hypot(last.end.x - last.start.x, last.end.y - last.start.y) < Self.minShapeSize {
            shapes.removeLast()
            history.removeLast()
        }
    }

    func addText(_ text: String, at origin: CGPoint, color: BoardColor) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        checkpoint()
        shapes.append(Shape(kind: .text, start: origin, end: origin, color: color, text: text))
    }

    // MARK: Selecting, moving, erasing

    /// The topmost stroke or shape under `point`. Strokes draw above shapes, so they're checked first.
    func item(at point: CGPoint) -> UUID? {
        if let stroke = strokes.last(where: { !$0.brush.isSpotlight && hits($0, point) }) { return stroke.id }
        return shapes.last { hits($0, point, outlineOnly: false) }?.id
    }

    func beginMove() {
        checkpoint()
    }

    /// The point that snaps to the grid when an item moves: a shape's start, a stroke's top-left.
    func anchor(of id: UUID) -> CGPoint? {
        shapes.first { $0.id == id }?.start ?? strokes.first { $0.id == id }?.bounds.origin
    }

    func move(_ id: UUID, by delta: CGSize) {
        if let index = shapes.firstIndex(where: { $0.id == id }) {
            shapes[index].start = shapes[index].start.offset(by: delta)
            shapes[index].end = shapes[index].end.offset(by: delta)
        } else if let index = strokes.firstIndex(where: { $0.id == id }) {
            strokes[index].points = strokes[index].points.map { $0.offset(by: delta) }
            strokes[index].bounds = strokes[index].bounds.offsetBy(dx: delta.width, dy: delta.height)
        }
    }

    func recolor(_ id: UUID, to color: BoardColor) {
        guard let index = shapes.firstIndex(where: { $0.id == id }), shapes[index].color != color else { return }
        checkpoint()
        shapes[index].color = color
    }

    func beginErasing() {
        checkpoint()
        didErase = false
    }

    /// Removes whatever the eraser touches. Shapes only erase from their outline, as in Excalidraw.
    func erase(at point: CGPoint) {
        let strokeCount = strokes.count, shapeCount = shapes.count
        strokes.removeAll { hits($0, point) }
        shapes.removeAll { hits($0, point, outlineOnly: true) }
        if strokes.count != strokeCount || shapes.count != shapeCount {
            didErase = true
            dropMissingSelection()
        }
    }

    func endErasing() {
        if !didErase { history.removeLast() }
    }

    func deleteSelected() {
        guard let selectedID else { return }
        checkpoint()
        strokes.removeAll { $0.id == selectedID }
        shapes.removeAll { $0.id == selectedID }
        self.selectedID = nil
    }

    // MARK: History

    func undo() {
        guard let snapshot = history.popLast() else { return }
        strokes = snapshot.strokes
        shapes = snapshot.shapes
        isDrawing = false
        isDrawingShape = false
        dropMissingSelection()
    }

    func clear() {
        guard !strokes.isEmpty || !shapes.isEmpty else { return }
        checkpoint()
        strokes.removeAll()
        shapes.removeAll()
        isDrawing = false
        isDrawingShape = false
        selectedID = nil
    }

    private func checkpoint() {
        history.append(Snapshot(strokes: strokes, shapes: shapes))
    }

    private func dropMissingSelection() {
        guard let id = selectedID else { return }
        if !strokes.contains(where: { $0.id == id }) && !shapes.contains(where: { $0.id == id }) { selectedID = nil }
    }

    // MARK: Hit testing

    private func hits(_ stroke: Stroke, _ point: CGPoint) -> Bool {
        let reach = Self.hitTolerance + stroke.brush.lineWidth / 2
        guard stroke.bounds.insetBy(dx: -reach, dy: -reach).contains(point) else { return false }
        return stroke.points.contains { hypot($0.x - point.x, $0.y - point.y) <= reach }
    }

    private func hits(_ shape: Shape, _ point: CGPoint, outlineOnly: Bool) -> Bool {
        let tolerance = Self.hitTolerance
        let rect = shape.bounds
        switch shape.kind {
        case .text:
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .line, .arrow:
            return point.distance(toSegmentFrom: shape.start, to: shape.end) <= tolerance
        case .rectangle:
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            guard outer.contains(point) else { return false }
            return !outlineOnly || !rect.insetBy(dx: tolerance, dy: tolerance).contains(point)
        case .ellipse:
            let radius = CGSize(width: max(rect.width / 2, 1), height: max(rect.height / 2, 1))
            let dx = (point.x - rect.midX) / radius.width, dy = (point.y - rect.midY) / radius.height
            // Distance from the outline, roughly in points.
            let distance = (sqrt(dx * dx + dy * dy) - 1) * min(radius.width, radius.height)
            return outlineOnly ? abs(distance) <= tolerance : distance <= tolerance
        }
    }
}

extension CGPoint {
    func offset(by delta: CGSize) -> CGPoint {
        CGPoint(x: x + delta.width, y: y + delta.height)
    }

    func distance(toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let segment = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = segment.x * segment.x + segment.y * segment.y
        guard lengthSquared > 0 else { return hypot(x - start.x, y - start.y) }
        let t = max(0, min(1, ((x - start.x) * segment.x + (y - start.y) * segment.y) / lengthSquared))
        return hypot(x - (start.x + t * segment.x), y - (start.y + t * segment.y))
    }
}

struct InkView: View {
    /// Excalidraw's selection color.
    private static let selectionColor = Color(red: 0x69 / 255, green: 0x65 / 255, blue: 0xdb / 255)

    @ObservedObject var ink: InkModel
    @ObservedObject var brushes: BrushState
    @ObservedObject private var tuning = ShaderTuning.shared

    var body: some View {
        ZStack {
            Whiteboard(isShown: brushes.showsWhiteboard)
            // Outside the timeline: the dim only changes when a spotlight is added or removed.
            SpotlightLayer(spotlights: ink.finishedSpotlights)
                .equatable()
            ShapeLayer(shapes: ink.shapes)
            strokes
            selection
        }
        .ignoresSafeArea()
    }

    private var strokes: some View {
        // Shader brushes move, so tick every frame while one is on screen. Plain ink holds still.
        TimelineView(.animation(paused: ink.brushesInUse.allSatisfy { $0 == .ink })) { timeline in
            let time = timeline.date.timeIntervalSince(ink.startDate)
            ZStack {
                ForEach(ink.brushesInUse) { brush in
                    let strokes = ink.strokes.filter { $0.brush == brush }
                    // Each layer covers only its strokes plus room for the glow, not the whole
                    // (5K) screen: full-screen offscreen layers per brush cost hundreds of MB.
                    let area = strokes.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
                        .insetBy(dx: -brush.layerMargin(tuning.values).width, dy: -brush.layerMargin(tuning.values).height)
                    StrokeLayer(strokes: strokes, brush: brush, origin: area.origin)
                        .frame(width: area.width, height: area.height)
                        .brushEffect(brush, time: Float(time), origin: area.origin, tuning: tuning.values)
                        .position(x: area.midX, y: area.midY)
                }
                // Thin frame so it's obvious the screen is in drawing mode.
                Rectangle()
                    .strokeBorder(Color(nsColor: brushes.brush.accent).opacity(0.45), lineWidth: 3)
            }
        }
        .overlay {
            // Marching-ants outline while a spotlight is being drawn.
            if let stroke = ink.drawingSpotlight {
                StrokeLayer.path(for: stroke.points)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: Brush.spotlight.lineWidth,
                                                                   lineCap: .round, dash: [6, 5]))
                    .shadow(color: .black.opacity(0.5), radius: 1)
            }
        }
    }

    @ViewBuilder
    private var selection: some View {
        if let bounds = ink.selectedBounds?.insetBy(dx: -8, dy: -8) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Self.selectionColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: bounds.width, height: bounds.height)
                .position(x: bounds.midX, y: bounds.midY)
                .allowsHitTesting(false)
        }
    }
}

/// Optional white drawing surface centred on the screen, 80% of its size, with a dot grid.
/// Ink draws on top.
struct Whiteboard: View {
    static let scale: CGFloat = 0.8

    let isShown: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = CGSize(width: geometry.size.width * Self.scale, height: geometry.size.height * Self.scale)
            let board = CGRect(x: (geometry.size.width - size.width) / 2, y: (geometry.size.height - size.height) / 2,
                               width: size.width, height: size.height)
            let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
            shape
                .fill(.white)
                .shadow(color: .black.opacity(0.3), radius: 40, y: 12)
                .overlay {
                    BoardGrid.dots(in: board.insetBy(dx: 12, dy: 12))
                        .offset(x: 12, y: 12)
                        .fill(Color.black.opacity(0.16))
                }
                .clipShape(shape)
                .frame(width: size.width, height: size.height)
                .position(x: board.midX, y: board.midY)
        }
        .opacity(isShown ? 1 : 0)
        .scaleEffect(isShown ? 1 : 0.96)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: isShown)
        .allowsHitTesting(false)
    }
}

/// Dims the whole screen except inside the closed spotlight outlines. Overlapping spotlights merge.
/// Stays until undone or cleared; the dim fades in with the first spotlight and out with the last.
private struct SpotlightLayer: View, Equatable {
    static let dim = 0.55

    let spotlights: [InkModel.Stroke]

    /// Finished spotlights never change, so their ids say everything.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.spotlights.map(\.id) == rhs.spotlights.map(\.id)
    }

    var body: some View {
        let holes = spotlights
            .map { StrokeLayer.path(for: $0.points, closed: true) }
            .reduce(Path()) { $0.union($1) }
        ZStack {
            if !spotlights.isEmpty {
                ZStack {
                    SpotlightDim(holes: holes).fill(.black.opacity(Self.dim))
                    holes.stroke(.white.opacity(0.45), lineWidth: 1.5)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: spotlights.isEmpty)
        .allowsHitTesting(false)
    }
}

private struct SpotlightDim: Shape {
    let holes: Path

    func path(in rect: CGRect) -> Path {
        Path(rect).subtracting(holes)
    }
}

struct StrokeLayer: View {
    let strokes: [InkModel.Stroke]
    let brush: Brush
    /// Screen position of this layer's top-left corner.
    let origin: CGPoint

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: -origin.x, y: -origin.y)
            let style = StrokeStyle(lineWidth: brush.lineWidth, lineCap: .round, lineJoin: .round)
            for stroke in strokes {
                context.stroke(Self.path(for: stroke.points), with: .color(stroke.color), style: style)
            }
        }
    }

    /// Smooths the stroke by curving through midpoints between samples.
    static func path(for points: [CGPoint], closed: Bool = false) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: first) // a single click leaves a dot
            return path
        }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let point = points[index]
            path.addQuadCurve(to: CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2), control: previous)
        }
        path.addLine(to: points[points.count - 1])
        if closed { path.closeSubpath() }
        return path
    }
}
