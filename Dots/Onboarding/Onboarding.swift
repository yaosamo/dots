import AppKit
import SwiftUI

/// Full-screen welcome (first launch) and dot setup (the bar's + dot). Both end with the chosen
/// dots flying into the bar, where the real bar takes over as the frost clears.
@MainActor
final class OnboardingController {
    private let panel = FloatingPanel(level: DotsLevel.onboarding, keyable: true)
    private var state: OnboardingState?

    var isVisible: Bool { state != nil }

    /// `onReveal` gets the chosen dots as they land in the bar, before the overlay fades.
    func show(mode: OnboardingState.Mode, enabled: Set<Dot>, onReveal: @escaping (Set<Dot>) -> Void) {
        guard state == nil, let screen = NSScreen.primary else { return }
        let state = OnboardingState(mode: mode, enabled: enabled)
        self.state = state

        let finish: (Bool) -> Void = { [weak self, weak state] apply in
            state?.finish(apply: apply, onReveal: onReveal) { self?.close() }
        }
        // Esc cancels setup; the welcome has to be finished with Done.
        panel.onCancel = mode == .setup ? { finish(false) } : nil
        panel.setFrame(screen.frame, display: false)
        panel.contentView = FirstClickHostingView(rootView: OnboardingView(
            state: state,
            barSlots: { DotsBarMetrics.slotCenters(slots: $0, on: screen) },
            onDone: { finish(true) },
            onCancel: { finish(false) }
        ))
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel.orderOut(nil)
        panel.contentView = nil
        state = nil
    }
}

@MainActor
final class OnboardingState: ObservableObject {
    enum Mode { case welcome, setup }

    /// Where the dots are: introduced mid-screen, one per card, or sitting in the bar.
    enum Phase { case intro, choose, bar }

    let mode: Mode
    private let original: Set<Dot>

    @Published var phase: Phase
    @Published var selection: Set<Dot>
    @Published var isFrosted = false
    /// Closing: the frost clears edges-first and the overlay's dots hand over to the bar's.
    @Published var isDismissing = false
    @Published var isIntroShown = false
    private var isFinishing = false

    init(mode: Mode, enabled: Set<Dot>) {
        self.mode = mode
        original = enabled
        // Setup starts with the dots where they are in the bar, then flies them down to the cards.
        phase = mode == .welcome ? .intro : .bar
        selection = mode == .welcome ? Set(Dot.allCases) : enabled
    }

    func start() {
        switch mode {
        case .welcome:
            withAnimation(.easeOut(duration: 1.2)) { isFrosted = true }
            after(0.5) { self.isIntroShown = true }
        case .setup:
            withAnimation(.easeOut(duration: 0.4)) { isFrosted = true }
            after(0.05) { self.phase = .choose }
        }
    }

    func getStarted() {
        phase = .choose
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

struct OnboardingView: View {
    private enum Metrics {
        static let cardSize = CGSize(width: 250, height: 290)
        static let cardSpacing: CGFloat = 24
        static let maxColumns = 4
        /// The card's dot is drawn by the dot layer, centered this far below the card's top.
        static let cardDotCenter: CGFloat = 76
        static let cardDot: CGFloat = 64
        static let introDot: CGFloat = 34
        static let introSpacing: CGFloat = 64
    }

    @ObservedObject var state: OnboardingState
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

                intro(in: size)
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

    // MARK: Intro

    private func intro(in size: CGSize) -> some View {
        let isShown = state.phase == .intro && state.isIntroShown
        return VStack(spacing: 14) {
            Text("Meet Dots")
                .font(.system(size: 48, weight: .bold))
            Text("Small tools that live at the top of your screen.")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Button("Get started", action: state.getStarted)
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 22)
                .disabled(state.phase != .intro)
        }
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown ? 0 : 12)
        .animation(isShown ? .easeOut(duration: 0.5).delay(0.6) : .easeIn(duration: 0.2), value: isShown)
        .position(x: size.width / 2, y: size.height / 2 + 90)
        .allowsHitTesting(isShown)
    }

    // MARK: Choose

    /// Cards are centered, so the heading and buttons share the screen's `midX`.
    private func choose(cards: [CGRect], midX: CGFloat) -> some View {
        let isShown = state.phase == .choose
        let top = cards.first?.minY ?? 0
        let bottom = cards.last?.maxY ?? 0
        return ZStack {
            VStack(spacing: 10) {
                Text(state.mode == .welcome ? "Pick your dots" : "Choose your dots")
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
                if state.mode == .setup {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(PillButtonStyle(isProminent: false))
                        .keyboardShortcut(.cancelAction)
                        .disabled(!isShown)
                }
                Button("Done", action: onDone)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    // Off while hidden too, so Return during the intro can't reach it.
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
        case .intro: dot.tint
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
            .animation(.spring(response: 0.5, dampingFraction: 0.55).delay(Double(index) * 0.14), value: state.isIntroShown)
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
        case .intro:
            let offset = CGFloat(index) - CGFloat(Dot.allCases.count - 1) / 2
            return Placement(center: CGPoint(x: size.width / 2 + offset * Metrics.introSpacing, y: size.height / 2 - 40),
                             diameter: Metrics.introDot,
                             scale: state.isIntroShown ? 1 : 0.01,
                             opacity: state.isIntroShown ? 1 : 0)
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
