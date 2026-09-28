import AppKit
import SceneKit
import SwiftUI

/// Dot 4: a countdown on a real 3D die. It drops in, bounces off the screen's edges and rolls to a
/// stop on its bottom edge; toss it by dragging and letting go. Click it to start or pause; hover
/// for −/+ a minute, reset and ✕ (put it away), or click the time to type one. When time's up it
/// chimes and hops once.
@MainActor
final class DiceTimerModel: ObservableObject {
    private static let durationKey = "timer.duration"
    static let minute: TimeInterval = 60
    static let longest: TimeInterval = 99 * minute

    /// The set time, remembered between launches.
    @Published private(set) var duration: TimeInterval {
        didSet { UserDefaults.standard.set(duration, forKey: Self.durationKey) }
    }
    /// Running: when it hits zero. Paused or idle: nil.
    @Published private(set) var endDate: Date?
    /// Paused partway through.
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var isDone = false
    /// Over the die or its time label: shows the −/+ and reset controls.
    @Published var isHovering = false
    /// On screen: the time label only ticks while it is (a hidden window's SwiftUI timelines keep
    /// running otherwise).
    @Published var isShown = false

    var onDone: (() -> Void)?
    private var alarm: DispatchWorkItem?

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.durationKey)
        duration = saved > 0 ? saved : 5 * Self.minute
    }

    var isRunning: Bool { endDate != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining ?? duration
    }

    /// Click: start, pause, resume, or (once done) reset.
    func primaryAction() {
        if isDone {
            reset()
        } else if let endDate {
            pausedRemaining = max(0, endDate.timeIntervalSinceNow)
            self.endDate = nil
            alarm?.cancel()
        } else {
            schedule(remaining(at: .now))
        }
    }

    /// ±1 minute, while not running. Up to 99 minutes; − stops at a minute (or at a shorter typed time).
    func adjust(minutes: Int) {
        guard !isRunning else { return }
        let base = pausedRemaining ?? duration
        set(min(max(base + Double(minutes) * Self.minute, min(base, Self.minute)), Self.longest))
    }

    /// A typed time (see `parse`), while not running.
    func set(_ seconds: TimeInterval) {
        guard !isRunning else { return }
        pausedRemaining = nil
        isDone = false
        duration = min(max(seconds.rounded(), 1), Self.longest)
    }

    /// "10s", "90 sec", "2m", "1:30" or a bare number of minutes ("5", "0.5"); nil if it isn't a time.
    static func parse(_ text: String) -> TimeInterval? {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2, let minutes = Double(parts[0].isEmpty ? "0" : parts[0]), let seconds = Double(parts[1]),
           seconds < 60 {
            return positive(minutes * minute + seconds)
        }
        let number = text.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(number) else { return nil }
        let unit = text.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        switch unit {
        case "", "m", "min", "mins", "minute", "minutes": return positive(value * minute)
        case "s", "sec", "secs", "second", "seconds": return positive(value)
        default: return nil
        }
    }

    private static func positive(_ seconds: TimeInterval) -> TimeInterval? { seconds > 0 ? seconds : nil }

    func reset() {
        alarm?.cancel()
        endDate = nil
        pausedRemaining = nil
        isDone = false
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    private func schedule(_ seconds: TimeInterval) {
        pausedRemaining = nil
        endDate = Date(timeIntervalSinceNow: seconds)
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        alarm = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func finish() {
        endDate = nil
        pausedRemaining = 0
        isDone = true
        NSSound(named: "Glass")?.play()
        onDone?()
    }
}

/// The die's flight in screen points (bottom-left origin): position of its center, velocity, and
/// a 3D spin that turns it as it goes. Rolling on the floor ties the spin to the speed.
struct DicePhysics {
    static let gravity: Float = -2600
    /// Slower than this (points per second), a hit doesn't rebound at all.
    static let restingImpact: Float = 250
    /// Hits this fast or faster get the most bounce.
    static let hardImpact: Float = 2600

    /// How much of an impact comes back as rebound: little for a soft hit, a lot for a hard one,
    /// so how high it bounces follows how hard it hit (roughly with the square of the speed).
    static func restitution(for impact: Float, soft: Float = 0.15, hard: Float = 0.55) -> Float {
        let t = min(max((impact - restingImpact) / (hardImpact - restingImpact), 0), 1)
        return soft + (hard - soft) * t * t * (3 - 2 * t)
    }
    /// Half the die's width on screen: how close its center gets to an edge.
    static let radius: CGFloat = 72

    var position: CGPoint
    var velocity = SIMD2<Float>(0, 0)
    /// Angular velocity in radians per second, in the die's world (x right, y up, z toward you).
    var spin = SIMD3<Float>(0, 0, 0)
    var orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))

    /// Advances by `dt` inside `bounds` (where the center may go). True once the die is at rest.
    mutating func step(_ dt: Float, in bounds: CGRect) -> Bool {
        velocity.y += Self.gravity * dt
        position.x += CGFloat(velocity.x * dt)
        position.y += CGFloat(velocity.y * dt)

        if position.x < bounds.minX, velocity.x < 0 { position.x = bounds.minX; bounceSideways() }
        if position.x > bounds.maxX, velocity.x > 0 { position.x = bounds.maxX; bounceSideways() }
        if position.y > bounds.maxY, velocity.y > 0 {
            position.y = bounds.maxY
            velocity.y = -velocity.y * Self.restitution(for: velocity.y)
        }
        if position.y < bounds.minY, velocity.y < 0 {
            position.y = bounds.minY
            let impact = -velocity.y
            velocity.y = impact < Self.restingImpact ? 0 : impact * Self.restitution(for: impact, hard: 0.5)
            // A harder landing grips the floor more: from 90% of the sideways speed kept down to 65%.
            velocity.x *= 0.9 - 0.25 * min(impact / Self.hardImpact, 1)
            if impact > Self.restingImpact { tumble(by: impact) }
        }

        let isOnFloor = position.y <= bounds.minY + 0.5 && velocity.y == 0
        if isOnFloor {
            // Rolling: friction slows it, and the spin follows the speed (rolls right = clockwise).
            velocity.x *= exp(-2.6 * dt)
            let rolling = SIMD3<Float>(0, 0, -velocity.x / Float(Self.radius))
            spin += (rolling - spin) * min(1, 12 * dt)
        } else {
            spin *= exp(-0.3 * dt)
        }
        let speed = simd_length(spin)
        if speed > 0.0001 {
            orientation = simd_normalize(simd_quatf(angle: speed * dt, axis: spin / speed) * orientation)
        }
        return isOnFloor && abs(velocity.x) < 10
    }

    /// A throw or a hop: new velocity with a tumble to match.
    mutating func launch(_ newVelocity: SIMD2<Float>) {
        velocity = newVelocity
        tumble(by: simd_length(newVelocity))
    }

    private mutating func bounceSideways() {
        let impact = abs(velocity.x)
        velocity.x = -velocity.x * Self.restitution(for: impact)
        tumble(by: impact)
    }

    /// Knocks the spin about in proportion to the hit, so bounces look lively.
    private mutating func tumble(by impact: Float) {
        let strength = min(impact / 700, 1.4) * 9
        spin += SIMD3(.random(in: -1...1), .random(in: -1...1), .random(in: -1...1)) * strength
    }

    /// The orientation nearest the current one with a face flat on the floor and one facing you.
    var settledOrientation: simd_quatf {
        let matrix = simd_float3x3(orientation)
        func nearestAxis(_ v: SIMD3<Float>, excluding used: [SIMD3<Float>]) -> SIMD3<Float> {
            let axes: [SIMD3<Float>] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
            return axes.filter { axis in !used.contains { abs(simd_dot($0, axis)) > 0.5 } }
                .max { simd_dot($0, v) < simd_dot($1, v) }!
        }
        let x = nearestAxis(matrix.columns.0, excluding: [])
        let y = nearestAxis(matrix.columns.1, excluding: [x])
        return simd_quatf(simd_float3x3(x, y, simd_cross(x, y)))
    }
}

