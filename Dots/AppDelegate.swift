    import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var running: AppDelegate?

    private var panel: FloatingPanel?
    private var rootView: LauncherRootView?
    private var statusItem: NSStatusItem?
    private var cameraOffset: CGSize = .zero
    private var homePanelFrame: NSRect?
    private var applicationBeforeTasks: NSRunningApplication?
    private let pointerState = LauncherPointerState()
    private let overlaySession = OverlaySession()
    private let toast = ToastController()

    static func main() {
        let delegate = AppDelegate()
        running = delegate
        NSApplication.shared.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        installAppMenu()

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
            rootView: DotsView(
                pointer: pointerState
            ) { [weak self] expansion, cameraOffset, taskCount in
                self?.handleExpansionChange(
                    expansion,
                    cameraOffset: cameraOffset,
                    taskCount: taskCount
                )
            }
        )
        let rootView = LauncherRootView(hostingView: hostingView)
        rootView.pointerState = pointerState

        panel.contentView = rootView
        panel.onCancel = { [weak self] in
            self?.pointerState.requestDismissal()
        }
        self.rootView = rootView
        self.panel = panel
        positionPanel()
        homePanelFrame = panel.frame
        rootView.captureHomeOrbs()
        panel.orderFrontRegardless()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == "q" {
                NSApp.terminate(nil)
                return nil
            }
            guard event.keyCode == 53 else { return event }
            self?.pointerState.requestDismissal()
            return nil
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlaySession.dismiss()
        toast.dismiss()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        NotificationCenter.default.removeObserver(self)
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Dots",
            .applicationVersion: "1.0",
        ])
    }

    @objc private func screenConfigurationDidChange() {
        positionPanel()
    }

    private func handleExpansionChange(
        _ newExpansion: DotExpansion,
        cameraOffset newOffset: CGSize,
        taskCount: Int
    ) {
        rootView?.taskCount = taskCount
        if newExpansion == .none {
            overlaySession.dismiss()
            restoreHomePanel()
        } else if newExpansion == .redPen || newExpansion == .screenToText {
            presentOverlay(newExpansion)
        } else {
            overlaySession.dismiss()
            if homePanelFrame == nil {
                homePanelFrame = panel?.frame
            }
            rootView?.expansion = newExpansion
            rootView?.cameraOffset = newOffset
            resizePanel(cameraOffset: newOffset)
            cameraOffset = newOffset
        }

        guard let panel else { return }

        if newExpansion == .tasks {
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                applicationBeforeTasks = frontmost
            }
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak self] in
                self?.rootView?.hostingView.focusComposer()
            }
        } else {
            if panel.isKeyWindow {
                panel.makeFirstResponder(nil)
                panel.resignKey()
            }
            restoreApplicationBeforeTasks()
        }
    }

    private func restoreApplicationBeforeTasks() {
        guard let application = applicationBeforeTasks else { return }
        applicationBeforeTasks = nil
        guard !application.isTerminated else { return }
        DispatchQueue.main.async {
            application.activate(options: [])
        }
    }

    private func presentOverlay(_ expansion: DotExpansion) {
        overlaySession.dismiss()
        rootView?.expansion = expansion
        rootView?.cameraOffset = .zero
        cameraOffset = .zero
        if let home = homePanelFrame {
            panel?.setFrame(home, display: true)
        }
        rootView?.layoutSubtreeIfNeeded()

        let screen = screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        switch expansion {
        case .redPen:
            let view = RedPenView(frame: screen.frame)
            view.onExit = { [weak self] in
                self?.pointerState.requestDismissal()
            }
            overlaySession.present(view, on: screen, canBecomeKey: true)
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        case .screenToText:
            let view = RegionSelectView(frame: screen.frame)
            view.onCancel = { [weak self] in
                self?.pointerState.requestDismissal()
            }
            view.onComplete = { [weak self] rect in
                self?.finishScreenToText(rect)
            }
            overlaySession.present(view, on: screen, canBecomeKey: true)
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        default:
            break
        }
    }

    private func finishScreenToText(_ screenRect: CGRect) {
        overlaySession.dismiss()
        pointerState.requestDismissal()
        Task { @MainActor in
            let screen = NSScreen.screens.first { $0.frame.intersects(screenRect) } ?? NSScreen.main
            if let text = await ScreenTextCapture.recognizeText(in: screenRect) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                if let screen {
                    toast.show("Copied", on: screen)
                }
            } else if let screen {
                toast.show("No text found", on: screen)
            }
        }
    }

    private func restoreHomePanel() {
        rootView?.expansion = .none
        rootView?.cameraOffset = .zero
        cameraOffset = .zero
        if let home = homePanelFrame {
            panel?.setFrame(home, display: true)
        } else {
            positionPanel()
            homePanelFrame = panel?.frame
        }
        rootView?.captureHomeOrbs()
    }

    private func resizePanel(cameraOffset newOffset: CGSize) {
        guard let panel else { return }
        let frame = DotsLayout.panelFrame(
            visibleFrame: (screenUnderPointer() ?? NSScreen.main)?.visibleFrame ?? .zero,
            cameraOffset: newOffset,
            previousCameraOffset: cameraOffset,
            keepingTopOf: panel.frame
        )
        panel.setFrame(frame, display: true)
    }

    private func positionPanel() {
        guard let panel else { return }
        panel.setFrame(frameForPanel(), display: true)
        if rootView?.expansion == DotExpansion.none || rootView == nil {
            homePanelFrame = panel.frame
            rootView?.captureHomeOrbs()
        }
    }

    private func frameForPanel() -> NSRect {
        let visibleFrame = (screenUnderPointer() ?? NSScreen.main)?.visibleFrame ?? .zero
        return DotsLayout.panelFrame(
            visibleFrame: visibleFrame,
            cameraOffset: cameraOffset
        )
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Dots"
        item.button?.toolTip = "Dots"
        item.menu = DotsMenu.quitMenu()
        statusItem = item
    }

    private func installAppMenu() {
        NSApp.mainMenu = DotsMenu.mainMenu()
    }
}

