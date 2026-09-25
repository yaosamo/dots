import AppKit
import SwiftUI

/// The first-launch welcome: a storm gathers in the middle of the screen, blows apart, and leaves
/// the dots floating under "Welcome to Dots." Clicking a dot previews its tool; Done flies the
/// chosen dots up into the bar.
@MainActor
final class WelcomeState: ObservableObject {
    /// Floating mid-screen, or flying to / sitting in the bar.
    enum Phase { case dots, bar }

    let startDate = Date()
    /// Used by the camera preview; stopped when the preview goes or the welcome ends.
    let camera = CameraSession()

    @Published var phase = Phase.dots
    /// The dots pop out of the blast; the text and Done follow.
    @Published var areDotsShown = false
    @Published var isTextShown = false
    @Published var isHintShown = false
    @Published var previewed: Dot?
    @Published var selection = Set(Dot.allCases)
    /// When the clouds started to leave, once the dots have landed in the bar.
    @Published var leftAt: Date?
    private var isFinishing = false

    func start() {
        after(StormFrame.burstTime + 0.05) { self.areDotsShown = true }
        after(StormFrame.burstTime + 0.6) { self.isTextShown = true }
        after(StormFrame.burstTime + 1.3) { self.isHintShown = true }
    }

    /// Opens the dot's preview, or closes it if it's already open.
    func tap(_ dot: Dot) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { previewed = previewed == dot ? nil : dot }
    }

    func toggle(_ dot: Dot) {
        if selection.contains(dot) { selection.remove(dot) } else { selection.insert(dot) }
    }

    /// Flies the chosen dots to the bar, hands over to the real bar as they land, then blows the
    /// clouds away.
    func finish(onReveal: @escaping (Set<Dot>) -> Void, completion: @escaping () -> Void) {
        guard !isFinishing, !selection.isEmpty else { return }
        isFinishing = true
        withAnimation(.easeIn(duration: 0.15)) { previewed = nil }
        camera.stop()
        phase = .bar
        after(0.75) {
            onReveal(self.selection)
            self.leftAt = Date()
        }
        after(1.4, completion)
    }

    private func after(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
}

/// The storm's script, all worked out from the seconds since the welcome opened (and since the
/// clouds started leaving), and handed to the `welcomeStorm` shader.
private struct StormFrame {
    /// The blast: the biggest flash, the clouds fly apart, the dots appear.
    static let burstTime: TimeInterval = 3

    /// Strikes that build up to the blast: when, how bright, and where (0…1 of the screen).
    private static let strikes: [(time: TimeInterval, strength: Float, at: CGPoint)] = [
        (1.1, 0.45, CGPoint(x: 0.47, y: 0.46)),
        (1.7, 0.6, CGPoint(x: 0.54, y: 0.52)),
        (2.15, 0.5, CGPoint(x: 0.5, y: 0.44)),
        (2.55, 0.8, CGPoint(x: 0.45, y: 0.53)),
        (burstTime, 1.6, CGPoint(x: 0.5, y: 0.5)),
    ]

    var gather: Float
    var burst: Float
    var flash: Float = 0
    var flashPoint = CGPoint(x: 0.5, y: 0.5)
    var fade: Float

    init(time: TimeInterval, leaving: TimeInterval?) {
        func smooth(_ x: Double) -> Double {
            let t = min(max(x, 0), 1)
            return t * t * (3 - 2 * t)
        }
        func easeOut(_ x: Double) -> Double { 1 - pow(1 - min(max(x, 0), 1), 3) }

        gather = Float(smooth((time - 0.2) / (Self.burstTime - 0.4)))
        var burst = easeOut((time - Self.burstTime) / 1.0)
        var fade = smooth(time / 0.8)
        if let leaving {
            burst += easeOut(leaving / 0.6) * 1.2 // the rest of the clouds blow off-screen
            fade *= 1 - smooth(leaving / 0.55)
        }
        self.burst = Float(burst)
        self.fade = Float(fade)
        // The brightest strike right now, each dying away fast.
        for strike in Self.strikes where time >= strike.time {
            let brightness = strike.strength * Float(exp(-(time - strike.time) * 9))
            if brightness > flash {
                flash = brightness
                flashPoint = strike.at
            }
        }
    }
}