@MainActor
final class DiceTimerController: DotFeature {
    /// The die's view, plus the time label above it. The window is this size and only ever moves.
    private static let dieSize: CGFloat = 300
    private static let labelHeight: CGFloat = 34
    /// The label sits just above the resting die, over the empty top of the die's view (which is
    /// big enough for the die's corners as it tumbles).
    private static let labelY = dieSize / 2 + DicePhysics.radius + 6
    private static let windowSize = CGSize(width: dieSize + 20, height: max(dieSize, labelY + labelHeight))
    /// The die's center within the window.
    private static let dieCenter = CGPoint(x: windowSize.width / 2, y: dieSize / 2)

    private let model = DiceTimerModel()
    /// Keyable only while the time is typed, so clicking the die never takes the keyboard.
    private let panel = FloatingPanel(level: DotsLevel.camera, keyable: false)
    private let die = DieView(frame: NSRect(origin: .zero, size: CGSize(width: dieSize, height: dieSize)))
    private let onVisibilityChange: (Bool) -> Void

    private var physics = DicePhysics(position: .zero)
    private var loop: Timer?
    private var lastTick: CFTimeInterval = 0
    /// Recent pointer positions while dragging, for the throw's velocity.
    private var dragSamples: [(time: CFTimeInterval, point: CGPoint)] = []
    private var dragOffset = CGSize.zero
    private var dragDistance: CGFloat = 0

