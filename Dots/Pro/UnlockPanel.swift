import AppKit
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
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSCursor.arrow.set()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
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
    @ObservedObject var store: ProStore
    let feature: ProFeature?
    let onClose: () -> Void

    @State private var isShown = false

    var body: some View {
        ZStack {
            Color.black.opacity(isShown ? 0.25 : 0)
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
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return VStack(spacing: 0) {
            Text("Dots Pro")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
            Text(headline)
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(ProFeature.allCases, id: \.self) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(item == feature ? Color.accentColor : .secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 14, weight: .semibold))
                            Text(item.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 22)

            Text("One purchase, yours for good. Everything stays on your Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 20)

            actions.padding(.top, 18)
        }
        .padding(28)
        .frame(width: 380)
        .background(shape.fill(.regularMaterial))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 40, y: 16)
    }

    private var headline: String {
        switch feature {
        case .cameraEffects: "Camera effects are part of Dots Pro"
        case .brushes: "Electric, fire and rainbow ink are part of Dots Pro"
        case .whiteboard: "The whiteboard is part of Dots Pro"
        case .clipboardHistory: "More clipboard history is part of Dots Pro"
        case nil: "Unlock everything in Dots"
        }
    }

    @ViewBuilder
    private var actions: some View {
        if store.isPro {
            Label("Unlocked", systemImage: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)
                .frame(height: 40)
        } else {
            VStack(spacing: 10) {
                Button {
                    Task { await store.purchase() }
                } label: {
                    Group {
                        if store.purchaseState == .purchasing {
                            ProgressView().controlSize(.small)
                        } else if let price = store.product?.displayPrice {
                            Text("Unlock for \(price)")
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
