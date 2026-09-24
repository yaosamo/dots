import AppKit
import SwiftUI

/// Whiteboard tools, a tiny Excalidraw. Only offered while the whiteboard is up; otherwise the
/// selected brush draws. Letter keys pick them, as in Excalidraw.
enum BoardTool: String, CaseIterable, Identifiable {
    case select, marker, rectangle, ellipse, arrow, line, text, eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .marker: "Marker"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .arrow: "Arrow"
        case .line: "Line"
        case .text: "Text"
        case .eraser: "Eraser"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .marker: "pencil.tip"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.right"
        case .line: "line.diagonal"
        case .text: "textformat"
        case .eraser: "eraser"
        }
    }

    var key: String {
        switch self {
        case .select: "v"
        case .marker: "p"
        case .rectangle: "r"
        case .ellipse: "o"
        case .arrow: "a"
        case .line: "l"
        case .text: "t"
        case .eraser: "e"
        }
    }

    /// The shape a drag with this tool draws, if it draws one.
    var shapeKind: InkModel.Shape.Kind? {
        switch self {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .arrow: .arrow
        case .line: .line
        case .select, .marker, .text, .eraser: nil
        }
    }

    init?(key: String?) {
        guard let tool = BoardTool.allCases.first(where: { $0.key == key }) else { return nil }
        self = tool
    }
}

/// Excalidraw's default stroke colors, used by the marker, shapes and text.
enum BoardColor: String, CaseIterable, Identifiable {
    case black, red, green, blue, orange

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .black: NSColor(red: 0x1e / 255, green: 0x1e / 255, blue: 0x1e / 255, alpha: 1)
        case .red: NSColor(red: 0xe0 / 255, green: 0x31 / 255, blue: 0x31 / 255, alpha: 1)
        case .green: NSColor(red: 0x2f / 255, green: 0x9e / 255, blue: 0x44 / 255, alpha: 1)
        case .blue: NSColor(red: 0x19 / 255, green: 0x71 / 255, blue: 0xc2 / 255, alpha: 1)
        case .orange: NSColor(red: 0xf0 / 255, green: 0x8c / 255, blue: 0x00 / 255, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

/// The whiteboard's dot grid. Shapes, text and moved objects snap to it; hold ⌘ to place freely.
/// Dots sit on multiples of `spacing` in screen coordinates, so snapping and drawing agree.
enum BoardGrid {
    static let spacing: CGFloat = 20
    static let dotRadius: CGFloat = 1.2

    static func snap(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x / spacing).rounded() * spacing, y: (point.y / spacing).rounded() * spacing)
    }

    /// The dots inside `rect` (screen coordinates), as one path in the rect's local coordinates.
    static func dots(in rect: CGRect) -> Path {
        var path = Path()
        let firstX = (rect.minX / spacing).rounded(.up) * spacing
        let firstY = (rect.minY / spacing).rounded(.up) * spacing
        for x in stride(from: firstX, through: rect.maxX, by: spacing) {
            for y in stride(from: firstY, through: rect.maxY, by: spacing) {
                path.addEllipse(in: CGRect(x: x - rect.minX - dotRadius, y: y - rect.minY - dotRadius,
                                           width: dotRadius * 2, height: dotRadius * 2))
            }
        }
        return path
    }
}

/// Board text, measured with AppKit so hit-testing matches what the Canvas draws.
enum BoardText {
    static let size: CGFloat = 26

    static var nsFont: NSFont { .systemFont(ofSize: size, weight: .medium) }
    static var font: Font { .system(size: size, weight: .medium) }
    static var lineHeight: CGFloat { ceil(nsFont.ascender - nsFont.descender + nsFont.leading) }

    static func size(of text: String) -> CGSize {
        let size = (text as NSString).size(withAttributes: [.font: nsFont])
        return CGSize(width: ceil(size.width), height: max(ceil(size.height), lineHeight))
    }
}