    private(set) var isVisible = false

    init(onVisibilityChange: @escaping (Bool) -> Void) {
        self.onVisibilityChange = onVisibilityChange
        let content = NSView(frame: NSRect(origin: .zero, size: Self.windowSize))
        die.frame.origin = CGPoint(x: (Self.windowSize.width - Self.dieSize) / 2, y: 0)
        content.addSubview(die)
        let label = FirstClickHostingView(rootView: TimeLabel(
            model: model,
            onEdit: { [weak self] in self?.beginTyping() },
            onEndEdit: { [weak self] in self?.endTyping() },
            onRemove: { [weak self] in self?.remove() }
        ))
        label.frame = NSRect(x: 0, y: Self.labelY, width: Self.windowSize.width, height: Self.labelHeight)
        content.addSubview(label)
        panel.contentView = content
        panel.setContentSize(Self.windowSize)

        die.onPress = { [weak self] in self?.press(at: $0) }
        die.onDrag = { [weak self] in self?.drag(to: $0) }
        die.onRelease = { [weak self] in self?.release() }
        die.onHover = { [weak self] hovering in
            withAnimation(.easeOut(duration: 0.15)) { self?.model.isHovering = hovering }
        }
        model.onDone = { [weak self] in self?.hop() }
    }

    func show() {
        guard !isVisible, let screen = NSScreen.primary else { return }
        // Dropped in near the top-left, thrown gently to the right.
        let bounds = Self.bounds(on: screen)
        physics.position = CGPoint(x: bounds.minX + 120, y: bounds.maxY)
        physics.orientation = simd_quatf(angle: .random(in: 0...(2 * .pi)), axis: simd_normalize(SIMD3(1, 1, 0.3)))
        physics.spin = .zero
        physics.launch(SIMD2(.random(in: 250...600), 0))
        moveWindow()
        panel.orderFrontRegardless()
        isVisible = true
        model.isShown = true
        onVisibilityChange(true)
        startLoop()
    }

    func hide() {
        guard isVisible else { return }
        stopLoop()
        panel.orderOut(nil)
        isVisible = false
        model.isShown = false
        onVisibilityChange(false)
    }

    /// ✕: stops the timer and puts the die away.
    private func remove() {
        model.reset()
        endTyping()
        hide()
    }

    /// Typing needs the key window, and Dots only has one while active.
    private func beginTyping() {
        panel.keyable = true
        NSApp.activate()
        panel.makeKey()
    }

    /// Hands the keyboard back to the app that had it.
    private func endTyping() {
        guard panel.keyable else { return }
        panel.keyable = false
        panel.resignKey()
        NSApp.deactivate()
    }

    /// Where the die's center can go: the whole screen, edge to edge (over the Dock at the bottom),
    /// leaving room for the time label at the top.
    private static func bounds(on screen: NSScreen) -> CGRect {
        let radius = DicePhysics.radius
        let frame = screen.frame
        return CGRect(x: frame.minX + radius, y: frame.minY + radius,
                      width: frame.width - radius * 2, height: frame.height - radius * 2 - labelHeight - 6)
    }

