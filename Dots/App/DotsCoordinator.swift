import AppKit
import Carbon.HIToolbox
import SwiftUI

enum Dot: Int, CaseIterable, Identifiable {
    case camera, tasks, pen, four, five

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .camera: "Selfie camera"
        case .tasks: "Tasks"
        case .pen: "Draw on screen"
        case .four, .five: "Coming soon"
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .tasks: "checklist"
        case .pen: "pencil.tip"
        case .four, .five: "ellipsis"
        }
    }

    var tint: Color {
        switch self {
        case .camera: .green
        case .tasks: .orange
        case .pen: .red
        case .four, .five: .gray
        }
    }

    var isAvailable: Bool { self == .camera || self == .tasks || self == .pen }

    /// ⌃⌥1, ⌃⌥2, … matching the dot's position in the bar.
    var keyEquivalent: String { String(rawValue + 1) }
    var shortcutLabel: String { "⌃⌥\(keyEquivalent)" }

    fileprivate var keyCode: Int {
        [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5][rawValue]
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

    private var bar: DotsBarController?
    private var statusMenu: StatusMenuController?
    private var camera: CameraController?
    private var tasks: TaskOverlayController?
    private var pen: PenController?
    private var shaderLab: ShaderLabController?

    func start() {
        camera = CameraController { [weak self] in self?.set(.camera, isOn: $0) }
        tasks = TaskOverlayController { [weak self] in self?.set(.tasks, isOn: $0) }
        pen = PenController { [weak self] in self?.set(.pen, isOn: $0) }
        shaderLab = ShaderLabController(
            onPreviewTasks: { [weak self] in self?.toggle(.tasks) },
            onTogglePen: { [weak self] in self?.toggle(.pen) }
        )
        bar = DotsBarController(coordinator: self)
        bar?.show()
        statusMenu = StatusMenuController(coordinator: self)

        for dot in Dot.allCases where dot.isAvailable {
            HotKeyCenter.shared.register(keyCode: dot.keyCode, label: dot.shortcutLabel) { [weak self] in
                self?.toggle(dot)
            }
        }
    }

    func toggle(_ dot: Dot) {
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
        case .four, .five:
            NSSound.beep()
        }
    }

    func showShaderLab() {
        shaderLab?.show()
    }

    private func set(_ dot: Dot, isOn: Bool) {
        if isOn { active.insert(dot) } else { active.remove(dot) }
    }
}
