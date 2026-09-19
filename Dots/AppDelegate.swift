import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var running: AppDelegate?

    private var panel: FloatingPanel?
    private var hostingView: DotsHostingView?

    static func main() {
        let delegate = AppDelegate()
        running = delegate
        NSApplication.shared.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installQuitMenu()

        let initialSize = DotsLayout.canvasSize
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        let hostingView = DotsHostingView(
            rootView: DotsView { [weak self] expansion in
                self?.handleExpansionChange(expansion)
            }
        )

        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel
        positionPanel()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screenConfigurationDidChange() {
        positionPanel()
    }

    private func handleExpansionChange(_ newExpansion: DotExpansion) {
        hostingView?.expansion = newExpansion

        guard let panel else { return }
        if newExpansion == .tasks {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak self] in
                self?.hostingView?.focusComposer()
            }
        } else if panel.isKeyWindow {
            panel.makeFirstResponder(nil)
            panel.resignKey()
        }
    }

    private func positionPanel() {
        guard let panel else { return }
        panel.setFrame(frameForPanel(), display: true)
    }

    private func frameForPanel() -> NSRect {
        let visibleFrame = (screenUnderPointer() ?? NSScreen.main)?.visibleFrame ?? .zero
        return DotsLayout.panelFrame(visibleFrame: visibleFrame)
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }

    private func installQuitMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            NSMenuItem(
                title: "Quit Dots",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }
}

enum DotsMenu {
    static func quitMenu() -> NSMenu {
        let menu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Dots",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class DotsHostingView: NSHostingView<DotsView> {
    var expansion: DotExpansion = .none

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var acceptsFirstResponder: Bool { expansion == .tasks }

    func composerField() -> NSTextField? {
        Self.findTextField(in: self)
    }

    func focusComposer() {
        guard let field = composerField(), let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let swiftPoint = isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
        guard DotsLayout.containsInteractiveContent(swiftPoint, expansion: expansion) else {
            return nil
        }

        if let field = composerField(), let superview = field.superview {
            let local = convert(point, to: superview)
            if let hit = field.hitTest(local) {
                return hit
            }
        }

        return super.hitTest(point)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        DotsMenu.quitMenu()
    }

    private static func findTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField {
            return field
        }
        for child in view.subviews {
            if let found = findTextField(in: child) {
                return found
            }
        }
        return nil
    }
}
