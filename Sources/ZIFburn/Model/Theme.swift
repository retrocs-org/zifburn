import AppKit
import SwiftUI

/// A colour theme. `palette == nil` means "use native macOS colours"
/// (System / Light / Dark); every other theme paints the window itself.
struct Theme: Identifiable, Equatable {
    enum Appearance: Equatable {
        case system, light, dark
    }

    struct Palette: Equatable {
        var background: Color     // main content area
        var sidebar: Color        // sidebar, inspector, toolbar, status bar
        var surface: Color        // raised elements / preview blocks
        var text: Color
        var secondaryText: Color
        var accent: Color
        var success: Color
        var warning: Color
        var error: Color
    }

    let id: String
    let name: String
    let appearance: Appearance
    let palette: Palette?

    var isCustom: Bool { palette != nil }

    // Semantic colours with native fallbacks.
    var accent: Color { palette?.accent ?? .accentColor }
    var success: Color { palette?.success ?? .green }
    var warning: Color { palette?.warning ?? .orange }
    var error: Color { palette?.error ?? .red }
    var text: Color { palette?.text ?? .primary }
    var secondaryText: Color { palette?.secondaryText ?? .secondary }
    var textStyle: AnyShapeStyle { palette.map { AnyShapeStyle($0.text) } ?? AnyShapeStyle(HierarchicalShapeStyle.primary) }

    var nsAppearance: NSAppearance? {
        switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Colours used to draw the theme's preview card.
    var previewPalette: Palette {
        palette ?? (appearance == .light ? Self.lightPreview : Self.darkPreview)
    }
}

// MARK: - Built-in themes

extension Theme {
    static let system = Theme(id: "system", name: "System", appearance: .system, palette: nil)
    static let light = Theme(id: "light", name: "Light", appearance: .light, palette: nil)
    static let dark = Theme(id: "dark", name: "Dark", appearance: .dark, palette: nil)

    static let catppuccinLatte = Theme(
        id: "catppuccin-latte", name: "Catppuccin Latte", appearance: .light,
        palette: Palette(
            background: Color(hex: 0xEFF1F5), sidebar: Color(hex: 0xE6E9EF), surface: Color(hex: 0xCCD0DA),
            text: Color(hex: 0x4C4F69), secondaryText: Color(hex: 0x6C6F85), accent: Color(hex: 0x1E66F5),
            success: Color(hex: 0x40A02B), warning: Color(hex: 0xDF8E1D), error: Color(hex: 0xD20F39)))

    static let catppuccinFrappe = Theme(
        id: "catppuccin-frappe", name: "Catppuccin Frappé", appearance: .dark,
        palette: Palette(
            background: Color(hex: 0x303446), sidebar: Color(hex: 0x292C3C), surface: Color(hex: 0x414559),
            text: Color(hex: 0xC6D0F5), secondaryText: Color(hex: 0xA5ADCE), accent: Color(hex: 0x8CAAEE),
            success: Color(hex: 0xA6D189), warning: Color(hex: 0xE5C890), error: Color(hex: 0xE78284)))

    static let catppuccinMacchiato = Theme(
        id: "catppuccin-macchiato", name: "Catppuccin Macchiato", appearance: .dark,
        palette: Palette(
            background: Color(hex: 0x24273A), sidebar: Color(hex: 0x1E2030), surface: Color(hex: 0x363A4F),
            text: Color(hex: 0xCAD3F5), secondaryText: Color(hex: 0xA5ADCB), accent: Color(hex: 0x8AADF4),
            success: Color(hex: 0xA6DA95), warning: Color(hex: 0xEED49F), error: Color(hex: 0xED8796)))

    static let catppuccinMocha = Theme(
        id: "catppuccin-mocha", name: "Catppuccin Mocha", appearance: .dark,
        palette: Palette(
            background: Color(hex: 0x1E1E2E), sidebar: Color(hex: 0x181825), surface: Color(hex: 0x313244),
            text: Color(hex: 0xCDD6F4), secondaryText: Color(hex: 0xA6ADC8), accent: Color(hex: 0x89B4FA),
            success: Color(hex: 0xA6E3A1), warning: Color(hex: 0xF9E2AF), error: Color(hex: 0xF38BA8)))

    static let nord = Theme(
        id: "nord", name: "Nord", appearance: .dark,
        palette: Palette(
            background: Color(hex: 0x2E3440), sidebar: Color(hex: 0x3B4252), surface: Color(hex: 0x434C5E),
            text: Color(hex: 0xECEFF4), secondaryText: Color(hex: 0xD8DEE9), accent: Color(hex: 0x88C0D0),
            success: Color(hex: 0xA3BE8C), warning: Color(hex: 0xEBCB8B), error: Color(hex: 0xBF616A)))

