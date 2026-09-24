import AppKit

/// Covers every screen with a transparent canvas and turns the cursor into a pen of the chosen brush.
@MainActor
final class PenController: DotFeature {
    private let onVisibilityChange: (Bool) -> Void
    private let brushes = BrushState()
    private let boardStore = BoardStore()
    private var panels: [FloatingPanel] = []
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
            // A nearly invisible fill plus an explicit `false` keeps clicks from falling through.
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.001)
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
        onVisibilityChange(true)
    }

    func saveBoard() {
        panels.forEach { ($0.contentView as? PenCanvasView)?.saveBoard() }
    }

    func hide() {
        guard isVisible else { return }
        saveBoard()
        panels.forEach { $0.orderOut(nil) }
        panels = []
        NSCursor.arrow.set()
        previousApp?.activate()
        previousApp = nil
        onVisibilityChange(false)
    }
}
