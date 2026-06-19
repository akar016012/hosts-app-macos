import AppKit
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

    // Six-digit RGB hex (no leading #), used to persist a custom accent color.
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }

    // Nudge brightness (HSB) while preserving hue/saturation — used to derive the
    // lighter second accent stop for a custom theme's gradient.
    func brightnessAdjusted(_ delta: CGFloat) -> Color {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(s),
                     brightness: Double(min(max(b + delta, 0), 1)), opacity: Double(a))
    }
}

// MARK: - Custom theme config

// A user-defined theme: a single accent color over a light or dark base. The
// structural colors are borrowed from a built-in template (Midnight / Daylight)
// so contrast stays sane, while everything accent-derived comes from the picked
// color. Persisted in UserDefaults.
enum CustomTheme {
    private static let accentKey = "hosts.custom.accent"
    private static let lightKey = "hosts.custom.light"

    static var accentHex: String {
        get { UserDefaults.standard.string(forKey: accentKey) ?? "5b8cff" }
        set { UserDefaults.standard.set(newValue, forKey: accentKey) }
    }
    static var isLight: Bool {
        get { UserDefaults.standard.bool(forKey: lightKey) }
        set { UserDefaults.standard.set(newValue, forKey: lightKey) }
    }
    static var accent: Color { Color(hex: accentHex) }
}

// MARK: - Theming

// All structural color comes from these tokens; switchable per AppTheme.
struct Palette {
    let bg, glow, headerBg, surface, surface2, border, row, rowOff, rowBorder: Color
    let text, text2, textDim, textMut: Color
    let accent, accent2, accentSoft, accentBorder, toggleOff: Color
    let isLight: Bool

    // Derived once at construction (each palette is built once per theme and
    // cached) so the WCAG contrast loops below don't re-run on every color read.
    let green, red, amber, onAccent: Color