enum DotsMenu {
    static func mainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: "Dots", action: nil, keyEquivalent: "")
        appMenuItem.submenu = quitMenu()
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu()
        mainMenu.addItem(editMenuItem)

        return mainMenu
    }

    static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(editingItem(
            title: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        ))
        menu.addItem(.separator())
        menu.addItem(editingItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        ))
        menu.addItem(.separator())
        menu.addItem(editingItem(
            title: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        ))
        menu.addItem(editingItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        ))
        menu.addItem(editingItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        ))
        return menu
    }

    static func quitMenu() -> NSMenu {
        let menu = NSMenu()

        let about = NSMenuItem(
            title: "About Dots",
            action: #selector(AppDelegate.showAbout(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp.delegate
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Dots",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    private static func editingItem(
        title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: keyEquivalent
        )
        item.keyEquivalentModifierMask = [.command]
        item.target = nil
        return item
    }
}

private final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           let root = contentView as? LauncherRootView,
           root.handleClick(event) {
            return
        }
        super.sendEvent(event)
    }
}

final class DotOrbView: NSView {
    var id: DotID = .mirror
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = DotsLayout.nodeDiameter / 2
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        NSApp.activate(ignoringOtherApps: true)
        return DotsMenu.quitMenu()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

final class LauncherRootView: NSView {
    let hostingView: DotsHostingView
    var pointerState: LauncherPointerState? {
        didSet { hostingView.pointerState = pointerState }
    }
    var expansion: DotExpansion = .none {
        didSet {
            hostingView.expansion = expansion
            needsLayout = true
        }
    }
    var cameraOffset: CGSize = .zero {
        didSet {
            hostingView.cameraOffset = cameraOffset
            needsLayout = true
        }
    }
    var taskCount: Int = 0

    private var orbViews: [DotOrbView] = []
    private var homeOrbScreenOrigins: [CGPoint]?
    private var cameraDragStartScreen: CGPoint?
    private var cameraDragOriginOffset: CGSize = .zero
    private var cameraDidDrag = false

    init(hostingView: DotsHostingView) {
        self.hostingView = hostingView
        super.init(frame: .zero)
        addSubview(hostingView)
        hostingView.autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
        layoutOrbs()
    }

