import AppKit
import ScreenCaptureKit

/// Takes the shots for dot 6 with ScreenCaptureKit, which needs Screen Recording permission.
/// Dots' own bar and overlays are left out; the pen's ink and the camera bubble stay in, so
/// whatever's drawn on screen ends up in the shot.
enum ScreenCapture {
    /// A shot and how many pixels it has per point.
    struct Shot {
        let image: CGImage
        let scale: CGFloat

        /// Its size in points.
        var size: CGSize { CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) }
    }

    /// A window that can be picked whole, in the picker's top-left coordinates.
    struct Window: Identifiable {
        let id: CGWindowID
        let frame: CGRect
        fileprivate let window: SCWindow
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time and lists Dots in Privacy & Security › Screen Recording.
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The normal app windows on `screen`, frontmost first, in top-left coordinates of the screen.
    static func windows(on screen: NSScreen) async -> [Window] {
        guard let displayID = screen.displayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else { return [] }
        let bounds = CGDisplayBounds(displayID)
        // ScreenCaptureKit doesn't promise an order; the window server's list is front to back.
        let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return content.windows
            .filter { window in
                window.windowLayer == 0 && window.isOnScreen
                    && window.owningApplication?.processID != getpid()
                    && window.frame.width > 40 && window.frame.height > 40
                    && window.frame.intersects(bounds)
            }
            .sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
            .map { Window(id: $0.windowID, frame: $0.frame.offsetBy(dx: -bounds.minX, dy: -bounds.minY), window: $0) }
    }

    /// `rect` in top-left points of `screen`; nil for the whole screen.
    static func capture(_ rect: CGRect?, on screen: NSScreen) async throws -> Shot {
        guard let displayID = screen.displayID else { throw CaptureError.noDisplay }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CaptureError.noDisplay }
        let filter = SCContentFilter(display: display, excludingWindows: ownOverlays(in: content))
        let scale = screen.backingScaleFactor
        let area = (rect ?? CGRect(origin: .zero, size: screen.frame.size)).integral
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = area
        configuration.width = Int(area.width * scale)
        configuration.height = Int(area.height * scale)
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return Shot(image: image, scale: scale)
    }

    /// Just the window, without its shadow or anything over it, with its rounded corners clear.
    static func capture(_ window: Window, on screen: NSScreen) async throws -> Shot {
        let filter = SCContentFilter(desktopIndependentWindow: window.window)
        let scale = screen.backingScaleFactor
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.shouldBeOpaque = false
        configuration.backgroundColor = .clear
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return Shot(image: image, scale: scale)
    }

    /// The bar, the welcome, the Pro card and the screenshot picker: everything of Dots from the bar up.
    private static func ownOverlays(in content: SCShareableContent) -> [SCWindow] {
        content.windows.filter {
            $0.owningApplication?.processID == getpid() && $0.windowLayer >= DotsLevel.bar.rawValue
        }
    }

    enum CaptureError: LocalizedError {
        case noDisplay

        var errorDescription: String? { "That screen isn't available any more." }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