    init(bg: Color, glow: Color, headerBg: Color, surface: Color, surface2: Color,
         border: Color, row: Color, rowOff: Color, rowBorder: Color,
         text: Color, text2: Color, textDim: Color, textMut: Color,
         accent: Color, accent2: Color, accentSoft: Color, accentBorder: Color,
         toggleOff: Color, isLight: Bool) {
        self.bg = bg; self.glow = glow; self.headerBg = headerBg
        self.surface = surface; self.surface2 = surface2; self.border = border
        self.row = row; self.rowOff = rowOff; self.rowBorder = rowBorder
        self.text = text; self.text2 = text2; self.textDim = textDim; self.textMut = textMut
        self.accent = accent; self.accent2 = accent2; self.accentSoft = accentSoft
        self.accentBorder = accentBorder; self.toggleOff = toggleOff; self.isLight = isLight

        // Semantic colors keep their meaning (green = good, red = bad, amber =
        // partial) but are brightness-tuned to a readable contrast vs this bg.
        self.green = contrastSafe(Color(hex: isLight ? "0f9d6b" : "34d399"), on: bg)
        self.red   = contrastSafe(Color(hex: isLight ? "dc2626" : "f87171"), on: bg)
        self.amber = contrastSafe(Color(hex: isLight ? "d97706" : "f5b54a"), on: bg)

        // Black or white — whichever reads better across the accent gradient
        // (accent2 → accent), maximizing the worst-case contrast over both stops.
        let dark = Color(hex: "0b0f14")
        func worst(_ fg: Color) -> Double {
            let l = fg.relativeLuminance
            return min(contrastRatio(l, accent.relativeLuminance),
                       contrastRatio(l, accent2.relativeLuminance))
        }
        self.onAccent = worst(.white) >= worst(dark) ? .white : dark
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case midnight, graphite, carbon, plum, daylight,
         aurora, crimson, ocean, ember, forest, latte, custom

    // The built-in presets shown in the swatch grid; `custom` is offered
    // separately through its own editor row.
    static var presets: [AppTheme] { allCases.filter { $0 != .custom } }

    var id: String { rawValue }
    var label: String {
        switch self {
        case .midnight: return "Midnight"; case .graphite: return "Graphite"
        case .carbon: return "Carbon"; case .plum: return "Plum"; case .daylight: return "Daylight"
        case .aurora: return "Aurora"; case .crimson: return "Crimson"; case .ocean: return "Ocean"
        case .ember: return "Ember"; case .forest: return "Forest"; case .latte: return "Latte"
        case .custom: return "Custom"
        }
    }
    var dot: Color {
        switch self {
        case .midnight: return Color(hex: "5b8cff"); case .graphite: return Color(hex: "8ea6c9")
        case .carbon: return Color(hex: "34d399"); case .plum: return Color(hex: "a78bfa")
        case .daylight: return Color(hex: "3a6df0"); case .aurora: return Color(hex: "2dd4bf")
        case .crimson: return Color(hex: "f43f5e"); case .ocean: return Color(hex: "38bdf8")
        case .ember: return Color(hex: "fb923c"); case .forest: return Color(hex: "4ade80")
        case .latte: return Color(hex: "b45309")
        case .custom: return CustomTheme.accent
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
                           accent: a, accent2: Color(hex: "2f5fe0"), accentSoft: a.opacity(0.10), accentBorder: a.opacity(0.26),
                           toggleOff: Color(hex: "c7cedb"), isLight: true)
        case .aurora:
            let a = Color(hex: "2dd4bf")
            return Palette(bg: Color(hex: "07111a"), glow: a.opacity(0.12), headerBg: Color(hex: "07111a").opacity(0.72),
                           surface: Color(hex: "0d1e25"), surface2: Color(hex: "091519"), border: Color(hex: "172e35"),
                           row: Color(hex: "0c1b22"), rowOff: Color(hex: "08121a"), rowBorder: Color(hex: "14272f"),
                           text: Color(hex: "dff4f1"), text2: Color(hex: "8db8b3"), textDim: Color(hex: "567870"), textMut: Color(hex: "3a5550"),
                           accent: a, accent2: Color(hex: "5ee8d6"), accentSoft: a.opacity(0.12), accentBorder: a.opacity(0.32),
                           toggleOff: Color(hex: "1c3a3a"), isLight: false)
        case .crimson:
            let a = Color(hex: "f43f5e")
            return Palette(bg: Color(hex: "0f0509"), glow: a.opacity(0.12), headerBg: Color(hex: "0f0509").opacity(0.72),
                           surface: Color(hex: "1e0c12"), surface2: Color(hex: "17080e"), border: Color(hex: "30131c"),
                           row: Color(hex: "1b0b10"), rowOff: Color(hex: "130709"), rowBorder: Color(hex: "2a1018"),
                           text: Color(hex: "f5dde3"), text2: Color(hex: "c4939d"), textDim: Color(hex: "89626c"), textMut: Color(hex: "573d44"),
                           accent: a, accent2: Color(hex: "fb7185"), accentSoft: a.opacity(0.12), accentBorder: a.opacity(0.34),
                           toggleOff: Color(hex: "3d1a22"), isLight: false)
        case .ocean:
            let a = Color(hex: "38bdf8")
            return Palette(bg: Color(hex: "040c1a"), glow: a.opacity(0.12), headerBg: Color(hex: "040c1a").opacity(0.72),
                           surface: Color(hex: "0a1628"), surface2: Color(hex: "071020"), border: Color(hex: "10243d"),
                           row: Color(hex: "091424"), rowOff: Color(hex: "060e1b"), rowBorder: Color(hex: "0e2037"),
                           text: Color(hex: "daf1fd"), text2: Color(hex: "8bbedd"), textDim: Color(hex: "4e7ea0"), textMut: Color(hex: "325470"),
                           accent: a, accent2: Color(hex: "7dd3fc"), accentSoft: a.opacity(0.12), accentBorder: a.opacity(0.32),
                           toggleOff: Color(hex: "163352"), isLight: false)
        case .ember:
            let a = Color(hex: "fb923c")
            return Palette(bg: Color(hex: "110905"), glow: a.opacity(0.12), headerBg: Color(hex: "110905").opacity(0.72),
                           surface: Color(hex: "1e1008"), surface2: Color(hex: "180d06"), border: Color(hex: "321a0c"),
                           row: Color(hex: "1c0e07"), rowOff: Color(hex: "150a05"), rowBorder: Color(hex: "2b1709"),
                           text: Color(hex: "faebd7"), text2: Color(hex: "c49a72"), textDim: Color(hex: "8b6742"), textMut: Color(hex: "55402a"),
                           accent: a, accent2: Color(hex: "fdba74"), accentSoft: a.opacity(0.12), accentBorder: a.opacity(0.32),
                           toggleOff: Color(hex: "3d2010"), isLight: false)
        case .forest:
            let a = Color(hex: "4ade80")
            return Palette(bg: Color(hex: "040a04"), glow: a.opacity(0.10), headerBg: Color(hex: "040a04").opacity(0.74),
                           surface: Color(hex: "0a150a"), surface2: Color(hex: "081008"), border: Color(hex: "142414"),
                           row: Color(hex: "091209"), rowOff: Color(hex: "060d06"), rowBorder: Color(hex: "111f11"),
                           text: Color(hex: "d4f4d4"), text2: Color(hex: "86b886"), textDim: Color(hex: "4a724a"), textMut: Color(hex: "344f34"),
                           accent: a, accent2: Color(hex: "86efac"), accentSoft: a.opacity(0.12), accentBorder: a.opacity(0.30),
                           toggleOff: Color(hex: "1a361a"), isLight: false)
        case .latte:
            let a = Color(hex: "b45309")
            return Palette(bg: Color(hex: "fdf6eb"), glow: a.opacity(0.08), headerBg: Color(hex: "fdf6eb").opacity(0.72),
                           surface: Color(hex: "fff8f0"), surface2: Color(hex: "f7eddc"), border: Color(hex: "e8d5b0"),
                           row: Color(hex: "fffaf4"), rowOff: Color(hex: "f5ede0"), rowBorder: Color(hex: "ead8b8"),
                           text: Color(hex: "1c1208"), text2: Color(hex: "5c4425"), textDim: Color(hex: "8c6e48"), textMut: Color(hex: "b8956a"),
                           accent: a, accent2: Color(hex: "a84e08"), accentSoft: a.opacity(0.10), accentBorder: a.opacity(0.28),
                           toggleOff: Color(hex: "d4b896"), isLight: true)
        case .custom:
            // Borrow structural tokens from a built-in base of the chosen mode,
            // then overlay everything accent-derived from the user's color so the
            // app stays readable regardless of which accent they pick.
            let a = CustomTheme.accent
            let light = CustomTheme.isLight
            let base = (light ? AppTheme.daylight : AppTheme.midnight).palette
            let a2 = a.brightnessAdjusted(light ? -0.08 : 0.14)
            return Palette(bg: base.bg, glow: a.opacity(light ? 0.10 : 0.16), headerBg: base.headerBg,
                           surface: base.surface, surface2: base.surface2, border: base.border,
                           row: base.row, rowOff: base.rowOff, rowBorder: base.rowBorder,
                           text: base.text, text2: base.text2, textDim: base.textDim, textMut: base.textMut,
                           accent: a, accent2: a2, accentSoft: a.opacity(light ? 0.10 : 0.14),
                           accentBorder: a.opacity(light ? 0.28 : 0.34),
                           toggleOff: base.toggleOff, isLight: light)
        }
    }
}

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    @Published var theme: AppTheme {
        didSet {
            cachedPalette = theme.palette
            revision &+= 1
            UserDefaults.standard.set(theme.rawValue, forKey: "hosts.theme")
        }
    }
    // Bumped on every change (including in-place custom edits, where `theme`
    // stays `.custom`). Views key their identity off this so a re-themed subtree
    // is torn down and rebuilt with the fresh palette.
    @Published private(set) var revision = 0

    // The palette (and its Color(hex:) parsing + WCAG math) is rebuilt only when
    // the theme actually changes, not on every token read.
    private(set) var cachedPalette: Palette
    private init() {
        let raw = UserDefaults.standard.string(forKey: "hosts.theme") ?? ""
        let initial = AppTheme(rawValue: raw) ?? .midnight
        theme = initial
        cachedPalette = initial.palette
    }
    var palette: Palette { cachedPalette }

    // Persist a new custom accent/mode and switch to (or refresh) the custom
    // theme. Rebuilds the cached palette explicitly because re-selecting `.custom`
    // while it's already active wouldn't trip `theme`'s didSet.
    func applyCustom(accentHex: String, isLight: Bool) {
        CustomTheme.accentHex = accentHex
        CustomTheme.isLight = isLight
        if theme == .custom {
            cachedPalette = AppTheme.custom.palette
            revision &+= 1
            objectWillChange.send()
        } else {
            theme = .custom   // didSet rebuilds palette, bumps revision, persists
        }
    }
}

