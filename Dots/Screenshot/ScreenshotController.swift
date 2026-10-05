import AppKit
import SwiftUI

/// Dot 6: pick an area, a window or the whole screen, and the shot opens set in a frame (FramedShot)
/// to restyle, draw on, then copy or save (ScreenshotEditor).
@MainActor
final class ScreenshotController: DotFeature {
    /// Over everything but the Pro card, so the bar can't be clicked mid-pick; left out of the shot.
    private let pickerPanel = FloatingPanel(level: DotsLevel.onboarding, keyable: true)
    /// A window of its own, which you can move, resize and click past to other apps.
    private let editorPanel = EditorWindow()
    private let onVisibilityChange: (Bool) -> Void
    /// Closes the other full-screen dots as the editor opens. Not while picking, so ink the pen has
    /// on the screen can be in the shot.
    private let onEdit: () -> Void
    private var keyMonitor: Any?
    private var picker: ScreenshotPicker?
    private var editor: ScreenshotEditorModel?

    var isVisible: Bool { picker != nil || editor.map { !$0.isDismissing } ?? false }

    init(onVisibilityChange: @escaping (Bool) -> Void, onEdit: @escaping () -> Void) {
        self.onVisibilityChange = onVisibilityChange
        self.onEdit = onEdit
        pickerPanel.onCancel = { [weak self] in self?.cancelPick() }
        editorPanel.onClose = { [weak self] in self?.hide() }
    }

    /// The editor can end up behind other apps' windows: the shortcut brings it back rather than
    /// closing it.
    func toggle() {
        if let editor, !editor.isDismissing, picker == nil, !editorPanel.isKeyWindow {
            NSApp.activate()
            editorPanel.makeKeyAndOrderFront(nil)
        } else {
            isVisible ? hide() : show()
        }
    }

    func show() {
        guard !isVisible else { return }
        onVisibilityChange(true)
        if ScreenCapture.hasPermission {
            pick()
        } else {
            // Lists Dots in Screen Recording (and asks, the first time); the editor explains.
            ScreenCapture.requestPermission()
            openEditor(with: nil)
        }
    }

    func hide() {
        if picker != nil { closePicker() }
        guard let editor, !editor.isDismissing else {
            if editor == nil { onVisibilityChange(false) }
            return
        }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        ColorWell.shared.close()
        editor.isDismissing = true
        onVisibilityChange(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ScreenshotEditor.exitDuration
            editorPanel.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ScreenshotEditor.exitDuration) { [weak self] in
            // Reopened meanwhile: that's a new editor, and it stays.
            guard let self, self.editor === editor else { return }
            self.editorPanel.orderOut(nil)
            self.editorPanel.contentView = nil
            self.editorPanel.alphaValue = 1
            self.editor = nil
        }
    }

    // MARK: Picking

    private func pick() {
        guard let screen = NSScreen.underMouse else { return }
        let picker = ScreenshotPicker(screen: screen)
        self.picker = picker
        pickerPanel.setFrame(screen.frame, display: false)
        pickerPanel.contentView = FirstClickHostingView(rootView: ScreenshotPickerView(
            picker: picker,
            onPick: { [weak self] target in self?.capture(target, on: screen) }
        ))
        NSApp.activate()
        pickerPanel.makeKeyAndOrderFront(nil)
        // A frame later, so the panel is up first; the windows only light up under the pointer.
        Task { picker.windows = await ScreenCapture.windows(on: screen) }
    }

    private func cancelPick() {
        closePicker()
        // Retaking from the editor goes back to it; otherwise the dot is off again.
        if let editor, !editor.isDismissing {
            editorPanel.makeKeyAndOrderFront(nil)
        } else {
            onVisibilityChange(false)
        }
    }

    private func closePicker() {
        pickerPanel.orderOut(nil)
        pickerPanel.contentView = nil
        picker = nil
    }

    private func capture(_ target: ScreenshotPicker.Target, on screen: NSScreen) {
        closePicker()
        Task {
            // The picker is already left out of the shot; this lets the window server drop it from
            // the screen too, and the pointer's hover effects in other apps settle.
            try? await Task.sleep(for: .milliseconds(80))
            do {
                let shot: ScreenCapture.Shot
                switch target {
                case .area(let rect): shot = try await ScreenCapture.capture(rect, on: screen)
                case .window(let window): shot = try await ScreenCapture.capture(window, on: screen)
                case .screen: shot = try await ScreenCapture.capture(nil, on: screen)
                }
                openEditor(with: shot)
            } catch {
                Log.screenshot.error("Capture failed: \(error.localizedDescription, privacy: .public)")
                openEditor(with: nil, error: error.localizedDescription)
            }
        }
    }