    // MARK: Simulation

    private func startLoop() {
        guard loop == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        loop = timer
    }

    private func stopLoop() {
        loop?.invalidate()
        loop = nil
    }

    private func tick() {
        guard let screen = NSScreen.primary else { return }
        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastTick, 1.0 / 30))
        lastTick = now
        let isAtRest = physics.step(dt, in: Self.bounds(on: screen))
        die.orientation = physics.orientation
        moveWindow()
        if isAtRest { settle() }
    }

    /// Rolls onto the nearest face and stops the loop.
    private func settle() {
        stopLoop()
        physics.velocity = .zero
        physics.spin = .zero
        physics.orientation = physics.settledOrientation
        die.setOrientation(physics.orientation, animated: true)
    }

    private func moveWindow() {
        panel.setFrameOrigin(NSPoint(x: physics.position.x - Self.dieCenter.x, y: physics.position.y - Self.dieCenter.y))
    }

    /// Time's up: one hop, then it settles again.
    private func hop() {
        guard isVisible else { return }
        physics.launch(SIMD2(.random(in: -160...160), 950))
        startLoop()
    }

    // MARK: Pointer

    private func press(at point: CGPoint) {
        stopLoop()
        physics.velocity = .zero
        dragOffset = CGSize(width: point.x - physics.position.x, height: point.y - physics.position.y)
        dragDistance = 0
        dragSamples = [(CACurrentMediaTime(), point)]
    }

    private func drag(to point: CGPoint) {
        guard let last = dragSamples.last else { return }
        dragDistance += hypot(point.x - last.point.x, point.y - last.point.y)
        let now = CACurrentMediaTime()
        dragSamples.append((now, point))
        dragSamples.removeAll { now - $0.time > 0.08 }
        physics.position = CGPoint(x: point.x - dragOffset.width, y: point.y - dragOffset.height)
        moveWindow()
    }

    /// A click toggles the timer; a drag throws the die with the pointer's last motion.
    private func release() {
        defer { dragSamples = [] }
        guard dragDistance > 4 else {
            model.primaryAction()
            startLoop() // in case it was held in the air
            return
        }
        if let first = dragSamples.first, let last = dragSamples.last, last.time > first.time {
            let dt = CGFloat(last.time - first.time)
            let throwVelocity = SIMD2<Float>(Float((last.point.x - first.point.x) / dt),
                                             Float((last.point.y - first.point.y) / dt))
            let speed = simd_length(throwVelocity)
            physics.launch(speed > 5000 ? throwVelocity / speed * 5000 : throwVelocity)
        }
        startLoop()
    }
}

/// The time above the die. While hovered and not running: −1 minute, +1 minute and reset, and a
/// click on the time turns it into a field to type one ("10s", "2m", "1:30"). ✕ shows on hover
/// whenever, to put the die away.
private struct TimeLabel: View {
    @ObservedObject var model: DiceTimerModel
    let onEdit: () -> Void
    let onEndEdit: () -> Void
    let onRemove: () -> Void

