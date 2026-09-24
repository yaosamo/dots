import Foundation
import os

/// Filter the Xcode console by "app.dots" or a category, e.g. `category:camera`.
enum Log {
    private static let subsystem = "app.dots.Dots"
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let hotKeys = Logger(subsystem: subsystem, category: "hotkeys")

    /// Milliseconds since a `systemUptime` timestamp (the same clock as `NSEvent.timestamp`).
    static func ms(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1000
    }
}