    override func mouseDown(with event: NSEvent) {
        if beginCameraDrag(event) { return }
        if handleClick(event) { return }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if updateCameraDrag(event) { return }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if endCameraDrag(event) { return }
        super.mouseUp(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for orb in orbViews where orb.frame.contains(point) {
            return orb
        }

        let swift = swiftPoint(point)
        if DotsLayout.dotID(
            at: swift,
            expansion: expansion,
            cameraOffset: cameraOffset
        ) != nil {
            return self
        }

        if expansion == .camera,
           DotsLayout.containsInteractiveContent(
            swift,
            expansion: expansion,
            cameraOffset: cameraOffset,
            taskCount: taskCount
           ) {
            return self
        }

        if DotsLayout.containsInteractiveContent(
            swift,
            expansion: expansion,
            cameraOffset: cameraOffset,
            taskCount: taskCount
        ) {
            let hosted = convert(point, to: hostingView)
            return hostingView.hitTest(hosted) ?? hostingView
        }

        return nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        NSApp.activate(ignoringOtherApps: true)
        return DotsMenu.quitMenu()
    }

    @discardableResult
    func handleClick(_ event: NSEvent) -> Bool {
        let local = convert(event.locationInWindow, from: nil)
        if let orb = orbViews.first(where: { $0.frame.contains(local) }) {
            pointerState?.requestActivation(of: orb.id)
            return true
        }
        let swift = swiftPoint(for: event)
        guard let id = DotsLayout.dotID(
            at: swift,
            expansion: expansion,
            cameraOffset: .zero
        ) else {
            return false
        }
        pointerState?.requestActivation(of: id)
        return true
    }

    private func isOnHangingCamera(_ swift: CGPoint) -> Bool {
        expansion == .camera
            && DotsLayout.dotID(
                at: swift,
                expansion: expansion,
                cameraOffset: cameraOffset
            ) == nil
            && DotsLayout.containsInteractiveContent(
                swift,
                expansion: expansion,
                cameraOffset: cameraOffset,
                taskCount: taskCount
            )
    }

    private func beginCameraDrag(_ event: NSEvent) -> Bool {
        let swift = swiftPoint(for: event)
        guard isOnHangingCamera(swift) else { return false }
        cameraDragStartScreen = NSEvent.mouseLocation
        cameraDragOriginOffset = pointerState?.cameraOffset ?? cameraOffset
        cameraDidDrag = false
        return true
    }

    private func updateCameraDrag(_ event: NSEvent) -> Bool {
        guard let start = cameraDragStartScreen else { return false }
        let screen = NSEvent.mouseLocation
        let dx = screen.x - start.x
        let dy = start.y - screen.y
        if hypot(dx, dy) >= 4 {
            cameraDidDrag = true
        }
        pointerState?.setCameraOffset(
            CGSize(
                width: cameraDragOriginOffset.width + dx,
                height: cameraDragOriginOffset.height + dy
            )
        )
        return true
    }

    private func endCameraDrag(_ event: NSEvent) -> Bool {
        guard cameraDragStartScreen != nil else { return false }
        if !cameraDidDrag {
            pointerState?.requestActivation(of: .mirror)
        }
        cameraDragStartScreen = nil
        cameraDidDrag = false
        return true
    }

    func captureHomeOrbs() {
        homeOrbScreenOrigins = nil
        layoutOrbs()
        guard let window else { return }
        homeOrbScreenOrigins = orbViews.map { orb in
            window.convertToScreen(CGRect(origin: orb.frame.origin, size: .zero)).origin
        }
    }

    private func layoutOrbs() {
        let ids = DotRegistry.visibleIDs(from: DotRegistry.defaultActiveIDs)
        let frames = DotsLayout.nodeFrames(
            expansion: .none,
            cameraOffset: .zero,
            dotIDs: ids
        )

        while orbViews.count < ids.count {
            let orb = DotOrbView(frame: .zero)
            addSubview(orb)
            orbViews.append(orb)
        }
        while orbViews.count > ids.count {
            orbViews.removeLast().removeFromSuperview()
        }

        for index in ids.indices {
            let orb = orbViews[index]
            let docked = appKitRect(from: frames[index])
            if let homes = homeOrbScreenOrigins,
               let window,
               index < homes.count {
                let placed = window.convertFromScreen(
                    CGRect(origin: homes[index], size: docked.size)
                )
                orb.frame = CGRect(origin: placed.origin, size: docked.size)
            } else {
                orb.frame = docked
            }
            orb.layer?.contentsScale = window?.backingScaleFactor ?? 2
            orb.layer?.cornerRadius = orb.frame.height / 2
            orb.layer?.backgroundColor = NSColor.black.cgColor
            orb.id = ids[index]
            orb.onClick = { [weak self] in
                self?.pointerState?.requestActivation(of: ids[index])
            }
            switch ids[index] {
            case .mirror:
                orb.setAccessibilityLabel(expansion == .camera ? "Close Mirror" : "Open Mirror")
            case .tasks:
                orb.setAccessibilityLabel(expansion == .tasks ? "Close Tasks" : "Open Tasks")
            case .redPen:
                orb.setAccessibilityLabel(expansion == .redPen ? "Close Red Pen" : "Open Red Pen")
            case .screenToText:
                orb.setAccessibilityLabel("Copy screen text")
            case .clipboard:
                orb.setAccessibilityLabel(expansion == .clipboard ? "Close Clipboard" : "Open Clipboard")
            }
        }
    }

    private func swiftPoint(for event: NSEvent) -> CGPoint {
        swiftPoint(convert(event.locationInWindow, from: nil))
    }

    private func swiftPoint(_ appKit: CGPoint) -> CGPoint {
        isFlipped ? appKit : CGPoint(x: appKit.x, y: bounds.height - appKit.y)
    }

    private func appKitRect(from swift: CGRect) -> CGRect {
        guard !isFlipped else { return swift }
        return CGRect(
            x: swift.minX,
            y: bounds.height - swift.maxY,
            width: swift.width,
            height: swift.height
        )
    }
}

final class DotsHostingView: NSHostingView<DotsView> {
    var expansion: DotExpansion = .none
    var cameraOffset: CGSize = .zero
    var pointerState: LauncherPointerState?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { expansion == .tasks }

    override func menu(for event: NSEvent) -> NSMenu? {
        NSApp.activate(ignoringOtherApps: true)
        return DotsMenu.quitMenu()
    }

    func composerField() -> NSTextField? {
        Self.findTextField(in: self)
    }

    func focusComposer() {
        guard let field = composerField(), let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let field = composerField(), let superview = field.superview {
            let local = convert(point, to: superview)
            if let hit = field.hitTest(local) {
                return hit
            }
        }
        return super.hitTest(point)
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
