import AppKit

/// Tasks and the clipboard follow the system appearance, and the whiteboard is light, unless
/// "Always Dark Mode" is on (menu bar menu). Then all three are dark.
enum DotsAppearance {
    /// Named from when the setting only covered Tasks; kept so it carries over.
    private static let alwaysDarkKey = "tasks.alwaysDark"

    static var isAlwaysDark: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysDarkKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysDarkKey) }
    }

    /// For a panel: dark, or nil to follow the system.
    static var panelAppearance: NSAppearance? {
        isAlwaysDark ? NSAppearance(named: .darkAqua) : nil
    }
}