    // MARK: Editing

    private func openEditor(with shot: ScreenCapture.Shot?, error: String? = nil) {
        // Retaking: the same editor, with the new shot.
        if let editor, !editor.isDismissing {
            if let shot { editor.replace(shot) }
            editor.error = error
            NSApp.activate()
            editorPanel.makeKeyAndOrderFront(nil)
            return
        }
        guard let screen = NSScreen.underMouse else { return }
        onEdit()
        let editor = ScreenshotEditorModel(shot: shot)
        editor.error = error
        self.editor = editor
        editorPanel.place(on: screen)
        // It may still be fading out from the last editor.
        editorPanel.alphaValue = 1
        editorPanel.contentView = FirstClickHostingView(rootView: ScreenshotEditor(
            model: editor,
            onRetake: { [weak self] in self?.retake() },
            onSave: { [weak self] in self?.save() },
            onCopy: { [weak self] in self?.copyAndClose() }
        ))
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isForPanel = event.window === self?.editorPanel
            let isConsumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, isForPanel, let editor = self.editor else { return false }
                return self.handleKey(event, editor: editor)
            }
            return isConsumed ? nil : event
        }
        NSApp.activate()
        editorPanel.makeKeyAndOrderFront(nil)
    }

    private func save() {
        editor?.save(over: editorPanel)
    }

    /// The usual next step is pasting it somewhere, so the editor gets out of the way.
    private func copyAndClose() {
        guard let editor, editor.copy() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.editor === editor else { return }
            self.hide()
        }
    }

    private func retake() {
        guard ScreenCapture.hasPermission else {
            ScreenCapture.requestPermission()
            return
        }
        editorPanel.orderOut(nil)
        pick()
    }

    /// ⌘C copy, ⌘S save, ⌘Z undo, ⌘V paste an image, ⌘N a new shot, ⌘W close; P, A, R pick the pen,
    /// arrow, box. Not while typing (Safari's address): the text field gets the keys.
    private func handleKey(_ event: NSEvent, editor: ScreenshotEditorModel) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command, key == "w" {
            hide()
            return true
        }
        guard !(editorPanel.firstResponder is NSText) else { return false }
        if flags == .command {
            switch key {
            case "c": copyAndClose()
            case "s": save()
            case "z": editor.undo()
            case "v": editor.pasteImage()
            case "n": retake()
            default: return false
            }
            return true
        }
        guard flags.isEmpty, let kind = Mark.Kind.allCases.first(where: { $0.key == key }) else { return false }
        editor.tool = kind
        return true
    }
}

/// The editor's window: dark, with its traffic lights over the content (the title bar is clear),
/// resizable, and where you last left it. Esc and the close button close the editor.
private final class EditorWindow: NSWindow {
    var onClose: (() -> Void)?
    private static let frameName = "ScreenshotEditor"

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Screenshot"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Dark, like a photo editor, whatever the system's appearance; clear, so the backdrop's
        // glass shows the desktop through.
        appearance = NSAppearance(named: .darkAqua)
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        tabbingMode = .disallowed
        collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        minSize = NSSize(width: 860, height: 600)
    }

    /// Where it was last time, or else centered on `screen`, with a margin all round.
    func place(on screen: NSScreen) {
        if frameAutosaveName.isEmpty {
            let restored = setFrameUsingName(Self.frameName)
            setFrameAutosaveName(Self.frameName)
            if restored, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { return }
        } else if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            return
        }
        let visible = screen.visibleFrame
        let size = NSSize(width: min(visible.width - 80, 1360), height: min(visible.height - 60, 900))
        setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                        width: size.width, height: size.height), display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) { onClose?() }
    override func performClose(_ sender: Any?) { onClose?() }
}

/// What the picker is choosing between, and what was chosen.
@MainActor
final class ScreenshotPicker: ObservableObject {
    enum Target {
        /// In top-left points of the screen.
        case area(CGRect)
        case window(ScreenCapture.Window)
        case screen
    }

