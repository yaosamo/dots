import AppKit
import SwiftUI

/// The first-launch welcome: clouds come down over the screen, then the dots emerge one by one above a
/// line of text. Clicking a dot previews its tool; Done flies the chosen dots up into the bar as the
/// clouds lift. Every timing, size and word comes from `WelcomeTuning` (Welcome Lab, in debug builds).
@MainActor
final class WelcomeState: ObservableObject, OnboardingFlow {
    /// Floating mid-screen, or flying to / sitting in the bar.
    enum Phase { case dots, bar }

    let startDate = Date()
    /// Used by the camera preview; stopped when the preview goes or the welcome ends.
    let camera = CameraSession()

    @Published var phase = Phase.dots
    /// How many dots have emerged (one by one); then the text and Done follow.
    @Published var shownDots = 0
    @Published var isTextShown = false
    @Published var isHintShown = false
    @Published var previewed: Dot?
    @Published var selection = Set(Dot.allCases)
    /// When the clouds started to leave, once the dots have landed in the bar.
    @Published var leftAt: Date?
    private var isFinishing = false
    private var isCancelled = false

    /// Schedules the dots, text and hint from the tuning's timings (the clouds follow the clock; see
    /// CloudFrame).
    func start() {
        let tuning = WelcomeTuning.shared.values
        // The clouds don't have to finish coming down: the dots start partway through.
        let first = tuning.cloudDescend * tuning.cloudDotsAt
        for index in Dot.allCases.indices {
            after(first + Double(index) * tuning.dotBeat) { self.shownDots = index + 1 }
        }
        let text = first + Double(Dot.allCases.count - 1) * tuning.dotBeat + tuning.textDelay
        after(text) { self.isTextShown = true }
        after(text + tuning.hintDelay) { self.isHintShown = true }
    }

    /// Opens the dot's preview, or closes it if it's already open.
    func tap(_ dot: Dot) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { previewed = previewed == dot ? nil : dot }
    }

    func toggle(_ dot: Dot) {
        if selection.contains(dot) { selection.remove(dot) } else { selection.insert(dot) }
    }

    /// Flies the chosen dots to the bar and shows the real bar under them as they land. The clouds
    /// lift away as the dots fly.
    func finish(onReveal: @escaping (Set<Dot>) -> Void, completion: @escaping () -> Void) {
        guard !isFinishing, !selection.isEmpty else { return }
        isFinishing = true
        withAnimation(.easeIn(duration: 0.15)) { previewed = nil }
        camera.stop()
        phase = .bar
        let landing = BarFlight.landing
        leftAt = Date()
        // The real bar comes in right under the dots once they've all landed.
        after(landing) { onReveal(self.selection) }
        // Once the bar is there under them and the clouds have lifted.
        after(max(landing + 0.1, WelcomeTuning.shared.values.cloudLeave) + 0.05, completion)
    }

    /// Ended from outside (Welcome Lab's Replay or Close): nothing scheduled runs, and the camera stops.
    func cancel() {
        isCancelled = true
        camera.stop()
    }

    private func after(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isCancelled else { return }
            action()
        }
    }
}

/// The clouds' script, from the seconds since the welcome opened (and since they started leaving),
/// handed to the clouds' shader (see CloudsView).
struct CloudFrame {
    var time: Double
    var descend: Double
    var leave: Double = 0
    var fade: Double

    init(time: TimeInterval, leaving: TimeInterval?, tuning: WelcomeTuning.Values) {
        func easeOut(_ x: Double) -> Double { 1 - pow(1 - min(max(x, 0), 1), 3) }
        func easeIn(_ x: Double) -> Double { pow(min(max(x, 0), 1), 2) }
        self.time = time
        descend = easeOut(time / tuning.cloudDescend)
        fade = min(time / 0.4, 1)
        if let leaving {
            leave = easeIn(leaving / tuning.cloudLeave)
            fade *= 1 - easeIn(leaving / tuning.cloudLeave)
        }
    }
}

struct WelcomeView: View {
    private enum Metrics {
        static let cardWidth: CGFloat = 360
        /// Room for the preview card above the dots; the card sits at its bottom.
        static let cardSlot: CGFloat = 360
    }

    @ObservedObject var state: WelcomeState
    /// Centers of the bar's slots for a given slot count, in this view's coordinates.
    let barSlots: (Int) -> [CGPoint]
    let onDone: () -> Void

    @ObservedObject private var tuning = WelcomeTuning.shared
    /// Different clouds each time.
    @State private var seed = Float.random(in: 0...50)

