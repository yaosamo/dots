import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The tools. New ones join the end; each keeps its shortcut number for good.
enum Dot: Int, CaseIterable, Identifiable {
    case camera, tasks, pen

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .camera: "Selfie camera"
        case .tasks: "Tasks"
        case .pen: "Draw on screen"
        }
    }

    /// One or two sentences for the welcome and setup cards.
    var summary: String {
        switch self {
        case .camera: "A floating selfie bubble for calls and recordings. Resize it, reshape it, drag it anywhere."
        case .tasks: "A quick list over everything. Jot a task, check it off, get back to work."
        case .pen: "Draw on any screen, spotlight what matters, or sketch on a whiteboard."
        }
    }

    /// Saved in UserDefaults by name, so adding tools never shuffles what's enabled.
    var storageKey: String { String(describing: self) }

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .tasks: "checklist"
        case .pen: "pencil.tip"
        }
    }

    var tint: Color {
        switch self {
        case .camera: .green
        case .tasks: .orange
        case .pen: .red
        }
    }

    /// ⌃⌥1, ⌃⌥2, … fixed per tool, whichever dots are enabled.
    var keyEquivalent: String { String(rawValue + 1) }
    var shortcutLabel: String { "⌃⌥\(keyEquivalent)" }

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
    private var shaderLab: ShaderLabController?
    private let onboarding = OnboardingController()

    func start() {
        camera = CameraController { [weak self] in self?.set(.camera, isOn: $0) }
        tasks = TaskOverlayController { [weak self] in self?.set(.tasks, isOn: $0) }
        pen = PenController { [weak self] in self?.set(.pen, isOn: $0) }
        shaderLab = ShaderLabController(
            onPreviewTasks: { [weak self] in self?.toggle(.tasks) },
            onTogglePen: { [weak self] in self?.toggle(.pen) }
        )
        bar = DotsBarController(coordinator: self)
        statusMenu = StatusMenuController(coordinator: self)
        registerHotKeys()

        if settings.hasCompletedWelcome {
            bar?.show()
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
            // Tasks and pen both cover the screen; only one at a time.
            pen?.hide()
            tasks?.toggle()
        case .pen:
            tasks?.hide()
            pen?.toggle()
        }
    }

    /// First-launch welcome: frost, the dots appear, then the user picks which to keep.
    func showWelcome() {
        present(.welcome)
    }

    /// The picker behind the bar's + dot.
    func showSetup() {
        present(.setup)
    }

    private func present(_ mode: OnboardingState.Mode) {
        guard !onboarding.isVisible else { return }
        tasks?.hide()
        pen?.hide()
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
            switch dot {
            case .camera: camera?.hide()
            case .tasks: tasks?.hide()
            case .pen: pen?.hide()
            }
        }
        registerHotKeys()
        bar?.show()
    }

    private func registerHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        for dot in settings.enabled {
            HotKeyCenter.shared.register(keyCode: dot.keyCode, label: dot.shortcutLabel) { [weak self] in
                self?.toggle(dot)
            }
        }
    }

    func showShaderLab() {
        shaderLab?.show()
    }

    private func set(_ dot: Dot, isOn: Bool) {
        if isOn { active.insert(dot) } else { active.remove(dot) }
    }
}
