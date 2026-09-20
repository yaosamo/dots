import AppKit
import Combine
import ScreenCaptureKit
import SwiftUI
import Vision

@MainActor
final class ClipboardStore: ObservableObject {
    static let maximumItems = 8

    @Published private(set) var items: [String] = []

    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    init() {
        ingestCurrentPasteboard(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.ingestCurrentPasteboard(force: false)
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    deinit {
        timer?.invalidate()
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        remember(text)
    }

    private func ingestCurrentPasteboard(force: Bool) {
        let pasteboard = NSPasteboard.general
        guard force || pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        remember(text)
    }

    private func remember(_ text: String) {
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        if items.count > Self.maximumItems {
            items = Array(items.prefix(Self.maximumItems))
        }
    }
}

@MainActor
final class OverlaySession {
    private var window: NSWindow?

    var isVisible: Bool { window != nil }

    func present(_ view: NSView, on screen: NSScreen, canBecomeKey: Bool) {
        dismiss()
        let panel = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.canBecomeKeyOverride = canBecomeKey
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        panel.orderFrontRegardless()
        if canBecomeKey {
            panel.makeKeyAndOrderFront(nil)
        }
        window = panel
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class OverlayPanel: NSPanel {
    var canBecomeKeyOverride = false
    override var canBecomeKey: Bool { canBecomeKeyOverride }
    override var canBecomeMain: Bool { false }
}

final class RedPenView: NSView {
    var onExit: (() -> Void)?
    private var strokes: [[CGPoint]] = []
    private var current: [CGPoint] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        current = [convert(event.locationInWindow, from: nil)]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current.append(convert(event.locationInWindow, from: nil))
        if current.count > 1 {
            strokes.append(current)
        }
        current = []
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onExit?()
            return
        }
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "z" {
            if !strokes.isEmpty {
                strokes.removeLast()
                needsDisplay = true
            }
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.06).setFill()
        dirtyRect.fill()

        let path = NSBezierPath()
        path.lineWidth = 3.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.systemRed.setStroke()
        for stroke in strokes + [current] where stroke.count > 1 {
            path.removeAllPoints()
            path.move(to: stroke[0])
            for point in stroke.dropFirst() {
                path.line(to: point)
            }
            path.stroke()
        }

        let hint = "Esc to close   ⌘Z undo"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ]
        let size = hint.size(withAttributes: attrs)
        hint.draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: 24),
            withAttributes: attrs
        )
    }
}

final class RegionSelectView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let start, let current else {
            onCancel?()
            return
        }
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        if rect.width < 4 || rect.height < 4 {
            onCancel?()
            return
        }
        let screenRect = window?.convertToScreen(convert(rect, to: nil)) ?? rect
        onComplete?(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        if let start, let current {
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            let overlay = NSBezierPath(rect: bounds)
            overlay.append(NSBezierPath(rect: rect))
            overlay.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.28).setFill()
            overlay.fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 2
            border.stroke()
        } else {
            NSColor.black.withAlphaComponent(0.28).setFill()
            bounds.fill()
        }

        let hint = "Drag a rectangle to copy text   Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let size = hint.size(withAttributes: attrs)
        hint.draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: 24),
            withAttributes: attrs
        )
    }
}

enum ScreenTextCapture {
    static func recognizeText(in screenRect: CGRect) async -> String? {
        guard let image = await capture(screenRect) else { return nil }
        return await ocr(image)
    }

    private static func capture(_ screenRect: CGRect) async -> CGImage? {
        let quartz = quartzRect(fromScreen: screenRect)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: {
                $0.frame.intersects(quartz)
            }) ?? content.displays.first else { return nil }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = quartz
            config.width = max(Int(quartz.width * 2), 1)
            config.height = max(Int(quartz.height * 2), 1)
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            return nil
        }
    }

    private static func ocr(_ image: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap {
                    $0.topCandidates(1).first?.string
                }
                let text = lines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func quartzRect(fromScreen rect: CGRect) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) })
                ?? NSScreen.main else { return rect }
        let frame = screen.frame
        return CGRect(
            x: rect.minX,
            y: frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

@MainActor
final class ToastController {
    private var window: NSWindow?
    private var hideWork: DispatchWorkItem?

    func show(_ message: String, on screen: NSScreen) {
        hideWork?.cancel()
        window?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padding = NSSize(width: 28, height: 16)
        let size = NSSize(
            width: label.bounds.width + padding.width * 2,
            height: label.bounds.height + padding.height * 2
        )
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + 80
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.78)
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        label.frame = NSRect(
            x: padding.width,
            y: padding.height,
            width: label.bounds.width,
            height: label.bounds.height
        )
        panel.contentView?.addSubview(label)
        panel.orderFrontRegardless()
        window = panel

        let work = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    func dismiss() {
        hideWork?.cancel()
        window?.orderOut(nil)
        window = nil
    }
}
