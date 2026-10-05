import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The tools. New ones join the end; each keeps its shortcut number for good.
enum Dot: Int, CaseIterable, Identifiable {
    case camera, tasks, pen, timer, clipboard, screenshot

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .camera: "Blob camera"
        case .tasks: "Tasks"
        case .pen: "Draw on screen"
        case .timer: "Timer"
        case .clipboard: "Clipboard"
        case .screenshot: "Screenshot"
        }
    }

    /// One or two sentences for the welcome and setup cards.
    var summary: String {
        switch self {
        case .camera: "A floating camera bubble for calls and recordings. Resize it, reshape it, drag it anywhere."
        case .tasks: "A quick list over everything. Jot a task, check it off, get back to work."
        case .pen: "Draw on any screen, spotlight what matters, or sketch on a whiteboard."
        case .timer: "A little die that tumbles to the bottom of your screen and counts down. Click to start."
        case .clipboard: "Your recent copies, one click away from being copied again."
        case .screenshot: "Snap an area or a window and set it in a frame. Pick a backdrop, draw arrows, copy."
        }
    }

    /// Saved in UserDefaults by name, so adding tools never shuffles what's enabled.
    var storageKey: String { String(describing: self) }

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .tasks: "checklist"
        case .pen: "pencil.tip"
        case .timer: "die.face.5.fill"
        case .clipboard: "doc.on.clipboard"
        case .screenshot: "camera.viewfinder"
        }
    }

    var tint: Color {
        switch self {
        case .camera: .green
        case .tasks: .orange
        case .pen: .red
        case .timer: .purple
        case .clipboard: .blue
        case .screenshot: .pink
        }
    }

    /// ⌃⇧1, ⌃⇧2, … fixed per tool, whichever dots are enabled.
    var keyEquivalent: String { String(rawValue + 1) }
    var shortcutLabel: String { "⌃⇧\(keyEquivalent)" }

    fileprivate var keyCode: Int {
        [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
         kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9][rawValue]
    }
}

/// A feature a dot can switch on and off.
@MainActor
protocol DotFeature: AnyObject {
    var isVisible: Bool { get }
    func show()
    func hide()
}

extension DotFeature {
    func toggle() { isVisible ? hide() : show() }
}

@MainActor
final class DotsCoordinator: ObservableObject {
    @Published private(set) var active: Set<Dot> = []
    let settings = DotSettings()

    private var bar: DotsBarController?
    private var statusMenu: StatusMenuController?
    private var camera: CameraController?
    private var tasks: TaskOverlayController?
    private var pen: PenController?
    private var timer: DiceTimerController?
    private var clipboard: ClipboardController?
    private var screenshot: ScreenshotController?
    private let onboarding = OnboardingController()

    func start() {
        ProStore.shared.start()
        camera = CameraController { [weak self] in self?.set(.camera, isOn: $0) }
        tasks = TaskOverlayController { [weak self] in self?.set(.tasks, isOn: $0) }
        pen = PenController { [weak self] in self?.set(.pen, isOn: $0) }
        timer = DiceTimerController { [weak self] in self?.set(.timer, isOn: $0) }
        clipboard = ClipboardController { [weak self] in self?.set(.clipboard, isOn: $0) }
        screenshot = ScreenshotController(
            onVisibilityChange: { [weak self] in self?.set(.screenshot, isOn: $0) },
            // The pen stays up while an area is picked, so its ink can be in the shot.
            onEdit: { [weak self] in
                self?.tasks?.hide()
                self?.pen?.hide()
                self?.clipboard?.hide()
            }
        )
        bar = DotsBarController(coordinator: self)
        statusMenu = StatusMenuController(coordinator: self)
        syncEnabledDots()

        if settings.hasCompletedWelcome {
            bar?.show(dropIn: true)
        } else {
            showWelcome()
        }
    }

    func toggle(_ dot: Dot) {
        guard settings.isEnabled(dot) else { return }
        switch dot {
        case .camera:
            camera?.toggle()
        case .tasks:
            // Tasks, pen, the clipboard and the screenshot editor all cover the screen; only one at a time.
            pen?.hide()
            clipboard?.hide()
            screenshot?.hide()
            tasks?.toggle()
        case .pen:
            tasks?.hide()
            clipboard?.hide()
            screenshot?.hide()
            pen?.toggle()
        case .clipboard:
            tasks?.hide()
            pen?.hide()
            screenshot?.hide()
            clipboard?.toggle()
        case .screenshot:
            // The pen's ink can go in the shot; the editor closes the pen once the shot is taken.
            tasks?.hide()
            clipboard?.hide()
            screenshot?.toggle()
        case .timer:
            timer?.toggle()
        }
    }

    /// "Hide Dots": takes the bar off the screen, or brings it back with the launch drop-in.
    func setHidesBar(_ hides: Bool) {
        settings.hidesBar = hides
        if hides { bar?.hide() } else { bar?.show(dropIn: true) }
    }

    /// First-launch welcome: frost, the dots appear, then the user picks which to keep.
    func showWelcome() {
        present(.welcome)
    }

    /// The picker behind the bar's + dot.
    func showSetup() {
        present(.setup)
    }

    private func present(_ mode: OnboardingController.Mode) {
        guard !onboarding.isVisible else { return }
        // Every full-screen overlay makes way for it.
        tasks?.hide()
        pen?.hide()
        clipboard?.hide()
        screenshot?.hide()
        onboarding.show(mode: mode, enabled: Set(settings.enabled)) { [weak self] selection in
            self?.apply(selection)
        }
        // The overlay draws its own dots over the bar's; the real bar returns as they land.
        bar?.hide()
    }

    private func apply(_ selection: Set<Dot>) {
        settings.setEnabled(selection)
        settings.hasCompletedWelcome = true
        for dot in Dot.allCases where !selection.contains(dot) {
            feature(for: dot)?.hide()
        }
        syncEnabledDots()
        bar?.show()
    }

    private func feature(for dot: Dot) -> DotFeature? {
        switch dot {
        case .camera: camera
        case .tasks: tasks
        case .pen: pen
        case .timer: timer
        case .clipboard: clipboard
        case .screenshot: screenshot
        }
    }

    /// Shortcuts for the enabled dots, and the clipboard history only while its dot is on.
    private func syncEnabledDots() {
        registerHotKeys()
        clipboard?.history.setWatching(settings.isEnabled(.clipboard))
    }

    private func registerHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        for dot in settings.enabled {
            HotKeyCenter.shared.register(keyCode: dot.keyCode, label: dot.shortcutLabel) { [weak self] in
                self?.toggle(dot)
            }
        }
    }

    /// Writes anything not yet saved, e.g. a whiteboard still open when the app quits.
    func prepareForQuit() {
        pen?.saveBoard()
    }

    private func set(_ dot: Dot, isOn: Bool) {
        if isOn { active.insert(dot) } else { active.remove(dot) }
    }
}