    @State private var draft: String?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !model.isShown)) { timeline in
            HStack(spacing: 2) {
                if showsControls { control("minus") { model.adjust(minutes: -1) } }
                if let draft {
                    TextField("1:30", text: Binding(get: { draft }, set: { self.draft = $0 }))
                        .textFieldStyle(.plain)
                        .font(Self.font)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DiceTimerModel.parse(draft) == nil && !draft.isEmpty ? Color.red : .white)
                        .frame(width: 56)
                        .focused($isFieldFocused)
                        .onSubmit(commit)
                        .onExitCommand { self.draft = nil; onEndEdit() }
                        .onChange(of: isFieldFocused) { _, focused in if !focused { commit() } }
                } else {
                    Text(DiceTimerModel.format(model.remaining(at: timeline.date)))
                        .font(Self.font)
                        .monospacedDigit()
                        .foregroundStyle(model.isDone ? Color.red : Color.white.opacity(model.isRunning ? 1 : 0.75))
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { if !model.isRunning { startTyping() } }
                        .help(model.isRunning ? "" : "Click to type a time, like 10s, 2m or 1:30")
                }
                if showsControls {
                    control("plus") { model.adjust(minutes: 1) }
                    control("arrow.counterclockwise") { model.reset() }
                }
                if model.isHovering || draft != nil { control("xmark", action: onRemove) }
            }
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { model.isHovering = hovering } }
    }

    private static let font = Font.system(size: 14, weight: .semibold, design: .rounded)

    private var showsControls: Bool { model.isHovering && !model.isRunning && draft == nil }

    private func startTyping() {
        onEdit()
        draft = ""
        isFieldFocused = true
    }

    /// Sets a valid time; anything else (or nothing) leaves the time as it was.
    private func commit() {
        guard let text = draft else { return }
        draft = nil
        if let seconds = DiceTimerModel.parse(text) { model.set(seconds) }
        onEndEdit()
    }

    private func control(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// A SceneKit die with pips on its six faces, lit from the top left, on a clear background.
/// Reports presses, drags and hover in screen coordinates.
final class DieView: SCNView {
    var onPress: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onRelease: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    private let cube = SCNNode()

    var orientation: simd_quatf {
        get { cube.simdOrientation }
        set { cube.simdOrientation = newValue }
    }

    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        allowsCameraControl = false

        let scene = SCNScene()
        let box = SCNBox(width: 0.85, height: 0.85, length: 0.85, chamferRadius: 0.14)
        // SCNBox faces: front, right, back, left, top, bottom. Opposite faces add up to 7.
        box.materials = [1, 3, 6, 4, 2, 5].map(Self.faceMaterial)
        cube.geometry = box
        scene.rootNode.addChildNode(cube)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 24
        camera.position = SCNVector3(0, 0, 4.2)
        scene.rootNode.addChildNode(camera)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.7, -0.5, 0)
        scene.rootNode.addChildNode(key)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 420
        scene.rootNode.addChildNode(fill)

        self.scene = scene
        pointOfView = camera
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setOrientation(_ orientation: simd_quatf, animated: Bool) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.22 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        cube.simdOrientation = orientation
        SCNTransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
                                       owner: self))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.set()
        onPress?(NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) { onDrag?(NSEvent.mouseLocation) }

    override func mouseUp(with event: NSEvent) {
        NSCursor.openHand.set()
        onRelease?()
    }

    /// A white face with dark pips in the classic layout for `pips`.
    private static func faceMaterial(pips: Int) -> SCNMaterial {
        let size = CGFloat(256)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(white: 0.97, alpha: 1).setFill()
            rect.fill()
            let spots: [Int: [CGPoint]] = [
                1: [CGPoint(x: 0.5, y: 0.5)],
                2: [CGPoint(x: 0.28, y: 0.72), CGPoint(x: 0.72, y: 0.28)],
                3: [CGPoint(x: 0.28, y: 0.72), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.72, y: 0.28)],
                4: [CGPoint(x: 0.28, y: 0.28), CGPoint(x: 0.28, y: 0.72), CGPoint(x: 0.72, y: 0.28), CGPoint(x: 0.72, y: 0.72)],
                5: [CGPoint(x: 0.28, y: 0.28), CGPoint(x: 0.28, y: 0.72), CGPoint(x: 0.5, y: 0.5),
                    CGPoint(x: 0.72, y: 0.28), CGPoint(x: 0.72, y: 0.72)],
                6: [CGPoint(x: 0.28, y: 0.25), CGPoint(x: 0.28, y: 0.5), CGPoint(x: 0.28, y: 0.75),
                    CGPoint(x: 0.72, y: 0.25), CGPoint(x: 0.72, y: 0.5), CGPoint(x: 0.72, y: 0.75)],
            ]
            NSColor(red: 0.24, green: 0.18, blue: 0.36, alpha: 1).setFill()
            let radius = size * 0.085
            for spot in spots[pips] ?? [] {
                NSBezierPath(ovalIn: NSRect(x: spot.x * size - radius, y: spot.y * size - radius,
                                            width: radius * 2, height: radius * 2)).fill()
            }
            return true
        }
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.specular.contents = NSColor(white: 0.35, alpha: 1)
        material.shininess = 0.6
        return material
    }
}
