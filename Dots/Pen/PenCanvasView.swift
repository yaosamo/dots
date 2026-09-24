import AppKit
import Combine

/// Handles mouse and keys for one screen. Ink is rendered by SwiftUI (InkView) in a click-through
/// subview, with the brush palette on the left and, while the whiteboard is up, its toolbar on top.
/// Esc deselects or exits, ⌘Z undoes, C clears, Delete removes the selection (or clears), 1–5 pick
/// a brush, W toggles the whiteboard, and on the whiteboard V P R O A L T E pick its tools.
final class PenCanvasView: NSView, NSTextFieldDelegate {
    var onExit: (() -> Void)?

    private let ink = InkModel()
    private let brushes: BrushState
    private let paletteHost: NSView
    private let boardHost: NSView
    private var stateObserver: AnyCancellable?
    private var lastBoardColor: BoardColor

    /// Where the select tool's drag began, where the dragged item's anchor was then,
    /// and whether it has moved anything yet.
    private var dragStart: CGPoint?
    private var anchorStart: CGPoint?
    private var hasMoved = false

    /// The text being typed with the text tool, and where it will land.
    private var textField: NSTextField?
    private var textOrigin = CGPoint.zero

    init(frame: NSRect, brushes: BrushState) {
        self.brushes = brushes
        lastBoardColor = brushes.boardColor
        paletteHost = FirstClickHostingView(rootView: BrushPalette(brushes: brushes))
        boardHost = FirstClickHostingView(rootView: BoardToolbar(brushes: brushes))
        super.init(frame: frame)

        let inkHost = PassthroughHostingView(rootView: InkView(ink: ink, brushes: brushes))
        inkHost.frame = bounds
        inkHost.autoresizingMask = [.width, .height]
        addSubview(inkHost)
        addSubview(paletteHost)
        addSubview(boardHost)
        boardHost.isHidden = !brushes.showsWhiteboard

        // objectWillChange fires before the new values are stored, so read them on the next pass.
        stateObserver = brushes.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.stateDidChange() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true } // match SwiftUI's top-left origin
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let palette = BrushPalette.size
        paletteHost.frame = NSRect(x: 32, y: bounds.midY - palette.height / 2,
                                   width: palette.width, height: palette.height)
        // Along the whiteboard's top edge, inside it.
        let board = BoardToolbar.size
        let boardTop = bounds.height * (1 - Whiteboard.scale) / 2
        boardHost.frame = NSRect(x: bounds.midX - board.width / 2, y: boardTop + 16,
                                 width: board.width, height: board.height)
    }

    private func stateDidChange() {
        boardHost.isHidden = !brushes.showsWhiteboard
        if brushes.boardTool != .select { ink.selectedID = nil }
        if brushes.boardColor != lastBoardColor {
            lastBoardColor = brushes.boardColor
            // As in Excalidraw, picking a color also recolors the selection and the text being typed.
            if let selected = ink.selectedID { ink.recolor(selected, to: brushes.boardColor) }
            textField?.textColor = brushes.boardColor.nsColor
        }
        if brushes.boardTool != .text { commitText() }
        // Cursor rects hold the old tool's cursor. Invalidate only here: doing it from
        // cursorUpdate re-triggers cursorUpdate, and AppKit throws after too many passes.
        window?.invalidateCursorRects(for: self)
        updateCursor()
    }

    // MARK: Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: PenCursor.cursor(for: brushes))
        addCursorRect(paletteHost.frame, cursor: .arrow)
        if !boardHost.isHidden { addCursorRect(boardHost.frame, cursor: .arrow) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeAlways, .cursorUpdate, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor() }
    override func mouseEntered(with event: NSEvent) { updateCursor() }
    override func mouseMoved(with event: NSEvent) { updateCursor() }

    /// Sets the cursor only — must not invalidate cursor rects (see stateDidChange).
    private func updateCursor() {
        let mouse = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        let overToolbar = mouse.map { paletteHost.frame.contains($0) || (!boardHost.isHidden && boardHost.frame.contains($0)) }
        if overToolbar == true {
            NSCursor.arrow.set()
        } else if textField.map({ $0.frame.contains(mouse ?? .zero) }) == true {
            NSCursor.iBeam.set()
        } else {
            PenCursor.cursor(for: brushes).set()
        }
    }

    // MARK: Mouse

    /// Grid snapping, unless ⌘ is held.
    private func snapped(_ point: CGPoint, _ event: NSEvent) -> CGPoint {
        event.modifierFlags.contains(.command) ? point : BoardGrid.snap(point)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        // A click away from the text being typed finishes it, and does nothing else.
        if textField != nil {
            commitText()
            return
        }
        window?.makeFirstResponder(self)
        let point = point(for: event)
        switch brushes.boardTool {
        case nil:
            ink.begin(at: point, brush: brushes.brush, color: brushes.brush.inkColor)
        case .marker:
            ink.begin(at: point, brush: .ink, color: brushes.boardColor.color)
        case .select:
            ink.selectedID = ink.item(at: point)
            dragStart = point
            anchorStart = ink.selectedID.flatMap(ink.anchor(of:))
            hasMoved = false
        case .eraser:
            ink.beginErasing()
            ink.erase(at: point)
        case .text:
            beginText(at: snapped(point, event))
        case .rectangle, .ellipse, .arrow, .line:
            if let kind = brushes.boardTool?.shapeKind {
                ink.beginShape(kind, at: snapped(point, event), color: brushes.boardColor)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = point(for: event)
        switch brushes.boardTool {
        case nil, .marker:
            ink.extend(to: point)
        case .select:
            guard let selected = ink.selectedID, let dragStart, let anchorStart,
                  let anchor = ink.anchor(of: selected) else { return }
            // The anchor follows the pointer from where it started, landing on grid dots.
            let target = snapped(CGPoint(x: anchorStart.x + point.x - dragStart.x,
                                         y: anchorStart.y + point.y - dragStart.y), event)
            guard target != anchor else { return }
            if !hasMoved {
                ink.beginMove()
                hasMoved = true
            }
            ink.move(selected, by: CGSize(width: target.x - anchor.x, height: target.y - anchor.y))
        case .eraser:
            ink.erase(at: point)
        case .text:
            break
        case .rectangle, .ellipse, .arrow, .line:
            // Shift's 15° lines win over the grid; squares and circles stay on it.
            let isAngled = ink.shapes.last.map { $0.kind == .line || $0.kind == .arrow } ?? false
            if event.modifierFlags.contains(.shift) {
                ink.updateShape(to: constrained(isAngled ? point : snapped(point, event)))
            } else {
                ink.updateShape(to: snapped(point, event))
            }
        }
        PenCursor.cursor(for: brushes).set()
    }

    override func mouseUp(with event: NSEvent) {
        switch brushes.boardTool {
        case nil, .marker: ink.end()
        case .select:
            dragStart = nil
            anchorStart = nil
        case .eraser: ink.endErasing()
        case .text: break
        case .rectangle, .ellipse, .arrow, .line: ink.endShape()
        }
    }

    /// Shift: squares and circles, and lines snapped to 15° steps.
    private func constrained(_ point: CGPoint) -> CGPoint {
        guard let shape = ink.shapes.last else { return point }
        let dx = point.x - shape.start.x, dy = point.y - shape.start.y
        switch shape.kind {
        case .rectangle, .ellipse:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: shape.start.x + (dx < 0 ? -side : side), y: shape.start.y + (dy < 0 ? -side : side))
        case .line, .arrow:
            let step = CGFloat.pi / 12
            let angle = (atan2(dy, dx) / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: shape.start.x + cos(angle) * length, y: shape.start.y + sin(angle) * length)
        case .text:
            return point
        }
    }

    // MARK: Text

    private func beginText(at point: CGPoint) {
        let lineHeight = BoardText.lineHeight
        let field = NSTextField(string: "")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = BoardText.nsFont
        field.textColor = brushes.boardColor.nsColor
        field.delegate = self
        // Centered on the click, like Excalidraw.
        field.frame = NSRect(x: point.x, y: point.y - lineHeight / 2, width: 600, height: lineHeight + 4)
        addSubview(field, positioned: .below, relativeTo: paletteHost)
        window?.makeFirstResponder(field)
        textField = field
        // The field's cell insets its text by 2pt.
        textOrigin = CGPoint(x: point.x + 2, y: point.y - lineHeight / 2)
    }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        field.removeFromSuperview()
        ink.addText(field.stringValue, at: textOrigin, color: brushes.boardColor)
        window?.makeFirstResponder(self)
    }

    /// Return and Esc finish the text instead of reaching the canvas (where Esc would exit).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:))
            || selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        commitText()
        return true
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let characters = event.charactersIgnoringModifiers?.lowercased()
        if event.keyCode == 53 { // Esc
            if ink.selectedID != nil {
                ink.selectedID = nil
            } else {
                onExit?()
            }
        } else if event.modifierFlags.contains(.command), characters == "z" {
            ink.undo()
        } else if characters == "\u{7f}" {
            if ink.selectedID != nil { ink.deleteSelected() } else { ink.clear() }
        } else if characters == "c" {
            ink.clear()
        } else if characters == "w" {
            brushes.showsWhiteboard.toggle()
        } else if let brush = Brush(digit: characters) {
            brushes.brush = brush
        } else if brushes.showsWhiteboard, let tool = BoardTool(key: characters) {
            brushes.boardTool = tool
        } else {
            super.keyDown(with: event)
        }
    }

    private func point(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }
}
