import SwiftUI

// MARK: - Colors

extension Color {
    init(hex: String) {
        let s = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
        var rgb: UInt64 = 0
        s.scanHexInt64(&rgb)
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Theming

// All structural color comes from these tokens; switchable per AppTheme.
struct Palette {
    let bg, glow, headerBg, surface, surface2, border, row, rowOff, rowBorder: Color
    let text, text2, textDim, textMut: Color
    let accent, accent2, accentSoft, accentBorder, toggleOff: Color
    let isLight: Bool
}

enum AppTheme: String, CaseIterable, Identifiable {
    case midnight, graphite, carbon, plum, daylight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .midnight: return "Midnight"; case .graphite: return "Graphite"
        case .carbon: return "Carbon"; case .plum: return "Plum"; case .daylight: return "Daylight"
        }
    }
    var dot: Color {
        switch self {
        case .midnight: return Color(hex: "5b8cff"); case .graphite: return Color(hex: "8ea6c9")
        case .carbon: return Color(hex: "34d399"); case .plum: return Color(hex: "a78bfa")
        case .daylight: return Color(hex: "3a6df0")
        }
    }

    var palette: Palette {
        switch self {
        case .midnight:
            let a = Color(hex: "5b8cff")
            return Palette(bg: Color(hex: "0a0e1a"), glow: a.opacity(0.16), headerBg: Color(hex: "0a0e1a").opacity(0.72),
                           surface: Color(hex: "131a2b"), surface2: Color(hex: "0e1422"), border: Color(hex: "1e2840"),
                           row: Color(hex: "111827"), rowOff: Color(hex: "0c1119"), rowBorder: Color(hex: "1b2336"),
                           text: Color(hex: "e7ecf5"), text2: Color(hex: "aab4c8"), textDim: Color(hex: "6b7689"), textMut: Color(hex: "495468"),
                           accent: a, accent2: Color(hex: "7aa2ff"), accentSoft: a.opacity(0.14), accentBorder: a.opacity(0.34),
                           toggleOff: Color(hex: "2a3346"), isLight: false)
        case .graphite:
            let a = Color(hex: "8ea6c9")
            return Palette(bg: Color(hex: "15181d"), glow: a.opacity(0.10), headerBg: Color(hex: "15181d").opacity(0.72),
                           surface: Color(hex: "1d2128"), surface2: Color(hex: "181c22"), border: Color(hex: "2a3039"),
                           row: Color(hex: "1b1f26"), rowOff: Color(hex: "16191f"), rowBorder: Color(hex: "272d36"),
                           text: Color(hex: "e9ebee"), text2: Color(hex: "b0b6c0"), textDim: Color(hex: "727885"), textMut: Color(hex: "525863"),
                           accent: a, accent2: Color(hex: "a8bcd9"), accentSoft: a.opacity(0.14), accentBorder: a.opacity(0.32),
                           toggleOff: Color(hex: "333a45"), isLight: false)
        case .carbon:
            let a = Color(hex: "34d399")
            return Palette(bg: Color(hex: "08090a"), glow: a.opacity(0.12), headerBg: Color(hex: "08090a").opacity(0.74),
                           surface: Color(hex: "101314"), surface2: Color(hex: "0c0e0f"), border: Color(hex: "1e2223"),
                           row: Color(hex: "0f1112"), rowOff: Color(hex: "0a0c0c"), rowBorder: Color(hex: "1a1f20"),
                           text: Color(hex: "e6eae8"), text2: Color(hex: "a4b0aa"), textDim: Color(hex: "69736d"), textMut: Color(hex: "49514c"),
                           accent: a, accent2: Color(hex: "5fe0ad"), accentSoft: a.opacity(0.13), accentBorder: a.opacity(0.32),
                           toggleOff: Color(hex: "283230"), isLight: false)
        case .plum:
            let a = Color(hex: "a78bfa")
            return Palette(bg: Color(hex: "120e1c"), glow: a.opacity(0.14), headerBg: Color(hex: "120e1c").opacity(0.72),
                           surface: Color(hex: "1b1428"), surface2: Color(hex: "150f20"), border: Color(hex: "2b2239"),
                           row: Color(hex: "181024"), rowOff: Color(hex: "120c1b"), rowBorder: Color(hex: "271d35"),
                           text: Color(hex: "ece7f5"), text2: Color(hex: "b6aacb"), textDim: Color(hex: "7a6e90"), textMut: Color(hex: "564b6a"),
                           accent: a, accent2: Color(hex: "bfa6ff"), accentSoft: a.opacity(0.14), accentBorder: a.opacity(0.34),
                           toggleOff: Color(hex: "2f2742"), isLight: false)
        case .daylight:
            let a = Color(hex: "3a6df0")
            return Palette(bg: Color(hex: "f4f6fb"), glow: a.opacity(0.10), headerBg: Color(hex: "f4f6fb").opacity(0.72),
                           surface: Color(hex: "ffffff"), surface2: Color(hex: "eef1f7"), border: Color(hex: "d9dfea"),
                           row: Color(hex: "ffffff"), rowOff: Color(hex: "eef1f7"), rowBorder: Color(hex: "e3e8f1"),
                           text: Color(hex: "1a2233"), text2: Color(hex: "4a5568"), textDim: Color(hex: "7a8699"), textMut: Color(hex: "9aa4b4"),
                           accent: a, accent2: Color(hex: "5b8cff"), accentSoft: a.opacity(0.10), accentBorder: a.opacity(0.26),
                           toggleOff: Color(hex: "c7cedb"), isLight: true)
        }
    }
}

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "hosts.theme") }
    }
    private init() {
        let raw = UserDefaults.standard.string(forKey: "hosts.theme") ?? ""
        theme = AppTheme(rawValue: raw) ?? .midnight
    }
    var palette: Palette { theme.palette }
}

