import Foundation

/// Which dots are in the bar, and whether the welcome has run. Remembered between launches.
@MainActor
final class DotSettings: ObservableObject {
    private static let enabledKey = "dots.enabled"
    private static let welcomeKey = "dots.hasCompletedWelcome"

    /// In bar order, which is always `Dot.allCases` order.
    @Published private(set) var enabled: [Dot]

    var hasCompletedWelcome: Bool {
        get { UserDefaults.standard.bool(forKey: Self.welcomeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.welcomeKey) }
    }

    /// The + dot shows while some tool is still off.
    var showsPlus: Bool { enabled.count < Dot.allCases.count }
    var barSlots: Int { enabled.count + (showsPlus ? 1 : 0) }

    init() {
        // Before the welcome has run, everything is on.
        let saved = UserDefaults.standard.stringArray(forKey: Self.enabledKey)
        enabled = saved.map { keys in Dot.allCases.filter { keys.contains($0.storageKey) } } ?? Dot.allCases
    }

    func isEnabled(_ dot: Dot) -> Bool {
        enabled.contains(dot)
    }

    func setEnabled(_ dots: Set<Dot>) {
        enabled = Dot.allCases.filter(dots.contains)
        UserDefaults.standard.set(enabled.map(\.storageKey), forKey: Self.enabledKey)
    }
}
