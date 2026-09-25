import AppKit
import SwiftUI

/// The two full-screen flows: the first-launch welcome (Welcome.swift) and dot setup behind the
/// bar's + dot (below). Both end with the chosen dots flying into the bar, where the real bar
/// takes over as the overlay clears.
@MainActor
final class OnboardingController {
    enum Mode { case welcome, setup }

    private let panel = FloatingPanel(level: DotsLevel.onboarding, keyable: true)
    private(set) var isVisible = false

    /// `onReveal` gets the chosen dots as they land in the bar, before the overlay fades.
    func show(mode: Mode, enabled: Set<Dot>, onReveal: @escaping (Set<Dot>) -> Void) {
        guard !isVisible, let screen = NSScreen.primary else { return }
        isVisible = true
        let barSlots = { DotsBarMetrics.slotCenters(slots: $0, on: screen) }
        let close: () -> Void = { [weak self] in self?.close() }

        switch mode {
        case .welcome:
            let state = WelcomeState()
            // The welcome has to be finished with Done.
            panel.onCancel = nil
            panel.contentView = FirstClickHostingView(rootView: WelcomeView(
                state: state, barSlots: barSlots,
                onDone: { state.finish(onReveal: onReveal, completion: close) }
            ))
        case .setup:
            let state = SetupState(enabled: enabled)
            let finish = { (apply: Bool) in state.finish(apply: apply, onReveal: onReveal, completion: close) }
            panel.onCancel = { finish(false) }
            panel.contentView = FirstClickHostingView(rootView: SetupView(
                state: state, barSlots: barSlots, onDone: { finish(true) }, onCancel: { finish(false) }
            ))
        }
        panel.setFrame(screen.frame, display: false)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel.orderOut(nil)
        panel.contentView = nil
        isVisible = false
    }
}

/// Dot setup: the dots fly down from the bar onto a card per tool, where each can be switched on
/// or off, then fly back up.
@MainActor
final class SetupState: ObservableObject {
    /// Where the dots are: one per card, or in the bar.
    enum Phase { case choose, bar }

    private let original: Set<Dot>

    /// Starts in the bar, where the dots are, then flies them down to the cards.
    @Published var phase = Phase.bar
    @Published var selection: Set<Dot>
    @Published var isFrosted = false
    /// Closing: the frost clears edges-first and the overlay's dots hand over to the bar's.
    @Published var isDismissing = false
    private var isFinishing = false

    init(enabled: Set<Dot>) {
        original = enabled
        selection = enabled
    }

    func start() {
        withAnimation(.easeOut(duration: 0.4)) { isFrosted = true }
        after(0.05) { self.phase = .choose }
    }

    func toggle(_ dot: Dot) {
        if selection.contains(dot) { selection.remove(dot) } else { selection.insert(dot) }
    }

    /// Flies the dots to the bar (`apply` false puts back the original set), hands over to the
    /// real bar, then clears the frost.
    func finish(apply: Bool, onReveal: @escaping (Set<Dot>) -> Void, completion: @escaping () -> Void) {
        guard !isFinishing, !apply || !selection.isEmpty else { return }
        isFinishing = true
        if !apply { selection = original }
        phase = .bar
        after(0.75) {
            onReveal(self.selection)
            self.isDismissing = true
            withAnimation(.easeIn(duration: 0.45)) { self.isFrosted = false }
        }
        after(1.3, completion)
    }

    private func after(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
}

struct SetupView: View {
    private enum Metrics {
        static let cardSize = CGSize(width: 250, height: 290)
        static let cardSpacing: CGFloat = 24
        static let maxColumns = 4
        /// The card's dot is drawn by the dot layer, centered this far below the card's top.
        static let cardDotCenter: CGFloat = 76
        static let cardDot: CGFloat = 64
    }

