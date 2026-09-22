import AppKit
import QuartzCore
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var running: AppDelegate?

    private var panel: FloatingPanel?
    private var rootView: LauncherRootView?
    private var statusItem: NSStatusItem?
    private var cameraPanel: CameraFloatingPanel?
    private var cameraResizeGeneration = 0
    private var cameraOffset: CGSize = .zero
    private var homePanelFrame: NSRect?
    private var applicationBeforeTasks: NSRunningApplication?
    private let pointerState = LauncherPointerState()
    private let dotAppearance = DotAppearanceSettings.shared
    private let cameraSession = CameraSession()
    private let cameraPanelModel = CameraPanelModel()
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
        rootView.dotMaterial = dotAppearance.material

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
        DispatchQueue.main.async {
            rootView.animateLaunchEntrance()
        }

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
        dismissCameraPanel()
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

    @objc func setDotMaterial(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let material = DotMaterialStyle(rawValue: rawValue) else {
            return
        }

        dotAppearance.material = material
        rootView?.dotMaterial = material
        statusItem?.menu = DotsMenu.quitMenu(material: material)
        NSApp.mainMenu = DotsMenu.mainMenu(material: material)
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
            dismissCameraPanel()
            rootView?.expansion = .none
            rootView?.cameraOffset = .zero
            restoreHomePanel()
        } else if newExpansion == .redPen || newExpansion == .screenToText {
            presentOverlay(newExpansion)
        } else if newExpansion == .camera {
            overlaySession.dismiss()
            rootView?.expansion = .camera
            rootView?.cameraOffset = .zero
            cameraOffset = .zero
            presentCameraPanel()
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

    private func presentCameraPanel() {
        guard cameraPanel == nil,
              let frame = cameraPanelFrame(for: cameraPanelModel.style) else { return }

        let panel = CameraFloatingPanel(
            frame: frame,
            onDismiss: { [weak self] in
                self?.pointerState.requestDismissal()
            }
        )
        panel.hasShadow = false
        panel.contentViewController = NSHostingController(
            rootView: CameraPanelView(
                camera: cameraSession,
                model: cameraPanelModel,
                onDismiss: { [weak self] in
                    self?.pointerState.requestDismissal()
                },
                onToggleStyle: { [weak self] in
                    self?.toggleCameraStyle()
                },
                onToggleSize: { [weak self] in
                    self?.toggleCameraSize()
                }
            )
        )
        if let contentView = panel.contentViewController?.view {
            contentView.frame = NSRect(origin: .zero, size: frame.size)
            contentView.autoresizingMask = [.width, .height]
        }
        panel.setFrame(frame, display: false)
        cameraPanel = panel
        panel.orderFrontRegardless()
    }

    private func toggleCameraStyle() {
        cameraPanelModel.toggleStyle()
        resizeCameraPanel()
    }

    private func toggleCameraSize() {
        cameraPanelModel.toggleSize()
        resizeCameraPanel()
    }

    private func resizeCameraPanel() {
        guard let panel = cameraPanel else { return }

        cameraResizeGeneration += 1
        let resizeGeneration = cameraResizeGeneration
        cameraPanelModel.isTransitioning = true

        let currentFrame = panel.frame
        let size = cameraPanelModel.style.panelSize(for: cameraPanelModel.sizeMode)
        let targetFrame = DotsLayout.cameraPanelResizeFrame(
            from: currentFrame,
            to: size
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = CameraPanelStyle.transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.completionHandler = { [weak self] in
                guard let self,
                      self.cameraResizeGeneration == resizeGeneration else {
                    return
                }
                self.cameraPanelModel.isTransitioning = false
            }
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func dismissCameraPanel() {
        guard let cameraPanel else { return }
        self.cameraPanel = nil
        cameraPanel.orderOut(nil)
        cameraPanelModel.resetStyle()
    }

    private func cameraPanelFrame(for style: CameraPanelStyle) -> NSRect? {
        guard let anchor = rootView?.orbView(for: .mirror),
              let anchorWindow = anchor.window else {
            return nil
        }

        let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
        let anchorOnScreen = anchorWindow.convertToScreen(anchorInWindow)
        let frame = DotsLayout.cameraPanelFrame(
            anchoredTo: anchorOnScreen,
            style: style,
            sizeMode: cameraPanelModel.sizeMode
        )
        return frame
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
        pointerState.setCameraOffset(.zero)
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
        item.menu = DotsMenu.quitMenu(material: dotAppearance.material)
        statusItem = item
    }

    private func installAppMenu() {
        NSApp.mainMenu = DotsMenu.mainMenu(material: dotAppearance.material)
    }
}

enum DotsMenu {
    static func mainMenu(material: DotMaterialStyle? = nil) -> NSMenu {
        let mainMenu = NSMenu()
        let selectedMaterial = material ?? DotAppearanceSettings.shared.material

        let appMenuItem = NSMenuItem(title: "Dots", action: nil, keyEquivalent: "")
        appMenuItem.submenu = quitMenu(material: selectedMaterial)
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

    static func quitMenu(material: DotMaterialStyle? = nil) -> NSMenu {
        let menu = NSMenu()
        let selectedMaterial = material ?? DotAppearanceSettings.shared.material

        let about = NSMenuItem(
            title: "About Dots",
            action: #selector(AppDelegate.showAbout(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp.delegate
        menu.addItem(about)

        let materialItem = NSMenuItem(
            title: "Dot Material",
            action: nil,
            keyEquivalent: ""
        )
        materialItem.submenu = materialMenu(selected: selectedMaterial)
        menu.addItem(materialItem)
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

    private static func materialMenu(selected: DotMaterialStyle) -> NSMenu {
        let menu = NSMenu(title: "Dot Material")
        for material in DotMaterialStyle.allCases {
            let item = NSMenuItem(
                title: material.title,
                action: #selector(AppDelegate.setDotMaterial(_:)),
                keyEquivalent: ""
            )
            item.target = NSApp.delegate
            item.representedObject = material.rawValue
            item.state = material == selected ? .on : .off
            menu.addItem(item)
        }
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

private final class CameraFloatingPanel: NSPanel {
    private let onDismiss: () -> Void
    private var isTrackingCameraControl = false
    private var dragStartScreenPoint: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDragSurface = false

    init(
        frame: NSRect,
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        NSCursor.arrow.set()
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if isCameraControlHit(event) {
                isTrackingCameraControl = true
                super.sendEvent(event)
                return
            }
            dragStartScreenPoint = NSEvent.mouseLocation
            dragStartWindowOrigin = frame.origin
            didDragSurface = false
        case .leftMouseDragged:
            guard let dragStartScreenPoint,
                  let dragStartWindowOrigin else {
                return
            }

            let currentScreenPoint = NSEvent.mouseLocation
            let deltaX = currentScreenPoint.x - dragStartScreenPoint.x
            let deltaY = currentScreenPoint.y - dragStartScreenPoint.y
            if hypot(deltaX, deltaY) >= 4 {
                didDragSurface = true
            }
            guard didDragSurface else { return }

            setFrameOrigin(
                NSPoint(
                    x: dragStartWindowOrigin.x + deltaX,
                    y: dragStartWindowOrigin.y + deltaY
                )
            )
        case .leftMouseUp:
            if isTrackingCameraControl {
                super.sendEvent(event)
                isTrackingCameraControl = false
                return
            }
            if dragStartScreenPoint != nil,
               !didDragSurface {
                onDismiss()
            }
            dragStartScreenPoint = nil
            dragStartWindowOrigin = nil
            didDragSurface = false
        default:
            super.sendEvent(event)
        }
    }

    private func isCameraControlHit(_ event: NSEvent) -> Bool {
        isCameraControlHit(at: event.locationInWindow)
    }

    private func isCameraControlHit(at point: NSPoint) -> Bool {
        let bounds = contentView?.bounds ?? NSRect(origin: .zero, size: frame.size)
        let controlsFrame = NSRect(
            x: bounds.maxX
                - DotsLayout.cameraControlEdgePadding
                - DotsLayout.cameraControlSize,
            y: bounds.maxY
                - DotsLayout.cameraControlEdgePadding
                - DotsLayout.cameraControlStackHeight,
            width: DotsLayout.cameraControlSize,
            height: DotsLayout.cameraControlStackHeight
        )
        return controlsFrame.contains(point)
    }
}

final class DotOrbView: NSView {
    var id: DotID = .mirror
    var onClick: (() -> Void)?
    var material: DotMaterialStyle = .liquid {
        didSet {
            circleView.rootView = AnyView(DotOrbMaterialView(style: material))
        }
    }
    private let circleView = NSHostingView(
        rootView: AnyView(DotOrbMaterialView(style: .liquid))
    )
    private var collapseSpring: FrameSpring?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        circleView.frame = bounds
        circleView.autoresizingMask = [.width, .height]
        circleView.wantsLayer = true
        circleView.setAccessibilityElement(false)
        addSubview(circleView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
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

    var isSpringing: Bool { collapseSpring?.isRunning == true }

    func stopSpring() {
        collapseSpring?.stop()
    }

    func springTo(
        _ destination: CGRect,
        onFrame: @escaping (CGRect) -> Void = { _ in },
        completion: @escaping () -> Void
    ) {
        if let collapseSpring, collapseSpring.isRunning {
            collapseSpring.retarget(destination, onFrame: onFrame, completion: completion)
            return
        }
        collapseSpring?.stop()
        let spring = FrameSpring(
            view: self,
            from: frame,
            to: destination,
            onFrame: onFrame,
            completion: completion
        )
        collapseSpring = spring
        spring.start()
    }
}

private final class FrameSpring {
    private weak var view: NSView?
    private var to: CGRect
    private var origin: CGPoint
    private var size: CGSize
    private var velocityOrigin = CGSize.zero
    private var velocitySize = CGSize.zero
    private var link: CADisplayLink?
    private var onFrame: (CGRect) -> Void
    private var completion: (() -> Void)?
    private let stiffness: CGFloat = 190
    private let damping: CGFloat = 13
    private let mass: CGFloat = 0.8
    private var startedAt = CACurrentMediaTime()
    private(set) var isRunning = false

    init(
        view: NSView,
        from: CGRect,
        to: CGRect,
        onFrame: @escaping (CGRect) -> Void,
        completion: @escaping () -> Void
    ) {
        self.view = view
        self.to = to
        origin = from.origin
        size = from.size
        self.onFrame = onFrame
        self.completion = completion
    }

    func start() {
        isRunning = true
        startedAt = CACurrentMediaTime()
        let link = view?.displayLink(target: self, selector: #selector(step))
        link?.add(to: .main, forMode: .common)
        self.link = link
    }

    func retarget(
        _ destination: CGRect,
        onFrame: @escaping (CGRect) -> Void,
        completion: @escaping () -> Void
    ) {
        to = destination
        self.onFrame = onFrame
        self.completion = completion
        startedAt = CACurrentMediaTime()
    }

    func stop() {
        isRunning = false
        link?.invalidate()
        link = nil
        completion = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let dt = min(link.targetTimestamp - link.timestamp, 1.0 / 30.0)
        integrate(dt)
        let frame = CGRect(origin: origin, size: size)
        view?.frame = frame
        onFrame(frame)

        let positionError = hypot(origin.x - to.origin.x, origin.y - to.origin.y)
        let sizeError = hypot(size.width - to.width, size.height - to.height)
        let speed = hypot(velocityOrigin.width, velocityOrigin.height)
            + hypot(velocitySize.width, velocitySize.height)
        let timedOut = CACurrentMediaTime() - startedAt > 1.4

        if timedOut || (positionError < 0.4 && sizeError < 0.4 && speed < 6) {
            finish()
        }
    }

    private func integrate(_ dt: CGFloat) {
        func tick(_ value: inout CGFloat, velocity: inout CGFloat, target: CGFloat) {
            let force = -stiffness * (value - target) - damping * velocity
            velocity += (force / mass) * dt
            value += velocity * dt
        }

        tick(&origin.x, velocity: &velocityOrigin.width, target: to.origin.x)
        tick(&origin.y, velocity: &velocityOrigin.height, target: to.origin.y)
        tick(&size.width, velocity: &velocitySize.width, target: to.width)
        tick(&size.height, velocity: &velocitySize.height, target: to.height)
    }

    private func finish() {
        isRunning = false
        link?.invalidate()
        link = nil
        view?.frame = to
        onFrame(to)
        let done = completion
        completion = nil
        done?()
    }
}

final class LauncherRootView: NSView {
    let hostingView: DotsHostingView
    var dotMaterial: DotMaterialStyle = .liquid {
        didSet {
            orbViews.forEach { $0.material = dotMaterial }
        }
    }
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
    private var launchingOrbIDs = Set<DotID>()
    private var homeOrbScreenOrigins: [CGPoint]?

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

    func orbView(for id: DotID) -> NSView? {
        orbViews.first { $0.id == id }
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
        layoutOrbs()
    }

    override func mouseDown(with event: NSEvent) {
        if handleClick(event) { return }
        super.mouseDown(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for orb in orbViews where !orb.isHidden && orb.alphaValue > 0.01 && orb.frame.contains(point) {
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
        if let orb = orbViews.first(where: {
            !$0.isHidden && $0.alphaValue > 0.01 && $0.frame.contains(local)
        }) {
            activateDot(
                orb.id,
                ignoreDebounce: orb.isSpringing
            )
            return true
        }
        let swift = swiftPoint(for: event)
        if expansion == .camera,
           DotsLayout.containsInteractiveContent(
            swift,
            expansion: expansion,
            cameraOffset: cameraOffset,
            taskCount: taskCount
           ) {
            pointerState?.requestDismissal()
            return true
        }
        guard let id = DotsLayout.dotID(
            at: swift,
            expansion: expansion,
            cameraOffset: .zero
        ) else {
            return false
        }
        activateDot(id)
        return true
    }

    private func activateDot(
        _ id: DotID,
        ignoreDebounce: Bool = false
    ) {
        pointerState?.requestActivation(of: id, ignoreDebounce: ignoreDebounce)
    }

    func captureHomeOrbs() {
        homeOrbScreenOrigins = nil
        layoutOrbs()
        guard let window else { return }
        homeOrbScreenOrigins = orbViews.map { orb in
            window.convertToScreen(CGRect(origin: orb.frame.origin, size: .zero)).origin
        }
    }

    func animateLaunchEntrance() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        let ids = DotRegistry.visibleIDs(from: DotRegistry.defaultActiveIDs)
        launchingOrbIDs = Set(ids)

        for index in ids.indices {
            guard index < orbViews.count else { continue }
            let id = ids[index]
            let orb = orbViews[index]
            let destination = dockedOrbFrame(at: index)
            orb.frame = DotsLayout.launchStartFrame(
                docked: destination,
                canvasHeight: bounds.height
            )
            orb.isHidden = false

            DispatchQueue.main.asyncAfter(
                deadline: .now() + (Double(index) * DotsLayout.launchCadence)
            ) { [weak self, weak orb] in
                guard let self, let orb, self.launchingOrbIDs.contains(id) else { return }
                orb.springTo(destination) { [weak self] in
                    guard let self else { return }
                    self.launchingOrbIDs.remove(id)
                    if self.launchingOrbIDs.isEmpty {
                        self.layoutOrbs()
                    }
                }
            }
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
            orb.material = dotMaterial
            addSubview(orb)
            orbViews.append(orb)
        }
        while orbViews.count > ids.count {
            orbViews.removeLast().removeFromSuperview()
        }

        for index in ids.indices {
            let orb = orbViews[index]
            let preservesAnimatedFrame = launchingOrbIDs.contains(ids[index])
            let docked = appKitRect(from: frames[index])
            if !preservesAnimatedFrame {
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
            }
            orb.layer?.contentsScale = window?.backingScaleFactor ?? 2
            orb.id = ids[index]
            orb.isHidden = false
            orb.onClick = { [weak self] in
                self?.activateDot(ids[index])
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

    private func dockedOrbFrame(at index: Int) -> CGRect {
        let docked = appKitRect(
            from: DotsLayout.nodeFrames(
                expansion: .none,
                cameraOffset: .zero
            )[index]
        )
        if let homes = homeOrbScreenOrigins,
           let window,
           index < homes.count {
            return CGRect(
                origin: window.convertFromScreen(
                    CGRect(origin: homes[index], size: docked.size)
                ).origin,
                size: docked.size
            )
        }
        return docked
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
