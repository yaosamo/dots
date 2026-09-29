import AVFoundation
import AppKit
import Combine
import SwiftUI

/// The Dots Pro card: over everything, centered on the screen under the pointer. Opened by any
/// locked feature (or the menu bar menu); Esc, "Not now" or a click off the card closes it.
@MainActor
final class UnlockController {
    static let shared = UnlockController()

    private let panel = FloatingPanel(level: DotsLevel.unlock, keyable: true)
    /// The window that had the keyboard before the card, e.g. the pen canvas; it gets it back.
    private weak var previousKey: NSWindow?
    private(set) var isVisible = false
    private var purchaseObserver: AnyCancellable?

    private init() {
        panel.onCancel = { [weak self] in self?.hide() }
    }

    /// `feature` is what was clicked; nil when opened from the menu.
    func show(for feature: ProFeature?) {
        guard !isVisible, let screen = NSScreen.underMouse else { return }
        isVisible = true
        previousKey = NSApp.keyWindow
        ProStore.shared.resetPurchaseState()
        panel.appearance = DotsAppearance.panelAppearance
        panel.setFrame(screen.frame, display: false)
        panel.contentView = FirstClickHostingView(rootView: UnlockView(
            store: ProStore.shared, feature: feature, onClose: { [weak self] in self?.hide() }
        ))
        panel.level = DotsLevel.unlock
        // The App Store's sign-in and payment windows are ordinary windows: while they're up, the
        // card steps down to their level so they show over it, and back up when they're done.
        purchaseObserver = ProStore.shared.$purchaseState.removeDuplicates().sink { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.panel.level = state == .purchasing ? .normal : DotsLevel.unlock
            }
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSCursor.arrow.set()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        purchaseObserver = nil
        panel.orderOut(nil)
        panel.contentView = nil
        if let previousKey, previousKey.isVisible {
            previousKey.makeKey()
            previousKey.makeFirstResponder(previousKey.contentView)
        }
        previousKey = nil
    }
}

private struct UnlockView: View {
    /// How long each feature's loop shows before the next tab takes over.
    private static let dwell: TimeInterval = 5

    @ObservedObject var store: ProStore
    let onClose: () -> Void

    @State private var selected: ProFeature
    @State private var isShown = false
    /// 0 → 1 across the selected tab while it's on screen.
    @State private var progress: CGFloat = 0

    init(store: ProStore, feature: ProFeature?, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _selected = State(initialValue: feature ?? .cameraEffects)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(isShown ? 0.3 : 0)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            card
                .opacity(isShown ? 1 : 0)
                .scaleEffect(isShown ? 1 : 0.96)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isShown = true } }
        .onChange(of: store.isPro) { _, isPro in
            // Unlocked: a beat of "Unlocked ✓", then back to what they were doing.
            guard isPro else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: onClose)
        }
        // Each tab plays for `dwell`, then the next one; a click on a tab restarts the clock.
        .task(id: selected) {
            progress = 0
            withAnimation(.linear(duration: Self.dwell)) { progress = 1 }
            try? await Task.sleep(for: .seconds(Self.dwell))
            guard !Task.isCancelled, store.purchaseState != .purchasing else { return }
            let all = ProFeature.allCases
            withAnimation(.easeInOut(duration: 0.3)) {
                selected = all[(all.firstIndex(of: selected)! + 1) % all.count]
            }
        }
    }

    private var card: some View {
        let outer: CGFloat = 30, inset: CGFloat = 10
        let shape = RoundedRectangle(cornerRadius: outer, style: .continuous)
        return VStack(spacing: 0) {
            ZStack {
                LoopingVideo(name: selected.preview)
                    .id(selected)
                    .transition(.opacity)
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: outer - inset, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text("Dots Pro")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                    .padding(12)
            }

            VStack(spacing: 6) {
                Text(selected.title)
                    .font(.system(size: 22, weight: .semibold))
                Text(selected.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 36, alignment: .top)
            }
            .contentTransition(.opacity)
            .padding(.top, 18)
            .padding(.horizontal, 24)

            tabs.padding(.top, 14).padding(.horizontal, 14)

            actions.padding(.top, 20).padding(.horizontal, 24)

            Text("One purchase, yours for good. Everything stays on your Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
        .padding(inset)
        .padding(.bottom, 12)
        .frame(width: 520)
        .background(shape.fill(.regularMaterial))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.3), radius: 50, y: 20)
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(ProFeature.allCases, id: \.self) { feature in
                let isSelected = feature == selected
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { selected = feature }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(height: 18)
                        Text(feature.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        // Fills while this tab plays; empty for the others.
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                            .frame(height: 3)
                            .overlay(alignment: .leading) {
                                GeometryReader { geometry in
                                    Capsule()
                                        .fill(Color.primary.opacity(0.7))
                                        .frame(width: isSelected ? geometry.size.width * progress : 0)
                                }
                            }
                            .padding(.horizontal, 10)
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(isSelected ? 0.08 : 0))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if store.isPro {
            Label("Unlocked", systemImage: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)
                .frame(height: 44)
        } else {
            VStack(spacing: 12) {
                Button {
                    Task { await store.purchase() }
                } label: {
                    Group {
                        if store.purchaseState == .purchasing {
                            ProgressView().controlSize(.small)
                        } else if let price = store.product?.displayPrice {
                            Text("Unlock everything for \(price)")
                        } else {
                            Text("Unlock Dots Pro")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())
                .disabled(store.purchaseState == .purchasing)

                if let message = statusMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 18) {
                    Button("Restore Purchase") { Task { await store.restore() } }
                    Button("Not now", action: onClose)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .disabled(store.purchaseState == .purchasing)
            }
        }
    }

    private var statusMessage: String? {
        switch store.purchaseState {
        case .pending: "Waiting for approval. Dots unlocks as soon as it goes through."
        case .failed(let message): message
        case .idle, .purchasing: nil
        }
    }
}

/// A muted clip from Pro/Previews, looping for as long as it's on screen.
private struct LoopingVideo: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4")
                ?? Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "Previews") else { return view }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        player.play()
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {}

    static func dismantleNSView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer.player?.pause()
        view.playerLayer.player = nil
        view.looper = nil
    }

    final class PlayerView: NSView {
        let playerLayer = AVPlayerLayer()
        var looper: AVPlayerLooper?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
