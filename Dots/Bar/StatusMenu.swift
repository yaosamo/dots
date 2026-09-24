import AppKit

/// Menu bar icon with About, the tools and their shortcuts, and Quit.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let coordinator: DotsCoordinator
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    init(coordinator: DotsCoordinator) {
        self.coordinator = coordinator
        super.init()
        item.button?.image = Self.icon
        item.button?.toolTip = "Dots"
        menu.delegate = self
        item.menu = menu
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { rebuild(menu) }
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let about = NSMenuItem(title: "About Dots", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        for dot in coordinator.settings.enabled {
            let toolItem = NSMenuItem(title: dot.title, action: #selector(toggleDot(_:)), keyEquivalent: dot.keyEquivalent)
            // Shown for reference; the global hot key does the work even when the menu is closed.
            toolItem.keyEquivalentModifierMask = HotKeyCenter.modifierFlags
            toolItem.tag = dot.rawValue
            toolItem.target = self
            toolItem.state = coordinator.active.contains(dot) ? .on : .off
            toolItem.image = NSImage(systemSymbolName: dot.symbol, accessibilityDescription: nil)
            menu.addItem(toolItem)
        }
        let choose = NSMenuItem(title: "Choose Dots…", action: #selector(showSetup), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)
        menu.addItem(.separator())

        let shaderLab = NSMenuItem(title: "Shader Lab…", action: #selector(showShaderLab), keyEquivalent: "")
        shaderLab.target = self
        menu.addItem(shaderLab)

        let welcome = NSMenuItem(title: "Show Welcome", action: #selector(showWelcome), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)

        let alwaysDark = NSMenuItem(title: "Always Dark Tasks", action: #selector(toggleAlwaysDarkTasks), keyEquivalent: "")
        alwaysDark.target = self
        alwaysDark.state = TaskAppearance.isAlwaysDark ? .on : .off
        menu.addItem(alwaysDark)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Dots", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc private func toggleDot(_ sender: NSMenuItem) {
        guard let dot = Dot(rawValue: sender.tag) else { return }
        coordinator.toggle(dot)
    }

    @objc private func showSetup() {
        coordinator.showSetup()
    }

    @objc private func showWelcome() {
        coordinator.showWelcome()
    }

    @objc private func showShaderLab() {
        coordinator.showShaderLab()
    }

    @objc private func toggleAlwaysDarkTasks() {
        TaskAppearance.isAlwaysDark.toggle()
    }

    @objc private func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let shortcuts = coordinator.settings.enabled
            .map { "\($0.title)  \($0.shortcutLabel)" }
            .joined(separator: "\n")
        let credits = NSAttributedString(
            string: "Small tools at the top of your screen, one dot each.\n\n\(shortcuts)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Dots", .credits: credits])
    }

    /// Five dots in a row, drawn as a template so it follows the menu bar's appearance.
    private static let icon: NSImage = {
        let image = NSImage(size: NSSize(width: 24, height: 16), flipped: false) { rect in
            let diameter: CGFloat = 3.2
            let gap: CGFloat = 1.5
            var x = (rect.width - (diameter * 5 + gap * 4)) / 2
            NSColor.black.setFill()
            for _ in 0..<5 {
                NSBezierPath(ovalIn: NSRect(x: x, y: rect.midY - diameter / 2, width: diameter, height: diameter)).fill()
                x += diameter + gap
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
