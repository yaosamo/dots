import SwiftUI

/// How a screenshot is framed: what's behind it, how far it sits from the edges, its corners,
/// shadow, shape, a title bar and an effect around its edge. Remembered between shots.
struct FrameStyle: Codable, Equatable {
    var background = FrameBackground.dusk
    /// The color picked with "Custom", kept while another background is chosen.
    var customColor = RGBA(red: 0.98, green: 0.36, blue: 0.55)
    /// Canvas points around the shot (see `FramedShot.canvasScale`).
    var padding: CGFloat = 64
    var cornerRadius: CGFloat = 12
    /// 0…1.
    var shadow: CGFloat = 0.5
    var aspect = FrameAspect.auto
    var chrome = WindowChrome.none
    /// What Safari's address field shows.
    var address = ""
    var edge = EdgeEffect.none

    private static let key = "screenshot.style"

    static var saved: FrameStyle {
        guard let data = UserDefaults.standard.data(forKey: key),
              let style = try? JSONDecoder().decode(FrameStyle.self, from: data) else { return FrameStyle() }
        return style
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

struct RGBA: Codable, Equatable {
    var red: Double, green: Double, blue: Double
    var alpha: Double = 1

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }

    init(_ color: Color) {
        self.init(NSColor(color))
    }

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent)
    }
}

enum FrameBackground: String, Codable, CaseIterable, Identifiable {
    case dusk, sunrise, ocean, mint, peach, lavender, night, graphite, blur, clear, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blur: "The shot, blurred"
        case .clear: "Transparent"
        case .custom: "Your color"
        default: rawValue.capitalized
        }
    }

    /// Top-left to bottom-right, for the gradient backgrounds.
    var colors: [Color]? {
        let hex: [UInt32]
        switch self {
        case .dusk: hex = [0x4E54C8, 0x8F94FB]
        case .sunrise: hex = [0xFF9A8B, 0xFF6A88, 0xFF99AC]
        case .ocean: hex = [0x00C6FB, 0x005BEA]
        case .mint: hex = [0xD4FC79, 0x96E6A1]
        case .peach: hex = [0xFFECD2, 0xFCB69F]
        case .lavender: hex = [0xE0C3FC, 0x8EC5FC]
        case .night: hex = [0x0F2027, 0x203A43, 0x2C5364]
        case .graphite: hex = [0x5A5A5E, 0x1C1C1E]
        case .blur, .clear, .custom: return nil
        }
        return hex.map { Color(hex: $0) }
    }
}

enum FrameAspect: String, Codable, CaseIterable, Identifiable {
    case auto, wide, classic, square, portrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .wide: "16:9"
        case .classic: "4:3"
        case .square: "1:1"
        case .portrait: "4:5"
        }
    }

    /// Width over height; nil hugs the shot.
    var ratio: CGFloat? {
        switch self {
        case .auto: nil
        case .wide: 16 / 9
        case .classic: 4 / 3
        case .square: 1
        case .portrait: 4 / 5
        }
    }
}

/// A macOS title bar with traffic lights over the shot, for regions that don't have their own, or
/// Safari's toolbar with its address field.
enum WindowChrome: String, Codable, CaseIterable, Identifiable {
    case none, light, dark, safari

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// In canvas points.
    var height: CGFloat {
        switch self {
        case .none: 0
        case .light, .dark: 28
        case .safari: 52
        }
    }
}

/// The pen's and the camera's effects, around the shot's edge.
enum EdgeEffect: String, Codable, CaseIterable, Identifiable {
    case none, electric, fire, rainbow, cloud

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var brush: Brush? {
        switch self {
        case .electric: .electric
        case .fire: .fire
        case .rainbow: .rainbow
        case .none, .cloud: nil
        }
    }

    var isPro: Bool { self != .none }

    var swatch: AnyShapeStyle {
        switch self {
        case .none: AnyShapeStyle(Color.white.opacity(0.15))
        case .cloud: AnyShapeStyle(RadialGradient(colors: [.white, Color(white: 0.8)], center: .top, startRadius: 0, endRadius: 14))
        default: brush?.swatch ?? AnyShapeStyle(Color.clear)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
