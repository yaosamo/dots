import SwiftUI

/// Something drawn over a screenshot: a pen stroke, an arrow or a box, in a color or in one of the
/// pen's shader inks. Points are canvas points from the shot's top-left corner, so marks move with
/// the shot when the padding or the shape of the frame changes.
struct Mark: Identifiable, Equatable {
    enum Kind: CaseIterable {
        case pen, arrow, box

        var title: String {
            switch self {
            case .pen: "Pen"
            case .arrow: "Arrow"
            case .box: "Box"
            }
        }

        var symbol: String {
            switch self {
            case .pen: "scribble"
            case .arrow: "arrow.up.right"
            case .box: "rectangle"
            }
        }

        var key: String {
            switch self {
            case .pen: "p"
            case .arrow: "a"
            case .box: "r"
            }
        }
    }

    enum Ink: Equatable {
        case color(MarkColor)
        /// Electric, fire or rainbow.
        case effect(Brush)
    }

    var id = UUID()
    let kind: Kind
    let ink: Ink
    /// A pen's samples; an arrow's or a box's start and end.
    var points: [CGPoint]

    var lineWidth: CGFloat {
        switch ink {
        case .color: kind == .pen ? 5 : 6
        case .effect(let brush): max(brush.lineWidth, 4)
        }
    }

    var bounds: CGRect {
        points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
            .insetBy(dx: -(lineWidth + headLength), dy: -(lineWidth + headLength))
    }

    private var headLength: CGFloat { kind == .arrow ? 28 : 0 }

    /// What's stroked, and for an arrow, its filled head.
    var paths: (stroke: Path, fill: Path?) {
        guard let start = points.first, let end = points.last else { return (Path(), nil) }
        switch kind {
        case .pen:
            return (StrokeLayer.path(for: points), nil)
        case .box:
            let rect = CGRect(start: start, end: end)
            return (Path(roundedRect: rect, cornerRadius: min(8, rect.width / 2, rect.height / 2), style: .continuous), nil)
        case .arrow:
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 0 else { return (Path(), nil) }
            let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
            let head = min(max(lineWidth * 4, 20), headLength, length * 0.5)
            let base = CGPoint(x: end.x - direction.x * head, y: end.y - direction.y * head)
            let side = CGPoint(x: -direction.y * head * 0.6, y: direction.x * head * 0.6)
            var shaft = Path()
            shaft.move(to: start)
            // Into the head a little, so the round cap doesn't poke out past its sides.
            shaft.addLine(to: CGPoint(x: base.x + direction.x * head * 0.3, y: base.y + direction.y * head * 0.3))
            var tip = Path()
            tip.move(to: end)
            tip.addLine(to: CGPoint(x: base.x + side.x, y: base.y + side.y))
            tip.addLine(to: CGPoint(x: base.x - side.x, y: base.y - side.y))
            tip.closeSubpath()
            return (shaft, tip)
        }
    }
}

/// Bright and bold, to point things out on any screenshot.
enum MarkColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, white, black

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: Color(hex: 0xFF3B30)
        case .orange: Color(hex: 0xFF9500)
        case .yellow: Color(hex: 0xFFCC00)
        case .green: Color(hex: 0x34C759)
        case .blue: Color(hex: 0x0A84FF)
        case .white: .white
        case .black: Color(hex: 0x1C1C1E)
        }
    }
}

/// The finished picture: the background, the shot with its title bar, corners and shadow, the edge
/// effect and the marks, in canvas points. The editor shows it scaled to fit; the export renders this
/// same view at the shot's own resolution.
struct FramedShot: View {
    struct Layout {
        /// The whole picture.
        let canvas: CGSize
        /// The shot with its title bar, if any.
        let content: CGRect
        /// The shot itself, inside `content`.
        let image: CGRect
    }

    /// Canvas points per point of the shot: a shot bigger than this many points across is scaled
    /// down to it, so padding, corners, ink widths and effects look the same on a full 5K screen as
    /// on a small region. Exports scale back up, so no pixels are lost.
    static func canvasScale(for shotSize: CGSize) -> CGFloat {
        min(1, 1400 / max(shotSize.width, shotSize.height, 1))
    }

    static func layout(shotSize: CGSize, style: FrameStyle) -> Layout {
        let chrome = style.chrome.height
        let content = CGSize(width: shotSize.width, height: shotSize.height + chrome)
        var canvas = CGSize(width: content.width + style.padding * 2, height: content.height + style.padding * 2)
        if let ratio = style.aspect.ratio {
            if canvas.width / canvas.height < ratio {
                canvas.width = canvas.height * ratio
            } else {
                canvas.height = canvas.width / ratio
            }
        }
        let origin = CGPoint(x: (canvas.width - content.width) / 2, y: (canvas.height - content.height) / 2)
        return Layout(canvas: canvas, content: CGRect(origin: origin, size: content),
                      image: CGRect(x: origin.x, y: origin.y + chrome, width: shotSize.width, height: shotSize.height))
    }