    private var dotSize: CGFloat { tuning.values.dotSize }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + tuning.values.dotsOffsetY)
            ZStack {
                CloudsView(startDate: state.startDate, leftAt: state.leftAt, seed: seed)
                caption(below: center)
                preview(above: center)
                plus
                dots(around: center, size: size)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .light)
        .onAppear(perform: state.start)
    }

    // MARK: Text and Done

    /// The welcome's type, shared with dot setup's heading.
    static func textFont(size: CGFloat) -> Font {
        .custom("SFCompact-Light", size: size)
    }

    /// Hangs from just below the dots, so longer text grows downward.
    private func caption(below center: CGPoint) -> some View {
        let isShown = state.phase == .dots && state.isTextShown
        let values = tuning.values
        let top = center.y + dotSize / 2 + values.textGap
        let slot: CGFloat = 800
        return VStack(spacing: 10) {
            // One simple style throughout: SF Compact Light.
            Text(values.message)
                .font(Self.textFont(size: values.textSize))
                .foregroundStyle(Color.black.opacity(values.textOpacity))
                .frame(width: values.textWidth)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                Text(values.hint)
                    .font(Self.textFont(size: values.hintSize))
                    .foregroundStyle(Color.black.opacity(values.textOpacity * 0.47))
                    .padding(.top, 18)
                Button("Done", action: onDone)
                    .buttonStyle(WelcomeButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isShown || !state.isHintShown || state.selection.isEmpty)
                    .padding(.top, 14)
            }
            .opacity(state.isHintShown ? 1 : 0)
            .animation(.easeOut(duration: 0.4), value: state.isHintShown)
        }
        .multilineTextAlignment(.center)
        .fixedSize()
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown ? 0 : 12)
        .animation(isShown ? .easeOut(duration: 0.5) : .easeIn(duration: 0.2), value: isShown)
        .frame(height: slot, alignment: .top)
        .position(x: center.x, y: top + slot / 2)
        .allowsHitTesting(isShown)
    }

    // MARK: Preview

    @ViewBuilder
    private func preview(above center: CGPoint) -> some View {
        if state.phase == .dots, let dot = state.previewed {
            PreviewCard(dot: dot, isIncluded: state.selection.contains(dot), camera: state.camera) {
                state.toggle(dot)
            }
            .frame(width: Metrics.cardWidth)
            .id(dot)
            .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            .frame(height: Metrics.cardSlot, alignment: .bottom)
            .position(x: center.x, y: center.y - dotSize / 2 - 24 - Metrics.cardSlot / 2)
        }
    }

    // MARK: Dots

    private var chosen: [Dot] { Dot.allCases.filter(state.selection.contains) }
    private var slotCount: Int { chosen.count + (chosen.count < Dot.allCases.count ? 1 : 0) }

    /// Floating dots bob gently, each on its own beat; in the bar they hold still.
    private func dots(around center: CGPoint, size: CGSize) -> some View {
        TimelineView(.animation(paused: state.phase != .dots)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(Dot.allCases.enumerated()), id: \.element) { index, dot in
                    let bob = state.phase == .dots ? sin(time * 1.7 + Double(index) * 1.3) * 4 : 0
                    dotView(dot, index: index, center: center, size: size)
                        .offset(y: bob)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func dotView(_ dot: Dot, index: Int, center: CGPoint, size: CGSize) -> some View {
        let placement = placement(of: dot, index: index, center: center, size: size)
        let inBar = state.phase == .bar
        let isPreviewed = state.previewed == dot
        return Button { state.tap(dot) } label: {
            // Plain white dots, no icons.
            Circle()
                .fill(.white)
                .frame(width: placement.diameter, height: placement.diameter)
                .overlay(Circle().strokeBorder(dot.tint, lineWidth: isPreviewed ? 2.5 : 0).padding(-6))
                .shadow(color: .black.opacity(inBar ? 0.35 : 0.14), radius: inBar ? 2 : 14, y: inBar ? 0 : 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(inBar || index >= state.shownDots)
        // Left out of the bar: dimmed until switched back on in its preview.
        .opacity(!inBar && !state.selection.contains(dot) ? 0.45 : 1)
        .scaleEffect(placement.scale)
        .blur(radius: placement.blur)
        .opacity(placement.opacity)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPreviewed)
        .animation(.easeOut(duration: 0.2), value: state.selection)
        .animation(BarFlight.animation(index: index), value: state.phase)
        // Emerging: out of focus and faint to crisp, in its own place.
        .animation(.easeOut(duration: tuning.values.dotEmerge), value: state.shownDots)
        .position(placement.center)
    }

    /// The + dot fades in at the end of the bar when some tools are left off, and stays over the
    /// clouds while they leave, like the dots.
    @ViewBuilder
    private var plus: some View {
        let isShown = state.phase == .bar && chosen.count < Dot.allCases.count
        if let slot = barSlots(slotCount).last {
            PlusDot(diameter: DotsBarMetrics.dotDiameter)
                .opacity(isShown ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(isShown ? 0.35 : 0), value: isShown)
                .position(slot)
                .allowsHitTesting(false)
        }
    }

    private struct Placement {
        var center: CGPoint
        var diameter: CGFloat
        var scale: CGFloat = 1
        var opacity: Double = 1
        var blur: CGFloat = 0
    }

    private func placement(of dot: Dot, index: Int, center: CGPoint, size: CGSize) -> Placement {
        switch state.phase {
        case .dots:
            let offset = CGFloat(index) - CGFloat(Dot.allCases.count - 1) / 2
            let spot = CGPoint(x: center.x + offset * tuning.values.dotSpacing, y: center.y)
            // Until its turn, each dot waits in its place, blurred into the background.
            guard index < state.shownDots else {
                return Placement(center: spot, diameter: dotSize, scale: tuning.values.dotStartScale,
                                 opacity: 0, blur: tuning.values.dotBlur)
            }
            return Placement(center: spot, diameter: dotSize)
        case .bar:
            let slots = barSlots(slotCount)
            // The welcome's dots stay over the clouds as they leave; the real bar, right under them
            // but below the overlay, takes over when the overlay closes.
            if let position = chosen.firstIndex(of: dot) {
                return Placement(center: slots[position], diameter: DotsBarMetrics.dotDiameter)
            }
            // Left off: shrink away into the + slot.
            return Placement(center: slots.last ?? CGPoint(x: size.width / 2, y: 0),
                             diameter: DotsBarMetrics.dotDiameter, scale: 0.3, opacity: 0)
        }
    }
}

// MARK: - Preview card

/// A dot's preview above the floating dots: a live demo of the tool, what it does, its shortcut,
/// and whether it goes in the bar.
private struct PreviewCard: View {
    let dot: Dot
    let isIncluded: Bool
    let camera: CameraSession
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            demo
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(alignment: .firstTextBaseline) {
                Text(dot.title)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(dot.shortcutLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().strokeBorder(Color.black.opacity(0.15)))
            }
            Text(dot.summary)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("In your bar")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle("In your bar", isOn: Binding(get: { isIncluded }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(dot.tint)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        )
    }

    @ViewBuilder
    private var demo: some View {
        switch dot {
        case .camera: CameraDemo(session: camera)
        case .tasks: TasksDemo()
        case .pen: PenDemo()
        case .timer: TimerDemo()
        case .clipboard: ClipboardDemo()
        }
    }
}

/// The real camera, in the camera dot's circle. Asks for permission the first time.
private struct CameraDemo: View {
    let session: CameraSession

    @State private var isDenied = false

    var body: some View {
        ZStack {
            DemoBackdrop()
            if isDenied {
                VStack(spacing: 6) {
                    Image(systemName: "video.slash.fill").font(.title2)
                    Text("Allow the camera in System Settings › Privacy").font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            } else {
                LiveCamera(session: session, diameter: 120)
                    .frame(width: 120, height: 120)
            }
        }
        .onAppear { session.start { isDenied = true } }
        .onDisappear { session.stop() }
    }
}

private struct LiveCamera: NSViewRepresentable {
    let session: CameraSession
    let diameter: CGFloat

    func makeNSView(context: Context) -> CameraBubbleView {
        let view = CameraBubbleView(session: session.session)
        view.dragsWindow = false
        view.setBubble(size: CGSize(width: diameter, height: diameter), cornerRadius: diameter / 2, duration: 0)
        return view
    }

    func updateNSView(_ nsView: CameraBubbleView, context: Context) {}
}

/// Tasks checking off one by one, squeezing down as they're done, on a loop.
private struct TasksDemo: View {
    private static let titles = ["Book flights", "Call Sam back", "Ship the deck"]
    private static let step: TimeInterval = 0.9

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.step)) { timeline in
            // 0 done, 1, 2, all 3, then a beat to show them all done before starting over.
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate / Self.step) % 5
            let done = min(tick, Self.titles.count)
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add a task…")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.9)))
                ForEach(Self.titles.indices, id: \.self) { index in
                    let isDone = index < done
                    HStack(spacing: 8) {
                        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isDone ? Color.green : Color.secondary)
                        Text(Self.titles[index])
                            .strikethrough(isDone)
                            .foregroundStyle(isDone ? .secondary : .primary)
                        Spacer()
                    }
                    .font(.system(size: isDone ? 11 : 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, isDone ? 4 : 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.65)))
                }
            }
            .padding(12)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: done)
        }
        .background(DemoBackdrop())
    }
}