struct WelcomeView: View {
    private enum Metrics {
        static let dot: CGFloat = 48
        static let spacing: CGFloat = 96
        static let cardWidth: CGFloat = 360
        /// Room for the preview card above the dots; the card sits at its bottom.
        static let cardSlot: CGFloat = 360
    }

    @ObservedObject var state: WelcomeState
    /// Centers of the bar's slots for a given slot count, in this view's coordinates.
    let barSlots: (Int) -> [CGPoint]
    let onDone: () -> Void

    /// Different clouds each time.
    @State private var seed = Float.random(in: 0...50)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2 - 10)
            ZStack {
                storm(size: size)
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

    private func storm(size: CGSize) -> some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSince(state.startDate)
            let frame = StormFrame(time: time, leaving: state.leftAt.map { timeline.date.timeIntervalSince($0) })
            Rectangle()
                .fill(.white)
                .colorEffect(ShaderLibrary.welcomeStorm(
                    .float2(size), .float(Float(time)), .float(frame.gather), .float(frame.burst),
                    .float(frame.flash), .float2(frame.flashPoint), .float(frame.fade), .float(seed)
                ))
        }
    }

    // MARK: Text and Done

    private func caption(below center: CGPoint) -> some View {
        let isShown = state.phase == .dots && state.isTextShown
        return VStack(spacing: 10) {
            Text("Welcome to Dots.")
                .font(.system(size: 46, weight: .bold))
            Text("Mini tools to make your life a bit more fun.")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Group {
                Text("Click a dot to see what it does.")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
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
        .position(x: center.x, y: center.y + 170)
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
            .position(x: center.x, y: center.y - Metrics.dot / 2 - 24 - Metrics.cardSlot / 2)
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
            Circle()
                .fill(.white)
                .frame(width: placement.diameter, height: placement.diameter)
                .overlay(
                    Image(systemName: dot.symbol)
                        .font(.system(size: placement.diameter * 0.38, weight: .semibold))
                        .foregroundStyle(isPreviewed ? dot.tint : Color.black.opacity(0.45))
                        .opacity(inBar ? 0 : 1)
                )
                .overlay(Circle().strokeBorder(dot.tint, lineWidth: isPreviewed ? 2.5 : 0).padding(-6))
                .shadow(color: .black.opacity(inBar ? 0.35 : 0.14), radius: inBar ? 2 : 14, y: inBar ? 0 : 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(inBar || !state.areDotsShown)
        // Left out of the bar: dimmed until switched back on in its preview.
        .opacity(!inBar && !state.selection.contains(dot) ? 0.45 : 1)
        .scaleEffect(placement.scale)
        .opacity(placement.opacity)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPreviewed)
        .animation(.easeOut(duration: 0.2), value: state.selection)
        .animation(.easeOut(duration: 0.2), value: state.leftAt != nil)
        .animation(.spring(response: 0.65, dampingFraction: 0.82).delay(Double(index) * 0.05), value: state.phase)
        .animation(.spring(response: 0.55, dampingFraction: 0.6).delay(Double(index) * 0.12), value: state.areDotsShown)
        .position(placement.center)
    }

    /// The + dot fades in at the end of the bar when some tools are left off.
    @ViewBuilder
    private var plus: some View {
        let isShown = state.phase == .bar && chosen.count < Dot.allCases.count && state.leftAt == nil
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
    }

    private func placement(of dot: Dot, index: Int, center: CGPoint, size: CGSize) -> Placement {
        switch state.phase {
        case .dots:
            // Until the blast they wait, tiny and hidden, at its center.
            guard state.areDotsShown else {
                return Placement(center: center, diameter: Metrics.dot, scale: 0.01, opacity: 0)
            }
            let offset = CGFloat(index) - CGFloat(Dot.allCases.count - 1) / 2
            return Placement(center: CGPoint(x: center.x + offset * Metrics.spacing, y: center.y), diameter: Metrics.dot)
        case .bar:
            let slots = barSlots(slotCount)
            // Once in the bar, the welcome's dots fade out over the real bar's.
            let handOver: Double = state.leftAt == nil ? 1 : 0
            if let position = chosen.firstIndex(of: dot) {
                return Placement(center: slots[position], diameter: DotsBarMetrics.dotDiameter, opacity: handOver)
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
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.85)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Capsule())
    }
}