// Static namespace so views and ButtonStyles can read tokens without plumbing
// the environment. ContentView observes ThemeStore, so a theme switch rebuilds
// the tree and every Theme.* below re-reads the active palette.
enum Theme {
    static var p: Palette { ThemeStore.shared.palette }
    static var isLight: Bool { p.isLight }

    static var bg: Color { p.bg }
    static var glow: Color { p.glow }
    static var headerBg: Color { p.headerBg }
    static var surface: Color { p.surface }
    static var surface2: Color { p.surface2 }
    static var border: Color { p.border }
    static var row: Color { p.row }
    static var rowOff: Color { p.rowOff }
    static var rowBorder: Color { p.rowBorder }
    static var text: Color { p.text }
    static var text2: Color { p.text2 }
    static var textDim: Color { p.textDim }
    static var textMut: Color { p.textMut }
    static var accent: Color { p.accent }
    static var accent2: Color { p.accent2 }
    static var accentSoft: Color { p.accentSoft }
    static var accentBorder: Color { p.accentBorder }
    static var toggleOff: Color { p.toggleOff }

    // Back-compat aliases used throughout the views.
    static var bg2: Color { p.surface2 }
    static var panel: Color { p.surface }
    static var panel2: Color { p.surface2 }
    static var muted: Color { p.text2 }
    static var faint: Color { p.textDim }
    static var blue: Color { p.accent }

    // Semantic colors (data-driven, re-tuned for light mode).
    static var green: Color { isLight ? Color(hex: "0f9d6b") : Color(hex: "34d399") }
    static var red: Color { isLight ? Color(hex: "dc2626") : Color(hex: "f87171") }
    static var amber: Color { isLight ? Color(hex: "d97706") : Color(hex: "f5b54a") }
}

// Toggle gradient (enabled = green, partial group = amber).
extension LinearGradient {
    static let toggleOn = LinearGradient(colors: [Color(hex: "3ddc97"), Color(hex: "22b07a")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let toggleAmber = LinearGradient(colors: [Color(hex: "f5b54a"), Color(hex: "e0972a")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static var accentFill: LinearGradient { LinearGradient(colors: [Theme.accent2, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing) }
}