/// A red pen circling a line in a little window and underlining another, on a loop.
private struct PenDemo: View {
    private static let loop: TimeInterval = 3.2

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop)
            let circle = min(max(time / 1.1, 0), 1)
            let underline = min(max((time - 1.25) / 0.5, 0), 1)
            let ink = time > 2.6 ? 1 - (time - 2.6) / 0.6 : 1
            Canvas { context, size in
                let window = CGRect(x: 18, y: 14, width: size.width - 36, height: size.height - 28)
                context.fill(Path(roundedRect: window, cornerRadius: 10), with: .color(.white))
                for index in 0..<3 {
                    let light = CGRect(x: window.minX + 10 + CGFloat(index) * 10, y: window.minY + 9, width: 6, height: 6)
                    context.fill(Path(ellipseIn: light), with: .color(Color(white: 0.86)))
                }
                let widths: [CGFloat] = [0.55, 0.8, 0.45, 0.7]
                for (index, width) in widths.enumerated() {
                    let line = CGRect(x: window.minX + 14, y: window.minY + 28 + CGFloat(index) * 18,
                                      width: (window.width - 28) * width, height: 7)
                    context.fill(Path(roundedRect: line, cornerRadius: 3.5), with: .color(Color(white: 0.88)))
                }
                let pen = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                let red = GraphicsContext.Shading.color(.red.opacity(ink))
                // A loose, slightly tilted loop around the start of the second line.
                let target = CGRect(x: window.minX + 6, y: window.minY + 36, width: 118, height: 28)
                let tilt = CGAffineTransform(translationX: target.midX, y: target.midY)
                    .rotated(by: -0.06).translatedBy(x: -target.midX, y: -target.midY)
                context.stroke(Path(ellipseIn: target).applying(tilt).trimmedPath(from: 0, to: circle), with: red, style: pen)
                var stroke = Path()
                let y = window.minY + 28 + 3 * 18 + 13
                stroke.move(to: CGPoint(x: window.minX + 14, y: y))
                stroke.addLine(to: CGPoint(x: window.minX + 14 + (window.width - 28) * 0.7, y: y - 2))
                context.stroke(stroke.trimmedPath(from: 0, to: underline), with: red, style: pen)
            }
        }
        .background(DemoBackdrop())
    }
}

