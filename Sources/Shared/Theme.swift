import SwiftUI

public struct Theme {
    public init(dark: Bool) { self.dark = dark }
    public let dark: Bool
    public var bg: Color { dark ? Color(hex: "1C1D1F") : Color(hex: "F6F5F2") }
    public var card: Color { dark ? Color(hex: "26282C") : .white }
    public var text: Color { dark ? Color(hex: "EDEDED") : Color(hex: "1C1D1F") }
    public var sub: Color { dark ? Color(hex: "9AA0A6") : Color(hex: "7A7F85") }
    public var accent: Color { Color(hex: "3CA1DD") }
    public var cream: Color { Color(hex: "FFF6E5") }
    public var creamText: Color { Color(hex: "3A2E1E") }
    public var ink: Color { Color(hex: "1C1D1F") }
    public var hairline: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
}

public extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            a = Double((v >> 24) & 0xFF) / 255
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
        case 6:
            a = 1
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
        default:
            a = 1; r = 0.1; g = 0.1; b = 0.1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

public enum MayflyTheme {
    public static let ink = Color(hex: "1C1D1F")
    public static let ink2 = Color(hex: "2A2C30")
    public static let cream = Color(hex: "FFF6E5")
    public static let blue = Color(hex: "3CA1DD")
    public static let paper = Color(hex: "F6F2EA")
    public static let sub = Color(hex: "8A8F98")

    /// 按偏好 + 时段判断当前是否深色
    public static func isDark(mode: Pref.ThemeMode, start: String, end: String,
                              scheme: ColorScheme, now: Date = Date()) -> Bool {
        switch mode {
        case .system:
            return scheme == .dark
        case .light:
            return false
        case .dark:
            return true
        case .scheduled:
            let cal = Calendar.current
            let cur = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
            let s = parseMinutes(start)
            let e = parseMinutes(end)
            if s == e { return false }
            if s < e { return cur >= s && cur < e }
            return cur >= s || cur < e
        }
    }

    static func parseMinutes(_ t: String) -> Int {
        let parts = t.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return 0 }
        return h * 60 + m
    }

    public static func bg(dark: Bool) -> Color { dark ? ink : paper }
    public static func card(dark: Bool) -> Color { dark ? ink2 : .white }
    public static func primary(dark: Bool) -> Color { dark ? cream : ink }
    public static func secondary(dark: Bool) -> Color { dark ? Color(hex: "A9AEB6") : Color(hex: "6C7079") }
}

/// 主题观察对象：设置页改动后整树刷新
public final class ThemeModel: ObservableObject {
    @Published public var mode: Pref.ThemeMode
    @Published public var start: String
    @Published public var end: String
    @Published public var tick: Int = 0

    public init() {
        mode = Pref.shared.themeMode
        start = Pref.shared.darkStart
        end = Pref.shared.darkEnd
    }

    public var isDarkScheduleActive: Bool {
        _ = tick
        return MayflyTheme.isDark(mode: .scheduled, start: start, end: end, scheme: .light)
    }

    public func isDark(scheme: ColorScheme) -> Bool {
        _ = tick
        return MayflyTheme.isDark(mode: mode, start: start, end: end, scheme: scheme)
    }

    public func save() {
        Pref.shared.themeMode = mode
        Pref.shared.darkStart = start
        Pref.shared.darkEnd = end
        tick += 1
    }
}