/// Clean, exact geometry for whiteboard shapes.
enum ShapeGeometry {
    static let lineWidth: CGFloat = 2.5
    static let cornerRadius: CGFloat = 6
    /// How far arrowheads can reach past a shape's bounds.
    static let margin: CGFloat = 16

    static func path(for shape: InkModel.Shape) -> Path {
        let rect = CGRect(start: shape.start, end: shape.end)
        var path = Path()
        switch shape.kind {
        case .rectangle:
            let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        case .ellipse:
            path.addEllipse(in: rect)
        case .line:
            path.move(to: shape.start)
            path.addLine(to: shape.end)
        case .arrow:
            path.move(to: shape.start)
            path.addLine(to: shape.end)
            let length = hypot(shape.end.x - shape.start.x, shape.end.y - shape.start.y)
            let angle = atan2(shape.end.y - shape.start.y, shape.end.x - shape.start.x)
            let head = min(18, length * 0.35)
            let wings = [-0.45, 0.45].map { side in
                CGPoint(x: shape.end.x + cos(angle + .pi + side) * head, y: shape.end.y + sin(angle + .pi + side) * head)
            }
            path.move(to: wings[0])
            path.addLine(to: shape.end)
            path.addLine(to: wings[1])
        case .text:
            break
        }
        return path
    }
}

extension CGRect {
    init(start: CGPoint, end: CGPoint) {
        self.init(x: min(start.x, end.x), y: min(start.y, end.y),
                  width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

/// Whiteboard shapes and text. Sized to the shapes, not the screen, like the stroke layers.
struct ShapeLayer: View {
    let shapes: [InkModel.Shape]

    var body: some View {
        if !shapes.isEmpty {
            let area = shapes.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
                .insetBy(dx: -ShapeGeometry.margin, dy: -ShapeGeometry.margin)
            Canvas { context, _ in
                context.translateBy(x: -area.origin.x, y: -area.origin.y)
                for shape in shapes {
                    if shape.kind == .text {
                        context.draw(Text(shape.text).font(BoardText.font).foregroundColor(shape.color.color),
                                     at: shape.start, anchor: .topLeading)
                    } else {
                        context.stroke(ShapeGeometry.path(for: shape), with: .color(shape.color.color),
                                       style: StrokeStyle(lineWidth: ShapeGeometry.lineWidth, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(width: area.width, height: area.height)
            .position(x: area.midX, y: area.midY)
            .allowsHitTesting(false)
        }
    }
}

/// Excalidraw-like toolbar along the top of the whiteboard: tools, then colors.
struct BoardToolbar: View {
    private enum Metrics {
        static let cell: CGFloat = 40
        static let spacing: CGFloat = 4
        static let padding: CGFloat = 8
        static let divider: CGFloat = 1
    }

    /// Excalidraw's selected-tool tint.
    private static let accent = Color(red: 0x69 / 255, green: 0x65 / 255, blue: 0xdb / 255)

    static var size: CGSize {
        let cells = CGFloat(BoardTool.allCases.count + BoardColor.allCases.count)
        let width = Metrics.padding * 2 + cells * Metrics.cell + cells * Metrics.spacing + Metrics.divider
        return CGSize(width: width, height: Metrics.cell + Metrics.padding * 2)
    }

    @ObservedObject var brushes: BrushState

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            ForEach(BoardTool.allCases) { tool in
                let isSelected = brushes.boardTool == tool
                Button { brushes.boardTool = tool } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isSelected ? Self.accent : Color(white: 0.2))
                        .frame(width: Metrics.cell, height: Metrics.cell)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Self.accent.opacity(0.16) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(tool.title)  \(tool.key.uppercased())")
            }

            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(width: Metrics.divider, height: Metrics.cell - 12)

            ForEach(BoardColor.allCases) { color in
                Button { brushes.boardColor = color } label: {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.color)
                        .frame(width: 22, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Self.accent, lineWidth: brushes.boardColor == color ? 2 : 0)
                                .padding(-5)
                        )
                        .frame(width: Metrics.cell, height: Metrics.cell)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Metrics.padding)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06))
        )
        .environment(\.colorScheme, .light)
    }
}