// Static namespace so views and ButtonStyles can read tokens without plumbing
// the environment. ContentView refreshes the themed subtree and syncs AppKit
// appearance when this palette changes.
enum Theme {
    static var p: Palette { ThemeStore.shared.cachedPalette }
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

    // Precomputed once per palette (see Palette.init).
    static var onAccent: Color { p.onAccent }
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

    // Semantic colors, brightness-tuned per theme (precomputed in Palette.init).
    static var green: Color { p.green }
    static var red: Color { p.red }
    static var amber: Color { p.amber }

    // Black or white, whichever reads better on the given background. Used for
    // text drawn over solid semantic fills (e.g. toasts) so it stays legible in
    // every theme.
    static func readable(on bg: Color) -> Color {
        let l = bg.relativeLuminance
        let dark = Color(hex: "0b0f14")
        return contrastRatio(l, Color.white.relativeLuminance) >= contrastRatio(l, dark.relativeLuminance)
            ? .white : dark
    }
}

// MARK: - Contrast (WCAG)

extension Color {
    fileprivate var srgb: NSColor { NSColor(self).usingColorSpace(.sRGB) ?? .black }

    // WCAG relative luminance.
    var relativeLuminance: Double {
        let c = srgb
        func lin(_ v: CGFloat) -> Double {
            let x = Double(v)
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }
}

private func contrastRatio(_ a: Double, _ b: Double) -> Double {
    (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

// Nudge a color's brightness (preserving hue/saturation, so its meaning stays
// intact) until it clears the target contrast ratio against `bg`. On dark
// backgrounds it lightens, on light backgrounds it darkens.
func contrastSafe(_ base: Color, on bg: Color, target: Double = 4.5) -> Color {
    let bgLum = bg.relativeLuminance
    let c = base.srgb
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    let lighten = bgLum < 0.5
    var result = base
    var iterations = 0
    while contrastRatio(result.relativeLuminance, bgLum) < target && iterations < 30 {
        b += lighten ? 0.03 : -0.03
        if b <= 0 || b >= 1 { break }
        result = Color(hue: Double(h), saturation: Double(s), brightness: Double(b))
        iterations += 1
    }
    return result
}

// MARK: - IPKind colors (UI layer — Core stays SwiftUI-free)

extension IPKind {
    // Saturated base color used on dark backgrounds and for strokes/fills.
    var base: Color {
        switch self {
        case .loopback:   return Color(hex: "34d399")
        case .ipv6:       return Color(hex: "60a5fa")
        case .broadcast:  return Color(hex: "f87171")
        case .privateNet: return Color(hex: "a78bfa")
        case .block:      return Color(hex: "f87171")
        case .custom:     return Color(hex: "94a3b8")
        }
    }
    // Slightly darker variant with enough contrast for light-mode backgrounds.
    var lightText: Color {
        switch self {
        case .loopback:   return Color(hex: "059669")
        case .ipv6:       return Color(hex: "2563eb")
        case .broadcast:  return Color(hex: "dc2626")
        case .privateNet: return Color(hex: "7c3aed")
        case .block:      return Color(hex: "dc2626")
        case .custom:     return Color(hex: "475569")
        }
    }
}

// Shared gradients. Keep accentFill computed so it always reads the active palette.
extension LinearGradient {
    static let toggleAmber = LinearGradient(colors: [Color(hex: "f5b54a"), Color(hex: "e0972a")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing)
    static var accentFill: LinearGradient {
        LinearGradient(colors: [Theme.accent2, Theme.accent],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }
}