    let image: CGImage
    /// In canvas points.
    let shotSize: CGSize
    let style: FrameStyle
    let marks: [Mark]
    /// For the shader effects; an export freezes the moment it's taken.
    let time: Double

    private let tuning = ShaderTuning.values

    var body: some View {
        let layout = Self.layout(shotSize: shotSize, style: style)
        ZStack(alignment: .topLeading) {
            background(layout)
            if style.edge == .cloud {
                // Behind the shot, so it sits in the cloud rather than under a sheet of it.
                cloud(layout)
            }
            content(layout)
            if let brush = style.edge.brush {
                edge(brush, layout: layout)
            }
            MarkLayer(marks: marks, time: time, tuning: tuning)
                .offset(x: layout.content.minX, y: layout.content.minY)
        }
        .frame(width: layout.canvas.width, height: layout.canvas.height, alignment: .topLeading)
        .clipped()
    }

    private var radius: CGFloat {
        min(style.cornerRadius, shotSize.width / 2, shotSize.height / 2)
    }

    @ViewBuilder
    private func background(_ layout: Layout) -> some View {
        let size = layout.canvas
        switch style.background {
        case .clear:
            Color.clear.frame(width: size.width, height: size.height)
        case .custom:
            style.customColor.color.frame(width: size.width, height: size.height)
        case .blur:
            // Scaled past the edges first, so the blur doesn't fade out to clear at them.
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(1.25)
                .blur(radius: max(size.width, size.height) * 0.04)
                .saturation(1.3)
                .overlay(Color.black.opacity(0.08))
                .frame(width: size.width, height: size.height)
                .clipped()
        default:
            LinearGradient(colors: style.background.colors ?? [], startPoint: .topLeading, endPoint: .bottomTrailing)
                // A soft sheen from the top-left, so the backdrop has some depth.
                .overlay(RadialGradient(colors: [.white.opacity(0.22), .clear], center: .topLeading,
                                        startRadius: 0, endRadius: max(size.width, size.height) * 0.8))
                .frame(width: size.width, height: size.height)
        }
    }

    private func content(_ layout: Layout) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return VStack(spacing: 0) {
            switch style.chrome {
            case .none: EmptyView()
            case .light, .dark: TitleBar(isDark: style.chrome == .dark).frame(height: style.chrome.height)
            case .safari: SafariBar(address: style.address).frame(height: style.chrome.height)
            }
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: shotSize.width, height: shotSize.height)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.black.opacity(style.chrome == .none ? 0 : 0.12), lineWidth: 0.5))
        // A wide soft shadow and a tight one underneath, like the whiteboard's.
        .shadow(color: .black.opacity(0.4 * style.shadow), radius: 44 * style.shadow, y: 22 * style.shadow)
        .shadow(color: .black.opacity(0.18 * style.shadow), radius: 3 * style.shadow, y: 1)
        .frame(width: layout.content.width, height: layout.content.height)
        .offset(x: layout.content.minX, y: layout.content.minY)
    }

    /// The camera's rim (CameraView's EffectRim), around the shot.
    private func edge(_ brush: Brush, layout: Layout) -> some View {
        var values = tuning
        values.rainbowScale *= 1.5
        values.fireHeight *= 1.6
        values.fireSpeed *= 1.4
        values.fireWobble *= 1.3
        let margin = brush.layerMargin(values)
        let ring = RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(brush.inkColor, lineWidth: brush.lineWidth)
            .frame(width: layout.content.width, height: layout.content.height)
            .padding(.horizontal, margin.width)
            .padding(.vertical, margin.height)
        return Group {
            if brush == .fire {
                ring.layerEffect(ShaderLibrary.rimFire(.float(Float(time)), .float(Float(values.fireHeight)),
                                                       .float(Float(values.fireSpeed)), .float(Float(values.fireWobble))),
                                 maxSampleOffset: margin)
            } else {
                ring.brushEffect(brush, time: Float(time), origin: .zero, tuning: values)
            }
        }
        .offset(x: layout.content.minX - margin.width, y: layout.content.minY - margin.height)
    }

    /// The camera's cloud (CameraShaders.metal's cameraCloud): a bank along the shot's bottom,
    /// spilling into the padding. Drawn behind the shot, so the puffs billow out around its lower
    /// edge without covering it.
    private func cloud(_ layout: Layout) -> some View {
        let shot = layout.content.size
        let room = max(style.padding, 24)
        let side = min(shot.width * 0.28, room)
        let below = min(shot.width * 0.3, room)
        let size = CGSize(width: shot.width + side * 2, height: shot.width * 0.4 + below)
        return Rectangle()
            .fill(.white)
            .colorEffect(ShaderLibrary.cameraCloud(.float2(size), .float2(shot), .float(Float(side)),
                                                   .float(Float(below)), .float(Float(time))))
            .frame(width: size.width, height: size.height)
            .offset(x: layout.content.minX - side, y: layout.content.maxY + below - size.height)
    }
}

