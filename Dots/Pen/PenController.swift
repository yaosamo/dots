import AppKit
import Combine

/// Covers every screen with a transparent canvas and turns the cursor into a pen of the chosen brush.
@MainActor
final class PenController: DotFeature {
    private let onVisibilityChange: (Bool) -> Void
    private let brushes = BrushState()
    private let boardStore = BoardStore()
    private var panels: [FloatingPanel] = []
    private var pointerObserver: AnyCancellable?
    /// Pointer mode's mouse-move monitors (global while the mouse is over other apps' windows).
    private var mouseMonitors: [Any] = []
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { !panels.isEmpty }

    init(onVisibilityChange: @escaping (Bool) -> Void) {
        self.onVisibilityChange = onVisibilityChange
    }

    func show() {
        guard !isVisible else { return }
        brushes.selectDefaultTool()
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost == .current ? nil : frontmost

        // The whiteboard lives on one screen: the one under the pointer as the pen opens.
        let boardScreen = NSScreen.underMouse
        panels = NSScreen.screens.map { screen in
            let panel = FloatingPanel(level: DotsLevel.pen, keyable: true)
            panel.backgroundColor = Self.background(isPointer: brushes.isPointer)
            panel.ignoresMouseEvents = false
            panel.setFrame(screen.frame, display: false)
            let canvas = PenCanvasView(frame: NSRect(origin: .zero, size: screen.frame.size), brushes: brushes,
                                       boardStore: screen == boardScreen ? boardStore : nil)
            canvas.onExit = { [weak self] in self?.hide() }
            panel.contentView = canvas
            panel.onCancel = { [weak self] in self?.hide() }
            panel.orderFrontRegardless()
            return panel
        }

        // Activating lets our cursor win over the app underneath.
        NSApp.activate()
        let mouseScreen = NSScreen.underMouse
        let target = panels.first { $0.screen == mouseScreen } ?? panels[0]
        target.makeKey()
        target.makeFirstResponder(target.contentView)
        PenCursor.cursor(for: brushes).set()
        // @Published emits before storing, so use the value passed in.
        pointerObserver = brushes.$isPointer.removeDuplicates().dropFirst().sink { [weak self] isPointer in
            MainActor.assumeIsolated { self?.setPointer(isPointer) }
        }
        onVisibilityChange(true)
    }

    private func setPointer(_ isPointer: Bool) {
        panels.forEach { $0.backgroundColor = Self.background(isPointer: isPointer) }
        guard !isPointer else {
            startPassThrough()
            return
        }
        stopPassThrough()
        // Back to drawing: take the keyboard and cursor back from whatever app was clicked.
        NSApp.activate()
        let target = panels.first { $0.screen == NSScreen.underMouse } ?? panels.first
        target?.makeKey()
        target?.makeFirstResponder(target?.contentView)
    }

    // MARK: Pointer mode pass-through

    /// A window that doesn't ignore mouse events takes every click, even on clear pixels. So in
    /// pointer mode each pen window ignores the mouse except while it's over a toolbar or the
    /// whiteboard, re-checked as the mouse moves.
    private func startPassThrough() {
        updatePassThrough()
        let update = { [weak self] in MainActor.assumeIsolated { self?.updatePassThrough() } }
        mouseMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { _ in update() },
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
                update()
                return event
            },
        ].compactMap { $0 }
    }

    private func stopPassThrough() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
        panels.forEach { $0.ignoresMouseEvents = false }
    }

    private func updatePassThrough() {
        let mouse = NSEvent.mouseLocation
        for panel in panels {
            guard let canvas = panel.contentView as? PenCanvasView else { continue }
            let point = canvas.convert(panel.convertPoint(fromScreen: mouse), from: nil)
            let takesClicks = canvas.isInteractive(at: point)
            if panel.ignoresMouseEvents == takesClicks { panel.ignoresMouseEvents = !takesClicks }
        }
    }

    /// A nearly invisible fill (with `ignoresMouseEvents` false) catches every click for drawing.
    /// Clear lets clicks on empty areas fall through to the apps below: pointer mode.
    private static func background(isPointer: Bool) -> NSColor {
        isPointer ? .clear : NSColor.black.withAlphaComponent(0.001)
    }

    func saveBoard() {
        panels.forEach { ($0.contentView as? PenCanvasView)?.saveBoard() }
    }

    func hide() {
        guard isVisible else { return }
        pointerObserver = nil
        stopPassThrough()
        saveBoard()
        panels.forEach { $0.orderOut(nil) }
        panels = []
        NSCursor.arrow.set()
        previousApp?.activate()
        previousApp = nil
        onVisibilityChange(false)
    }
}