    @ObservedObject var state: SetupState
    /// Centers of the bar's slots for a given slot count, in this view's coordinates.
    let barSlots: (Int) -> [CGPoint]
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cards = cardFrames(in: size)
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.55))
                    .mask(FrostSweep(progress: state.isFrosted ? 1 : 0, recedesToCenter: state.isDismissing))

                choose(cards: cards, midX: size.width / 2)
                plus
                ForEach(Array(Dot.allCases.enumerated()), id: \.element) { index, dot in
                    dotView(dot, index: index, cards: cards, size: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear { state.start() }
    }

    // MARK: Choose

    /// Cards are centered, so the heading and buttons share the screen's `midX`.
    private func choose(cards: [CGRect], midX: CGFloat) -> some View {
        let isShown = state.phase == .choose
        let top = cards.first?.minY ?? 0
        let bottom = cards.last?.maxY ?? 0
        return ZStack {
            VStack(spacing: 10) {
                Text("Choose your dots")
                    .font(.system(size: 34, weight: .bold))
                Text("Each dot is a tool. Turn on the ones you need, and add more any time from + in the bar.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .position(x: midX, y: top - 70)

            ForEach(Array(Dot.allCases.enumerated()), id: \.element) { index, dot in
                DotCard(dot: dot, isSelected: state.selection.contains(dot)) { state.toggle(dot) }
                    .frame(width: cards[index].width, height: cards[index].height)
                    .opacity(isShown ? 1 : 0)
                    .offset(y: isShown ? 0 : 24)
                    .animation(isShown ? .spring(response: 0.5, dampingFraction: 0.85).delay(0.12 + Double(index) * 0.05)
                                       : .easeIn(duration: 0.15),
                               value: isShown)
                    .position(x: cards[index].midX, y: cards[index].midY)
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(PillButtonStyle(isProminent: false))
                    .keyboardShortcut(.cancelAction)
                    .disabled(!isShown)
                Button("Done", action: onDone)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isShown || state.selection.isEmpty)
            }
            .position(x: midX, y: bottom + 64)
        }
        .opacity(isShown ? 1 : 0)
        .animation(isShown ? .easeOut(duration: 0.35).delay(0.1) : .easeIn(duration: 0.2), value: isShown)
        .allowsHitTesting(isShown)
    }

    /// A row of cards (wrapping after four), centered on screen.
    private func cardFrames(in size: CGSize) -> [CGRect] {
        let count = Dot.allCases.count
        let columns = min(count, Metrics.maxColumns)
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let card = Metrics.cardSize, gap = Metrics.cardSpacing
        let totalHeight = CGFloat(rows) * card.height + CGFloat(rows - 1) * gap
        let top = (size.height - totalHeight) / 2 + 20
        return (0..<count).map { index in
            let row = index / columns
            let inRow = min(columns, count - row * columns)
            let rowWidth = CGFloat(inRow) * card.width + CGFloat(inRow - 1) * gap
            let column = index % columns
            return CGRect(x: (size.width - rowWidth) / 2 + CGFloat(column) * (card.width + gap),
                          y: top + CGFloat(row) * (card.height + gap),
                          width: card.width, height: card.height)
        }
    }

    // MARK: Dots

    private var chosen: [Dot] { Dot.allCases.filter(state.selection.contains) }
    private var slotCount: Int { chosen.count + (chosen.count < Dot.allCases.count ? 1 : 0) }

    /// The + dot fades in at the end of the bar when some tools are left off.
    @ViewBuilder
    private var plus: some View {
        let isShown = state.phase == .bar && chosen.count < Dot.allCases.count && !state.isDismissing
        if let slot = barSlots(slotCount).last {
            PlusDot(diameter: DotsBarMetrics.dotDiameter)
                .opacity(isShown ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(isShown ? 0.35 : 0), value: isShown)
                .position(slot)
                .allowsHitTesting(false)
        }
    }

    private func dotView(_ dot: Dot, index: Int, cards: [CGRect], size: CGSize) -> some View {
        let isSelected = state.selection.contains(dot)
        let placement = placement(of: dot, index: index, cards: cards, size: size)
        let fill: Color = switch state.phase {
        case .choose: isSelected ? dot.tint : .white.opacity(0.14)
        case .bar: .white.opacity(0.9)
        }
        let inBar = state.phase == .bar
        return Circle()
            .fill(fill)
            .frame(width: placement.diameter, height: placement.diameter)
            .overlay(
                Image(systemName: dot.symbol)
                    .font(.system(size: placement.diameter * 0.4, weight: .semibold))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.55))
                    .opacity(state.phase == .choose ? 1 : 0)
            )
            .shadow(color: inBar ? .black.opacity(0.35) : dot.tint.opacity(isSelected ? 0.55 : 0), radius: inBar ? 2 : 20)
            .scaleEffect(placement.scale)
            .opacity(placement.opacity)
            .animation(.easeOut(duration: 0.2), value: state.selection)
            .animation(.easeOut(duration: 0.2), value: state.isDismissing)
            .animation(.spring(response: 0.65, dampingFraction: 0.82).delay(Double(index) * 0.05), value: state.phase)
            .position(placement.center)
            .allowsHitTesting(false)
    }

    private struct Placement {
        var center: CGPoint
        var diameter: CGFloat
        var scale: CGFloat = 1
        var opacity: Double = 1
    }

    private func placement(of dot: Dot, index: Int, cards: [CGRect], size: CGSize) -> Placement {
        switch state.phase {
        case .choose:
            let card = cards[index]
            return Placement(center: CGPoint(x: card.midX, y: card.minY + Metrics.cardDotCenter),
                             diameter: Metrics.cardDot)
        case .bar:
            let slots = barSlots(slotCount)
            // Once in the bar, the overlay's dots fade out over the real bar's identical ones.
            let handOver: Double = state.isDismissing ? 0 : 1
            if let position = chosen.firstIndex(of: dot) {
                return Placement(center: slots[position], diameter: DotsBarMetrics.dotDiameter, opacity: handOver)
            }
            // Left off: shrink away into the + slot.
            return Placement(center: slots.last ?? CGPoint(x: size.width / 2, y: 0),
                             diameter: DotsBarMetrics.dotDiameter, scale: 0.3, opacity: 0)
        }
    }
}

/// One tool on the setup screen. The whole card toggles it; its dot is drawn above by the dot layer.
private struct DotCard: View {
    let dot: Dot
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(spacing: 10) {
            Color.clear.frame(height: 118) // the dot sits here
            Text(dot.title)
                .font(.system(size: 20, weight: .semibold))
            Text(dot.summary)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(dot.shortcutLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().strokeBorder(Color.white.opacity(0.2)))
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Color.white.opacity(isSelected ? 0.1 : 0.04)))
        .overlay(shape.strokeBorder(isSelected ? dot.tint.opacity(0.7) : Color.white.opacity(0.1),
                                    lineWidth: isSelected ? 2 : 1))
        .overlay(alignment: .topTrailing) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? dot.tint : Color.white.opacity(0.3))
                .padding(16)
        }
        .scaleEffect(isHovering ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovering)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .contentShape(shape)
        .onTapGesture(perform: onToggle)
        .onHover { isHovering = $0 }
    }
}

private struct PillButtonStyle: ButtonStyle {
    var isProminent = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isProminent ? Color.black : Color.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Capsule().fill(isProminent ? Color.white : Color.white.opacity(0.14)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Capsule())
    }
}
