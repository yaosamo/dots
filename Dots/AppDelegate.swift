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
            if rootView?.animateCameraCollapse(completion: { [weak self] in
                self?.restoreHomePanel()
            }) != true {
                restoreHomePanel()
            }
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
        pointerState.setCameraReveal(false)
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

final class CameraTransitionHitAnchorView: NSView {
    static let diameter = DotsLayout.nodeDiameter + (DotsLayout.dotHitSlop * 2)
    private static let coverageOpacity: CGFloat = 0.001

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.coverageOpacity).cgColor
        layer?.cornerRadius = Self.diameter / 2
        layer?.masksToBounds = true
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func arm(at point: CGPoint) {
        frame = CGRect(
            x: point.x - (Self.diameter / 2),
            y: point.y - (Self.diameter / 2),
            width: Self.diameter,
            height: Self.diameter
        )
        isHidden = false
    }

    func disarm() {
        isHidden = true
    }

    func contains(_ point: CGPoint) -> Bool {
        guard !isHidden else { return false }
        let dx = point.x - frame.midX
        let dy = point.y - frame.midY
        let radius = Self.diameter / 2
        return (dx * dx) + (dy * dy) <= (radius * radius)
    }
}

final class DotOrbView: NSView {
    var id: DotID = .mirror
    var onClick: (() -> Void)?
    private let circleView = NSHostingView(
        rootView: AnyView(Circle().fill(.black))
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
            updateCameraMaskForCurrentFrame()
            needsLayout = true
        }
    }
    var taskCount: Int = 0

    private var orbViews: [DotOrbView] = []
    private let cameraTransitionHitAnchor = CameraTransitionHitAnchorView(frame: .zero)
    private weak var cameraMorphingOrb: DotOrbView?
    private var isCameraMorphInProgress = false
    private var hasCompletedCameraMorph = false
    private var launchingOrbIDs = Set<DotID>()
    private var homeOrbScreenOrigins: [CGPoint]?
    private var cameraDragStartScreen: CGPoint?
    private var cameraDragOriginOffset: CGSize = .zero
    private var cameraDidDrag = false

    init(hostingView: DotsHostingView) {
        self.hostingView = hostingView
        super.init(frame: .zero)
        addSubview(hostingView)
        addSubview(cameraTransitionHitAnchor)
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
        for orb in orbViews where !orb.isHidden && orb.frame.contains(point) {
            return orb
        }

        if cameraTransitionHitAnchor.contains(point) {
            return self
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
            activateDot(
                orb.id,
                ignoreDebounce: isCameraMorphInProgress || orb.isSpringing,
                cameraClick: local
            )
            return true
        }
        if cameraTransitionHitAnchor.contains(local) {
            activateDot(.mirror, ignoreDebounce: true, cameraClick: local)
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
        activateDot(id, cameraClick: id == .mirror ? local : nil)
        return true
    }

    private func activateDot(
        _ id: DotID,
        ignoreDebounce: Bool = false,
        cameraClick: CGPoint? = nil
    ) {
        if id == .mirror, let cameraClick {
            cameraTransitionHitAnchor.arm(at: cameraClick)
        }
        pointerState?.requestActivation(of: id, ignoreDebounce: ignoreDebounce)
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
        guard hasCompletedCameraMorph,
              !isCameraMorphInProgress,
              isOnHangingCamera(swift) else { return false }
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

    @discardableResult
    func animateCameraCollapse(completion: @escaping () -> Void) -> Bool {
        let ids = DotRegistry.visibleIDs(from: DotRegistry.defaultActiveIDs)
        guard let mirrorIndex = ids.firstIndex(of: .mirror) else { return false }
        let orb = cameraMorphingOrb
            ?? (orbViews.indices.contains(mirrorIndex) ? orbViews[mirrorIndex] : nil)
        guard let orb else { return false }

        sendOrbsToFront()

        let destination = dockedOrbFrame(at: mirrorIndex)
        let wasHidden = orb.isHidden
        if wasHidden, !orb.isSpringing, let hang = hangingCameraRect() {
            orb.frame = hang
        }
        cameraMorphingOrb = orb
        hasCompletedCameraMorph = false
        isCameraMorphInProgress = true
        orb.isHidden = false
        orb.alphaValue = 1
        updateCameraMask(with: orb.frame)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            orb.frame = destination
            updateCameraMask(with: destination)
            orb.alphaValue = 1
            pointerState?.setCameraReveal(false)
            pointerState?.setCameraMaskFrame(nil)
            cameraTransitionHitAnchor.disarm()
            cameraMorphingOrb = nil
            isCameraMorphInProgress = false
            completion()
            return true
        }

        orb.springTo(destination, onFrame: { [weak self] frame in
            self?.updateCameraMask(with: frame)
        }) { [weak self, weak orb] in
            guard let self, let orb, self.cameraMorphingOrb === orb else { return }
            orb.alphaValue = 1
            self.pointerState?.setCameraReveal(false)
            self.pointerState?.setCameraMaskFrame(nil)
            self.cameraTransitionHitAnchor.disarm()
            self.cameraMorphingOrb = nil
            self.isCameraMorphInProgress = false
            completion()
        }

        return true
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

        if expansion != .camera, (isCameraMorphInProgress || hasCompletedCameraMorph) {
            cameraMorphingOrb?.layer?.removeAllAnimations()
            cameraMorphingOrb?.alphaValue = 1
            cameraMorphingOrb = nil
            isCameraMorphInProgress = false
            hasCompletedCameraMorph = false
            cameraTransitionHitAnchor.disarm()
        }

        for index in ids.indices {
            let orb = orbViews[index]
            let isMirrorCameraMorph = expansion == .camera && ids[index] == .mirror
            let isCurrentCameraMorph = (isCameraMorphInProgress || hasCompletedCameraMorph)
                && cameraMorphingOrb === orb
            let preservesAnimatedFrame = isCurrentCameraMorph || launchingOrbIDs.contains(ids[index])
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
            if isMirrorCameraMorph {
                startCameraMorphIfNeeded(for: orb)
            } else {
                orb.isHidden = false
            }
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

    private func startCameraMorphIfNeeded(for orb: DotOrbView) {
        guard !hasCompletedCameraMorph else { return }
        guard let destination = hangingCameraRect() else { return }

        // A fast reopen reverses the active collapse rather than allowing its
        // stale completion to restore the collapsed panel over the new camera.
        if isCameraMorphInProgress, cameraMorphingOrb === orb {
            pointerState?.setCameraReveal(true)
            orb.isHidden = false
            orb.alphaValue = 1
            orb.springTo(destination, onFrame: { [weak self] frame in
                self?.updateCameraMask(with: frame)
            }) { [weak self, weak orb] in
                guard let self, let orb, self.cameraMorphingOrb === orb else { return }
                self.finishCameraExpand(orb)
            }
            return
        }

        cameraMorphingOrb = orb
        isCameraMorphInProgress = true
        hasCompletedCameraMorph = false
        pointerState?.setCameraReveal(true)
        updateCameraMask(with: orb.frame)
        orb.isHidden = false
        orb.alphaValue = 1
        sendOrbsToFront()

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            orb.frame = destination
            finishCameraExpand(orb)
            return
        }

        orb.springTo(destination, onFrame: { [weak self] frame in
            self?.updateCameraMask(with: frame)
        }) { [weak self, weak orb] in
            guard let self, let orb, self.cameraMorphingOrb === orb else { return }
            self.finishCameraExpand(orb)
        }
    }

    private func finishCameraExpand(_ orb: DotOrbView) {
        hasCompletedCameraMorph = true
        isCameraMorphInProgress = false
        addSubview(hostingView)
        pointerState?.setCameraMaskFrame(swiftRect(from: orb.frame))
        cameraTransitionHitAnchor.disarm()
        orb.isHidden = false
        orb.alphaValue = 0
    }

    private func sendOrbsToFront() {
        for orb in orbViews {
            addSubview(orb)
        }
    }

    private func hangingCameraRect() -> CGRect? {
        DotsLayout.hangingFrame(
            expansion: .camera,
            cameraOffset: cameraOffset
        ).map(appKitRect(from:))
    }

    private func updateCameraMask(with appKitFrame: CGRect) {
        pointerState?.setCameraMaskFrame(swiftRect(from: appKitFrame))
    }

    private func updateCameraMaskForCurrentFrame() {
        guard hasCompletedCameraMorph, let hang = hangingCameraRect() else { return }
        updateCameraMask(with: hang)
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

    private func swiftRect(from appKit: CGRect) -> CGRect {
        guard !isFlipped else { return appKit }
        return CGRect(
            x: appKit.minX,
            y: bounds.height - appKit.maxY,
            width: appKit.width,
            height: appKit.height
        )
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