    let screen: NSScreen
    /// Frontmost first; empty until ScreenCaptureKit has listed them.
    @Published var windows: [ScreenCapture.Window] = []

    init(screen: NSScreen) {
        self.screen = screen
    }

    func window(at point: CGPoint) -> ScreenCapture.Window? {
        windows.first { $0.frame.contains(point) }
    }
}

/// Over the screen: drag out an area, or click a window (it lights up under the pointer), or click
/// the desktop or press Return for the whole screen. Esc cancels (FloatingPanel's cancelOperation).
struct ScreenshotPickerView: View {
    /// Below this, a drag was a click.
    private static let minDrag: CGFloat = 4

    @ObservedObject var picker: ScreenshotPicker
    let onPick: (ScreenshotPicker.Target) -> Void

    @State private var pointer: CGPoint?
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var hasAppeared = false

    private var area: CGRect? {
        guard let dragStart, let dragEnd else { return nil }
        let rect = CGRect(start: dragStart, end: dragEnd)
        return rect.width >= Self.minDrag || rect.height >= Self.minDrag ? rect : nil
    }

    private var hovered: ScreenCapture.Window? {
        guard area == nil, let pointer else { return nil }
        return picker.window(at: pointer)
    }

    var body: some View {
        GeometryReader { geometry in
            let hole = area ?? hovered?.frame
            ZStack(alignment: .topLeading) {
                ScreenDim(hole: hole)
                    .fill(Color.black.opacity(hasAppeared ? 0.28 : 0), style: FillStyle(eoFill: true))
                    .animation(.easeOut(duration: 0.2), value: hasAppeared)
                if let area {
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 1.5)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .frame(width: area.width, height: area.height)
                        .offset(x: area.minX, y: area.minY)
                    sizeLabel(for: area, in: geometry.size)
                } else if let hovered {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Dot.screenshot.tint.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Dot.screenshot.tint, lineWidth: 3))
                        .frame(width: hovered.frame.width, height: hovered.frame.height)
                        .offset(x: hovered.frame.minX, y: hovered.frame.minY)
                        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hovered.id)
                }
                hint
                    .frame(width: geometry.size.width)
                    .offset(y: DotsBarMetrics.height + 40)
                    .opacity(dragStart == nil && hasAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: dragStart == nil)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                NSCursor.crosshair.set()
                if case .active(let location) = phase { pointer = location } else { pointer = nil }
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    NSCursor.crosshair.set()
                    if dragStart == nil { dragStart = value.startLocation }
                    dragEnd = value.location
                    pointer = value.location
                }
                .onEnded { value in
                    let picked = area
                    dragStart = nil
                    dragEnd = nil
                    if let picked {
                        onPick(.area(picked))
                    } else if let window = picker.window(at: value.location) {
                        onPick(.window(window))
                    } else {
                        onPick(.screen)
                    }
                })
        }
        .ignoresSafeArea()
        .background(ReturnKey { onPick(.screen) })
        .onAppear {
            NSCursor.crosshair.set()
            hasAppeared = true
        }
    }

    private var hint: some View {
        HStack(spacing: 8) {
            Circle().fill(Dot.screenshot.tint).frame(width: 8, height: 8)
            Text("Drag an area or click a window")
                .fontWeight(.medium)
            Text("Return for the whole screen · Esc to cancel")
                .foregroundStyle(.white.opacity(0.6))
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .allowsHitTesting(false)
    }

    /// Width × height in pixels, under the area (above it near the screen's bottom).
    private func sizeLabel(for area: CGRect, in size: CGSize) -> some View {
        let scale = picker.screen.backingScaleFactor
        let below = area.maxY + 34 < size.height
        return Text("\(Int(area.width * scale)) × \(Int(area.height * scale))")
            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.7)))
            .fixedSize()
            .offset(x: area.minX, y: below ? area.maxY + 8 : area.minY - 28)
            .allowsHitTesting(false)
    }
}

/// The whole screen, with the chosen area or window cut out (filled even-odd).
private struct ScreenDim: Shape {
    let hole: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let hole { path.addRect(hole) }
        return path
    }
}

/// Return picks the whole screen. A key-equivalent button, so it works without a key monitor.
private struct ReturnKey: View {
    let action: () -> Void

    var body: some View {
        Button("", action: action)
            .keyboardShortcut(.defaultAction)
            .opacity(0)
            .allowsHitTesting(false)
    }
}
