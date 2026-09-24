import AppKit
import SwiftUI

/// Stacking order of Dots' windows, all above regular app windows.
enum DotsLevel {
    private static let base = NSWindow.Level.statusBar.rawValue
    static let tasks = NSWindow.Level(rawValue: base + 1)
    static let pen = NSWindow.Level(rawValue: base + 2)
    static let camera = NSWindow.Level(rawValue: base + 3)
    static let bar = NSWindow.Level(rawValue: base + 4)
    /// Shader Lab floats above everything so it can be tweaked while the pen or Tasks is open.
    static let lab = NSWindow.Level(rawValue: base + 5)
}

/// Borderless, transparent, non-activating panel that follows the user across Spaces.
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?
    private let keyable: Bool

    init(level: NSWindow.Level, keyable: Bool) {
        self.keyable = keyable
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Hosting view that reacts to the first click even when its window isn't key.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Hosting view that only draws: clicks go to the view behind it.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension NSScreen {
    /// The screen that owns the menu bar.
    static var primary: NSScreen? { screens.first }

    static var underMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? primary
    }
}
