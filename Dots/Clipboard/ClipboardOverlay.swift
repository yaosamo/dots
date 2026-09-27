import AppKit
import SwiftUI

/// Dot 5's screen: the clipboard history as a row of cards over a frosted screen, like the tasks.
/// Click a card (or press 1–5) to copy it again; hover one for ✕ (or press Delete) to remove it;
/// Esc or a click off the cards closes it.
@MainActor
final class ClipboardController: DotFeature {
    let history = ClipboardHistory()
    /// Full screen, like the tasks: under the pen, camera and bar.
    private let panel = FloatingPanel(level: DotsLevel.tasks, keyable: true)
    private let onVisibilityChange: (Bool) -> Void
    private var keyMonitor: Any?
    private var state: ClipboardOverlayState?

    /// Off as soon as it starts closing, so the shortcut can reopen it during the exit.
    var isVisible: Bool { state.map { !$0.isDismissing } ?? false }

    init(onVisibilityChange: @escaping (Bool) -> Void) {
        self.onVisibilityChange = onVisibilityChange
        panel.onCancel = { [weak self] in self?.hide() }
    }

    func show() {
        guard !isVisible, let screen = NSScreen.underMouse else { return }
        history.refresh()
        panel.setFrame(screen.frame, display: false)
        // Fresh each time, so the frost and the cards' entrance replay.
        let state = ClipboardOverlayState()
        self.state = state
        panel.contentView = FirstClickHostingView(rootView: ClipboardOverlayView(
            history: history, state: state,
            onPick: { [weak self] item in
                self?.history.copy(item)
                self?.hide()
            },
            onClose: { [weak self] in self?.hide() }
        ))
        // 1–5 copy that card; Delete removes the one under the pointer.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isForPanel = event.window === self?.panel
            let isConsumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, isForPanel else { return false }
                return self.handleKey(event, state: state)
            }
            return isConsumed ? nil : event
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        onVisibilityChange(true)
    }

    private func handleKey(_ event: NSEvent, state: ClipboardOverlayState) -> Bool {
        let items = history.items
        if let digit = event.charactersIgnoringModifiers.flatMap(Int.init), items.indices.contains(digit - 1) {
            history.copy(items[digit - 1])
            hide()
            return true
        }
        let isDelete = event.keyCode == 51 || event.keyCode == 117 // ⌫, ⌦
        if isDelete, let hovered = state.hovered, let item = items.first(where: { $0.id == hovered }) {
            withAnimation(ClipboardOverlayView.removal) { history.delete(item) }
            return true
        }
        return false
    }

    /// Plays the entrance backwards, then removes the panel. Every way of closing ends up here.
    func hide() {
        guard isVisible, let state, !state.isDismissing else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        state.isDismissing = true
        onVisibilityChange(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + ClipboardOverlayView.exitDuration) { [weak self] in
            // Reopened meanwhile: that's a new state, and it stays.
            guard let self, self.state === state else { return }
            self.panel.orderOut(nil)
            self.panel.contentView = nil
            self.state = nil
        }
    }
}

@MainActor
final class ClipboardOverlayState: ObservableObject {
    @Published var isDismissing = false
    /// The card under the pointer, for Delete.
    @Published var hovered: ClipboardHistory.Item.ID?
}

/// The frost sweeps in (as for the tasks) and the copies rise in as a row of cards, newest first.
struct ClipboardOverlayView: View {
    static let exitDuration: TimeInterval = 0.35
    static let removal = Animation.spring(response: 0.35, dampingFraction: 0.85)
    private static let maxCardWidth: CGFloat = 230
    private static let spacing: CGFloat = 20

    @ObservedObject var history: ClipboardHistory
    @ObservedObject var state: ClipboardOverlayState
    let onPick: (ClipboardHistory.Item) -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isFrosted = false
    @State private var isRevealed = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(isDark ? Material.ultraThinMaterial : Material.regularMaterial)
                    .overlay(isDark ? Color.black.opacity(0.4) : Color.white.opacity(0.45))
                    .mask(FrostSweep(progress: isFrosted ? 1 : 0, recedesToCenter: state.isDismissing))
                    // A click off the cards closes it.
                    .onTapGesture(perform: onClose)