/// A little die dropping in, bouncing, and counting down from 0:05, on a loop.
private struct TimerDemo: View {
    private static let loop: TimeInterval = 7.5

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop)
            // Falls for 0.45 s, then a hop that decays to rest.
            let fall = time < 0.45 ? 1 - pow(time / 0.45, 2) : 0
            let hop = time >= 0.45 && time < 0.85 ? sin((time - 0.45) / 0.4 * .pi) * 0.12 : 0
            let lift = (fall + hop) * 150
            let remaining = max(0, 5 - max(0, time - 1.2))
            let isDone = remaining == 0
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            ZStack {
                shape.fill(LinearGradient(colors: [.white, Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                Text(DiceTimerModel.format(remaining))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isDone ? Color.red : Color.black.opacity(0.8))
            }
            .frame(width: 64, height: 64)
            .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
            .rotationEffect(.degrees(isDone ? sin(time * 40) * 6 : fall * 160))
            .offset(y: 30 - lift)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DemoBackdrop())
    }
}

/// Copies arriving at the top of a short list, newest first, on a loop.
private struct ClipboardDemo: View {
    private static let copies = ["dots.app/welcome", "Meeting moved to 3pm", "#FF6B6B", "Thanks, Sam!"]
    private static let step: TimeInterval = 1.1

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.step)) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate / Self.step) % (Self.copies.count + 2)
            let shown = Array(Self.copies.prefix(min(tick + 1, Self.copies.count)).reversed().prefix(3))
            VStack(spacing: 6) {
                ForEach(Array(shown.enumerated()), id: \.element) { index, copy in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.2)))
                        Text(copy).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.85)))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shown)
        }
        .background(DemoBackdrop())
    }
}

private struct DemoBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(white: 0.95), Color(white: 0.89)], startPoint: .top, endPoint: .bottom)
    }
}

private struct WelcomeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("SFCompact-Regular", size: 16)) // the welcome's type; Light is too thin here
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.85)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Capsule())
    }
}