/// A macOS window's title bar: three traffic lights.
private struct TitleBar: View {
    let isDark: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach([0xFF5F57, 0xFEBC2E, 0x28C840] as [UInt32], id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 12, height: 12)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDark ? Color(hex: 0x2B2B2D) : Color(hex: 0xECECEC))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(isDark ? 0.5 : 0.1)).frame(height: 0.5)
        }
    }
}

/// Safari's toolbar, light: traffic lights, the sidebar button and back/forward, the address field
/// in the middle, then share, new tab and the tab overview. A narrow shot keeps the lights and the
/// address field.
private struct SafariBar: View {
    let address: String

    private static let icon = Color(hex: 0x6E6E73)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(isCompact: false)
            bar(isCompact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xF4F4F5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.1)).frame(height: 0.5)
        }
    }

    private func bar(isCompact: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach([0xFF5F57, 0xFEBC2E, 0x28C840] as [UInt32], id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                        .frame(width: 12, height: 12)
                }
            }
            if !isCompact {
                HStack(spacing: 18) {
                    glyph("sidebar.left")
                    HStack(spacing: 14) {
                        glyph("chevron.left")
                        glyph("chevron.right").opacity(0.4)
                    }
                }
                .padding(.leading, 22)
            }
            Spacer(minLength: 16)
            addressField
                .frame(minWidth: isCompact ? 0 : 280, maxWidth: 560)
                .layoutPriority(1)
            Spacer(minLength: 16)
            if !isCompact {
                HStack(spacing: 18) {
                    glyph("square.and.arrow.up")
                    glyph("plus")
                    glyph("square.on.square")
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private var addressField: some View {
        HStack(spacing: 5) {
            if !address.isEmpty {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Self.icon)
            }
            Text(address)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x1D1D1F))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.06)))
        .overlay(alignment: .trailing) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Self.icon)
                .padding(.trailing, 10)
        }
    }

    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Self.icon)
    }
}

/// The marks: colored ones in one Canvas, then one layer per shader ink, sized to its marks, like
/// the pen's StrokeStack.
struct MarkLayer: View {
    let marks: [Mark]
    let time: Double
    let tuning: ShaderTuning.Values

    var body: some View {
        let colored = marks.filter { if case .color = $0.ink { true } else { false } }
        let brushes = [Brush.electric, .fire, .rainbow].filter { brush in marks.contains { $0.ink == .effect(brush) } }
        ZStack(alignment: .topLeading) {
            if !colored.isEmpty {
                layer(colored, origin: area(of: colored, margin: .zero).origin) { mark in
                    if case .color(let color) = mark.ink { color.color } else { .clear }
                }
                .frame(width: area(of: colored, margin: .zero).width, height: area(of: colored, margin: .zero).height)
                .offset(x: area(of: colored, margin: .zero).minX, y: area(of: colored, margin: .zero).minY)
            }
            ForEach(brushes) { brush in
                let inked = marks.filter { $0.ink == .effect(brush) }
                let area = area(of: inked, margin: brush.layerMargin(tuning))
                layer(inked, origin: area.origin) { _ in brush.inkColor }
                    .frame(width: area.width, height: area.height)
                    .brushEffect(brush, time: Float(time), origin: area.origin, tuning: tuning)
                    .offset(x: area.minX, y: area.minY)
            }
        }
        .allowsHitTesting(false)
    }

    private func area(of marks: [Mark], margin: CGSize) -> CGRect {
        marks.map(\.bounds).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -margin.width, dy: -margin.height)
    }

    private func layer(_ marks: [Mark], origin: CGPoint, color: @escaping (Mark) -> Color) -> some View {
        Canvas { context, _ in
            context.translateBy(x: -origin.x, y: -origin.y)
            for mark in marks {
                let paths = mark.paths
                let style = StrokeStyle(lineWidth: mark.lineWidth, lineCap: .round, lineJoin: .round)
                context.stroke(paths.stroke, with: .color(color(mark)), style: style)
                if let fill = paths.fill {
                    context.fill(fill, with: .color(color(mark)))
                    // Rounds the head's corners.
                    context.stroke(fill, with: .color(color(mark)), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
        }
    }
}