    static let dracula = Theme(
        id: "dracula", name: "Dracula", appearance: .dark,
        palette: Palette(
            background: Color(hex: 0x282A36), sidebar: Color(hex: 0x21222C), surface: Color(hex: 0x44475A),
            text: Color(hex: 0xF8F8F2), secondaryText: Color(hex: 0x9CA3C7), accent: Color(hex: 0xBD93F9),
            success: Color(hex: 0x50FA7B), warning: Color(hex: 0xF1FA8C), error: Color(hex: 0xFF5555)))

    static let solarizedLight = Theme(
        id: "solarized-light", name: "Solarized Light", appearance: .light,
        palette: Palette(
            background: Color(hex: 0xFDF6E3), sidebar: Color(hex: 0xEEE8D5), surface: Color(hex: 0xE4DDC8),
            text: Color(hex: 0x586E75), secondaryText: Color(hex: 0x839496), accent: Color(hex: 0x268BD2),
            success: Color(hex: 0x859900), warning: Color(hex: 0xB58900), error: Color(hex: 0xDC322F)))

    static let solarizedDark = Theme(
        id: "solarized-dark", name: "Solarized Dark", appearance: .dark,
        palette: Palette(
            background: Color(hex: 0x002B36), sidebar: Color(hex: 0x073642), surface: Color(hex: 0x0E4351),
            text: Color(hex: 0x93A1A1), secondaryText: Color(hex: 0x839496), accent: Color(hex: 0x2AA198),
            success: Color(hex: 0x859900), warning: Color(hex: 0xB58900), error: Color(hex: 0xDC322F)))

    /// Green-phosphor CRT, for that 1985 EPROM-programmer feeling.
    static let phosphor = Theme(
        id: "phosphor", name: "Phosphor", appearance: .dark,
        palette: Palette(
            background: Color(hex: 0x0A120B), sidebar: Color(hex: 0x07100A), surface: Color(hex: 0x14261A),
            text: Color(hex: 0x4AF07A), secondaryText: Color(hex: 0x2FA552), accent: Color(hex: 0x6BFF95),
            success: Color(hex: 0x6BFF95), warning: Color(hex: 0xD7FF5A), error: Color(hex: 0xFF6B5A)))

    /// Amber monochrome monitor.
    static let amber = Theme(
        id: "amber", name: "Amber", appearance: .dark,
        palette: Palette(
            background: Color(hex: 0x140E04), sidebar: Color(hex: 0x0E0902), surface: Color(hex: 0x2A1D08),
            text: Color(hex: 0xFFB43A), secondaryText: Color(hex: 0xC08427), accent: Color(hex: 0xFFC65C),
            success: Color(hex: 0xE8D35A), warning: Color(hex: 0xFFD27A), error: Color(hex: 0xFF6A3D)))

    static let all: [Theme] = [
        .system, .light, .dark,
        .catppuccinLatte, .catppuccinFrappe, .catppuccinMacchiato, .catppuccinMocha,
        .nord, .dracula, .solarizedLight, .solarizedDark,
        .phosphor, .amber,
    ]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .system
    }

    fileprivate static let lightPreview = Palette(
        background: Color(hex: 0xFFFFFF), sidebar: Color(hex: 0xEBEBEE), surface: Color(hex: 0xF2F2F5),
        text: Color(hex: 0x1D1D1F), secondaryText: Color(hex: 0x6E6E73), accent: Color(hex: 0x007AFF),
        success: .green, warning: .orange, error: .red)

    fileprivate static let darkPreview = Palette(
        background: Color(hex: 0x1E1E1E), sidebar: Color(hex: 0x2A2A2C), surface: Color(hex: 0x323234),
        text: Color(hex: 0xE5E5E7), secondaryText: Color(hex: 0x98989D), accent: Color(hex: 0x0A84FF),
        success: .green, warning: .orange, error: .red)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Environment & root modifier

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.system
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Applied once at the root of every window. Every modifier is applied
/// unconditionally (with neutral values for native themes) so switching
/// themes never changes view identity or resets window state.
struct ThemeRoot: ViewModifier {
    @AppStorage(DefaultsKey.theme) private var themeID = Theme.system.id

    func body(content: Content) -> some View {
        let theme = Theme.named(themeID)
        content
            .environment(\.theme, theme)
            .tint(theme.accent)
            .foregroundStyle(theme.textStyle)
            .background(theme.palette?.background ?? Color.clear)
            .onChange(of: themeID, initial: true) { _, newID in
                NSApp.appearance = Theme.named(newID).nsAppearance
            }
    }
}

extension View {
    func themedRoot() -> some View { modifier(ThemeRoot()) }

    /// Hides a List/Form's own background for custom themes and paints `color` instead.
    func themedBackground(_ theme: Theme, _ color: Color?) -> some View {
        self
            .scrollContentBackground(theme.isCustom ? .hidden : .automatic)
            .background(color ?? Color.clear)
    }
}
