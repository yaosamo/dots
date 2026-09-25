import AppKit

@MainActor
enum PenCursor {
    private static var cache: [String: NSCursor] = [:]

    /// A pencil in the brush's color whose tip (bottom-left) is the hot spot.
    static func cursor(for brush: Brush) -> NSCursor {
        cursor(key: brush.rawValue, color: brush.accent)
    }

    /// The cursor for the current tool: a pencil for brushes and the marker, system cursors otherwise.
    static func cursor(for state: BrushState) -> NSCursor {
        if state.isPointer { return .arrow }
        return switch state.boardTool {
        case nil: cursor(for: state.brush)
        case .marker: cursor(key: "board.\(state.boardColor.rawValue)", color: state.boardColor.nsColor)
        case .select: .arrow
        case .hand: .openHand
        case .text: .iBeam
        case .rectangle, .ellipse, .arrow, .line, .eraser: .crosshair
        }
    }

    private static func cursor(key: String, color: NSColor) -> NSCursor {
        if let cursor = cache[key] { return cursor }
        let cursor = makeCursor(color: color)
        cache[key] = cursor
        return cursor
    }

    private static func makeCursor(color: NSColor) -> NSCursor {
        let size = NSSize(width: 28, height: 28)
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let symbol = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Pen")?
            .withSymbolConfiguration(config)

        let image = NSImage(size: size, flipped: false) { rect in
            guard let symbol else { return false }
            let inset: CGFloat = 2
            let scale = min((rect.width - inset * 2) / symbol.size.width, (rect.height - inset * 2) / symbol.size.height)
            let drawSize = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            // White halo keeps the pen visible on dark or same-colored backgrounds.
            NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 2, color: NSColor.white.cgColor)
            symbol.draw(in: NSRect(origin: NSPoint(x: inset, y: inset), size: drawSize))
            return true
        }
        // Hot spot uses a top-left origin.
        return NSCursor(image: image, hotSpot: NSPoint(x: 3, y: size.height - 3))
    }
}