                VStack(spacing: 28) {
                    if history.needsPermission { notice }
                    if history.items.isEmpty {
                        Text("Copy something and it shows up here.")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                            .opacity(isRevealed ? 1 : 0)
                    } else {
                        cards(cardWidth: cardWidth(in: geometry.size.width))
                    }
                    Text("Click to copy, Esc to close")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .opacity(isRevealed && !history.items.isEmpty ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(isRevealed ? 0.3 : 0), value: isRevealed)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { isFrosted = true }
            isRevealed = true
        }
        .onChange(of: state.isDismissing) { _, isDismissing in
            guard isDismissing else { return }
            isRevealed = false
            withAnimation(.easeIn(duration: Self.exitDuration)) { isFrosted = false }
        }
    }

    /// As wide as fits the screen with room at the sides, up to `maxCardWidth`.
    private func cardWidth(in screenWidth: CGFloat) -> CGFloat {
        let count = CGFloat(max(history.items.count, 1))
        return min(Self.maxCardWidth, (screenWidth - 160 - (count - 1) * Self.spacing) / count)
    }

    private func cards(cardWidth: CGFloat) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(history.items.enumerated()), id: \.element.id) { index, item in
                ClipCard(item: item, isDark: isDark,
                         onPick: { onPick(item) },
                         onDelete: { withAnimation(Self.removal) { history.delete(item) } },
                         onHover: { isOver in
                             if isOver {
                                 state.hovered = item.id
                             } else if state.hovered == item.id {
                                 state.hovered = nil
                             }
                         })
                    .frame(width: cardWidth, height: cardWidth * 1.1)
                    .opacity(isRevealed ? 1 : 0)
                    .offset(y: isRevealed ? 0 : 24)
                    .animation(isRevealed ? .spring(response: 0.45, dampingFraction: 0.85).delay(0.1 + Double(index) * 0.04)
                                          : .easeIn(duration: 0.18),
                               value: isRevealed)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
    }

    private var notice: some View {
        VStack(spacing: 8) {
            Text("Keep a clipboard history")
                .font(.system(size: 15, weight: .semibold))
            Text("Set Dots to “Always Allow” in Privacy & Security › Paste from Other Apps.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("Open Settings", action: history.openPrivacySettings)
        }
        .multilineTextAlignment(.center)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.06)))
        .opacity(isRevealed ? 1 : 0)
    }
}

/// One copy, its text or its whole image; on hover, "Copy" and ✕ to remove it (1–5 still copy).
private struct ClipCard: View {
    let item: ClipboardHistory.Item
    let isDark: Bool
    let onPick: () -> Void
    let onDelete: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovering = false

    private var fill: Color {
        isDark ? .white.opacity(isHovering ? 0.16 : 0.1) : .white.opacity(isHovering ? 1 : 0.85)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: onPick) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .bottom) {
                    if isHovering { copyLabel }
                }
                .background(shape.fill(fill))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(isDark ? 0.12 : 0.06)))
            .shadow(color: .black.opacity(isDark ? 0 : (isHovering ? 0.14 : 0.08)), radius: isHovering ? 18 : 12, y: 6)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isHovering { deleteButton }
        }
        .scaleEffect(isHovering ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            onHover(hovering)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.content {
        case .text(let text):
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 14))
                .lineLimit(11)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .padding(14)
        case .image(let image):
            // Whole, however wide or tall: fitted in the card over a blurred, dimmed fill of itself,
            // so a panorama or a long screenshot shows entirely and the card doesn't look empty.
            // The fill is a background, so its overflow can't make the card (and the fit) bigger.
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 18)
                        .opacity(0.45)
                }
                .clipped()
        }
    }

    private var copyLabel: some View {
        Text("Copy")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(12)
            .transition(.opacity)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Delete")
        .padding(8)
        .transition(.opacity)
    }
}
