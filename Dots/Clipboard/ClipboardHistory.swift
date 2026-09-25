import AppKit
import SwiftUI

/// Dot 5: the last five things you copied, in a card that hangs under the dot bar.
/// Click one (or press 1–5) to copy it again; Esc or a click elsewhere closes it.
///
/// Reading the clipboard without the user pasting shows a system alert on every read, so history
/// is only recorded silently once Dots is set to "Always Allow" in System Settings › Privacy &
/// Security › Paste from Other Apps. Watching `changeCount` never reads, so it's always quiet.
/// Until then, opening the card reads once (showing the alert) and explains the setting.
@MainActor
final class ClipboardHistory: ObservableObject {
    struct Item: Identifiable, Equatable {
        enum Content: Equatable {
            case text(String)
            case image(NSImage)
        }

        let id = UUID()
        let content: Content
        let copiedAt = Date()
    }

    static let limit = 5
    private static let pollInterval: TimeInterval = 0.5

    @Published private(set) var items: [Item] = []
    @Published private(set) var needsPermission = false

    private let pasteboard = NSPasteboard.general
    private var lastChange = NSPasteboard.general.changeCount
    private var poll: Timer?

    private var canReadSilently: Bool {
        if #available(macOS 15.4, *) { return pasteboard.accessBehavior == .alwaysAllow }
        return true
    }

    /// Runs while the clipboard dot is enabled.
    func setWatching(_ isOn: Bool) {
        poll?.invalidate()
        poll = nil
        guard isOn else { return }
        lastChange = pasteboard.changeCount
        poll = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForChange() }
        }
    }

    /// When the card opens: pick up the current clipboard even if it can't be read silently
    /// (opening the card is the user asking for it).
    func refresh() {
        if !canReadSilently {
            needsPermission = true
            capture()
            lastChange = pasteboard.changeCount
        }
    }

    func copy(_ item: Item) {
        pasteboard.clearContents()
        switch item.content {
        case .text(let text): pasteboard.setString(text, forType: .string)
        case .image(let image): pasteboard.writeObjects([image])
        }
        // Our own write: don't record it again, just move it to the top.
        lastChange = pasteboard.changeCount
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    private func checkForChange() {
        let change = pasteboard.changeCount
        guard change != lastChange else { return }
        lastChange = change
        needsPermission = !canReadSilently
        if !needsPermission { capture() }
    }

    private func capture() {
        let content: Item.Content
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content = .text(text)
        } else if let image = NSImage(pasteboard: pasteboard) {
            content = .image(image)
        } else {
            return
        }
        // Copying the same thing again just brings it to the top.
        items.removeAll { $0.content == content }
        items.insert(Item(content: content), at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }
}

@MainActor
final class ClipboardController: DotFeature {
    private static let width: CGFloat = 380

    let history = ClipboardHistory()
    private let panel = FloatingPanel(level: DotsLevel.camera, keyable: true)
    private let onVisibilityChange: (Bool) -> Void
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    private(set) var isVisible = false

    init(onVisibilityChange: @escaping (Bool) -> Void) {
        self.onVisibilityChange = onVisibilityChange
        panel.onCancel = { [weak self] in self?.hide() }
        panel.contentView = FirstClickHostingView(rootView: ClipboardView(history: history) { [weak self] item in
            self?.history.copy(item)
            self?.hide()
        })
    }

    func show() {
        guard !isVisible, let screen = NSScreen.primary else { return }
        history.refresh()
        // Under the dot bar, centered.
        let height = ClipboardView.height(for: history)
        let top = screen.visibleFrame.maxY - DotsBarMetrics.height - DotsBarMetrics.topInset - 6
        panel.setFrame(NSRect(x: screen.frame.midX - Self.width / 2, y: top - height,
                              width: Self.width, height: height), display: true)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // 1–5 copy that item.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let digit = event.charactersIgnoringModifiers.flatMap(Int.init)
            let isForPanel = event.window === self?.panel
            let isConsumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, isForPanel, let digit, self.history.items.indices.contains(digit - 1) else { return false }
                self.history.copy(self.history.items[digit - 1])
                self.hide()
                return true
            }
            return isConsumed ? nil : event
        }
        // A click in another app closes it.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        isVisible = true
        onVisibilityChange(true)
    }

    func hide() {
        guard isVisible else { return }
        [keyMonitor, clickMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        keyMonitor = nil
        clickMonitor = nil
        panel.orderOut(nil)
        isVisible = false
        onVisibilityChange(false)
    }
}

struct ClipboardView: View {
    private static let rowHeight: CGFloat = 52
    private static let padding: CGFloat = 8
    private static let noticeHeight: CGFloat = 92

    /// Enough for the rows (or the empty message) and the permission notice.
    static func height(for history: ClipboardHistory) -> CGFloat {
        let rows = CGFloat(max(history.items.count, 1))
        return padding * 2 + rows * rowHeight + (history.needsPermission ? noticeHeight : 0)
    }

    @ObservedObject var history: ClipboardHistory
    let onPick: (ClipboardHistory.Item) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if history.needsPermission { notice }
            if history.items.isEmpty {
                Text("Copy something and it shows up here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            }
            ForEach(Array(history.items.enumerated()), id: \.element.id) { index, item in
                ClipRow(item: item, number: index + 1) { onPick(item) }
                    .frame(height: Self.rowHeight)
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keep a clipboard history")
                .font(.system(size: 13, weight: .semibold))
            Text("Set Dots to “Always Allow” in Privacy & Security › Paste from Other Apps.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings", action: history.openPrivacySettings)
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: Self.noticeHeight - 8, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .padding(.bottom, 8)
    }
}

private struct ClipRow: View {
    let item: ClipboardHistory.Item
    let number: Int
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.2)))
                preview
                Spacer(minLength: 0)
                Text(item.copiedAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.content {
        case .text(let text):
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13))
                .lineLimit(2)
                .truncationMode(.tail)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
