//
//  AppleDesignSystem.swift
//  Notch Lyrics
//
//  Visual foundation for the settings window: color, type, spacing, radii,
//  shadows and motion tokens in one place.
//
//  Rules:
//  - Only reference tokens declared here — no ad-hoc colors, sizes, radii,
//    shadows or durations.
//  - Weights are 400 / 600 / 700. There is no 500.
//  - Spacing 4 / 8 / 12 / 16 / 24 / 32 / 48; radii only 6 / 10 / 12 / pill.
//  - Exactly three shadows exist (window / popover / hero art). Controls and
//    cards are always flat and rely on a 1px stroke.
//  - Settings layout: one system material + a themed scrim under the whole
//    window; sidebar, page and group cards are translucent layers on top of it.
//    Keep controls opaque so they stay readable. 44pt rows.
//

import AppKit
import Defaults
import SwiftUI

/// Runtime string lookup: static copy comes from the catalog, dynamic values
/// (folder names, display names and the like) fall through untouched.
/// Shares one String Catalog with `Text(LocalizedStringKey(_:))`.
@inline(__always)
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

// MARK: - Dynamic two-tone color primitives

private func nlHex(_ hex: UInt32, alpha: Double = 1) -> NSColor {
    NSColor(
        srgbRed: Double((hex >> 16) & 0xFF) / 255.0,
        green: Double((hex >> 8) & 0xFF) / 255.0,
        blue: Double(hex & 0xFF) / 255.0,
        alpha: alpha
    )
}

/// A color that flips between a light and a dark value with the system appearance.
private func nlDynamic(
    _ light: UInt32,
    _ dark: UInt32,
    lightAlpha: Double = 1,
    darkAlpha: Double = 1
) -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? nlHex(dark, alpha: darkAlpha) : nlHex(light, alpha: lightAlpha)
    }
}

// MARK: - Notch colour theme

/// Palette of the notch slab and its metric readings. This is a setting, not a
/// system-appearance branch: the notch is always dark, so the choice is between
/// the saturated cool slab and the original neutral black one.
enum NLTheme: String, CaseIterable, Identifiable {
    /// Cool gradient slab, saturated per-metric accents, tinted card strokes.
    case vivid
    /// Original pure-black slab and muted accents.
    case standard

    static let storageKey = "notchColorTheme"
    static let defaultTheme: NLTheme = .vivid

    var id: String { rawValue }
    var isVivid: Bool { self == .vivid }

    var label: String {
        switch self {
        case .vivid: return L("Vivid")
        case .standard: return L("Standard")
        }
    }

    /// The palette is no longer a user-facing choice: the background picker
    /// replaced it, so every colour token stays on the cool, saturated set.
    static var current: NLTheme { .vivid }
}

// MARK: - Notch background

/// Three surfaces, one choice. They are qualities of the same panel rather than
/// effects stacked on top of each other: a deep black surface still uses a
/// system material, and a frosted one can still carry the artwork's colour.
///
/// These are product names. The user is choosing what the notch looks like,
/// not which blur or tint to switch on.
enum NLBackground: String, CaseIterable, Identifiable, Defaults.Serializable {
    case deep
    case frosted
    case clear

    static let defaultStyle: NLBackground = .frosted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deep: return L("深黑")
        case .frosted: return L("磨砂")
        case .clear: return L("透光")
        }
    }

    /// Black laid over the system material. Even Deep Black is not a flat
    /// opaque fill — the material stays faintly present underneath it.
    var scrim: Double {
        switch self {
        case .deep: return 0.92
        case .frosted: return 0.31
        case .clear: return 0.17
        }
    }

    /// Strength of the flat cool field over the black scrim. One hue, one
    /// direction, only the opacity changes: the three tiers stay distinct
    /// without a gradient or a glow.
    var glowStrength: Double {
        switch self {
        case .deep: return 0.45
        case .frosted: return 1.0
        case .clear: return 1.2
        }
    }
}

// MARK: - Settings window surface

/// A settings-window colour whose dark value is chosen per background style.
/// The window is pinned to darkAqua (see SettingsWindowController), so the
/// dark branch is what actually renders: the three backgrounds are qualities
/// of a dark surface, and the style is passed in by a view holding
/// `@Default(.notchBackground)` so switching the picker re-resolves
/// immediately. A dynamic provider that reads the default itself can be
/// cached and go stale, which is why the style is threaded through explicitly.
/// The light branch only serves Xcode previews and the `-appearance-light`
/// debug override.
private func nlSettingsDynamic(
    _ light: UInt32,
    lightAlpha: Double = 1,
    _ style: NLBackground,
    deep: (UInt32, Double),
    frosted: (UInt32, Double),
    clear: (UInt32, Double)
) -> NSColor {
    let dark: (UInt32, Double)
    switch style {
    case .deep: dark = deep
    case .frosted: dark = frosted
    case .clear: dark = clear
    }
    return nlDynamic(light, dark.0, lightAlpha: lightAlpha, darkAlpha: dark.1)
}

/// The four layers that make up the settings window. They are transparent in
/// varying degrees so the system material underneath is not painted over — a
/// card that stays opaque is the one thing that makes glass impossible to see.
enum NLSettingsSurface {
    /// Window / page background. Deep Black is near-opaque but still a thin
    /// scrim over the material, never a flat black fill.
    static func page(_ style: NLBackground) -> Color {
        Color(nsColor: pageNSColor(style))
    }

    /// The same scrim for AppKit. A transparent titlebar is filled with the
    /// window's own background colour, so leaving it clear would show a strip
    /// of desktop above a dark window.
    static func pageNSColor(_ style: NLBackground) -> NSColor {
        nlSettingsDynamic(
            0xF5F5F7, style,
            deep: (0x08080B, 0.95),
            frosted: (0x1F2025, 0.62),
            clear: (0x1F2128, 0.34)
        )
    }

    /// Group cards. In Deep Black they read as solid dark tiles; in Frosted and
    /// Translucent they become a faint white lift so the material shows through.
    static func card(_ style: NLBackground) -> Color {
        Color(nsColor: nlSettingsDynamic(
            0xFFFFFF, style,
            deep: (0x18181B, 0.94),
            frosted: (0xFFFFFF, 0.055),
            clear: (0xFFFFFF, 0.048)
        ))
    }

    /// Sidebar / titlebar material tint, laid over the same system material.
    static func sidebar(_ style: NLBackground) -> Color {
        Color(nsColor: nlSettingsDynamic(
            0xF9F9FB, lightAlpha: 0.82, style,
            deep: (0x101013, 0.86),
            frosted: (0x2E2E32, 0.55),
            clear: (0x2E2F36, 0.34)
        ))
    }

    /// The AppKit titlebar is outside the material, so it cannot use a
    /// translucent scrim — a partly clear window colour would show a bright
    /// strip of desktop above a dark window. Match each theme's sidebar tone
    /// with an opaque colour instead. The window is darkAqua, so the dark
    /// value is the one that renders.
    static func titlebarNSColor(_ style: NLBackground) -> NSColor {
        let dark: UInt32
        switch style {
        case .deep: dark = 0x101013
        case .frosted: dark = 0x333335
        case .clear: dark = 0x434347
        }
        return nlDynamic(0xF5F5F7, dark)
    }

    /// A group card stops being an opaque tile in the two glass themes, so it
    /// needs a hairline to stay legible against the page. Light Mode keeps the
    /// original borderless white card: this is fully transparent there.
    static func cardStroke(_ style: NLBackground) -> Color {
        Color(nsColor: nlSettingsDynamic(
            0xFFFFFF, lightAlpha: 0, style,
            deep: (0xFFFFFF, 0.07),
            frosted: (0xFFFFFF, 0.09),
            clear: (0xFFFFFF, 0.10)
        ))
    }
}

/// The settings window is one system material with a single scrim over it.
/// Every other surface (sidebar, group cards) is a translucent layer on top —
/// painting any of them opaque is what would hide the material.
///
/// The window is pinned to darkAqua by SettingsWindowController, so the dark
/// values below are what render in the app; the light branch is preview-only.
struct NLSettingsBackdrop: View {
    var style: NLBackground

    var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
            NLSettingsSurface.page(style)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Color tokens

enum NLColor {
    /// An accent the user picked in Appearance wins; otherwise fall back to the single interactive color.
    private static var customAccent: Color? {
        guard Defaults[.useCustomAccentColor],
            let data = Defaults[.customAccentColorData],
            let ns = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else { return nil }
        return Color(nsColor: ns)
    }

    /// --accent: the one interactive color in the app. #0066cc / #2997ff
    static var accent: Color { customAccent ?? Color(nsColor: nlDynamic(0x0066CC, 0x2997FF)) }
    /// --accent-hover: #0071e3 / #47a5ff (hover, focus ring)
    static var accentHover: Color { customAccent ?? Color(nsColor: nlDynamic(0x0071E3, 0x47A5FF)) }
    /// --accent-pressed: #0058b0 / #0071e3
    static var accentPressed: Color { customAccent ?? Color(nsColor: nlDynamic(0x0058B0, 0x0071E3)) }
    /// Focus ring color (2px #0071e3, 2px offset).
    static var accentRing: Color { Color(nsColor: nlDynamic(0x0071E3, 0x47A5FF)) }
    /// --text-on-accent
    static var textOnAccent: Color { .white }

    static var textPrimary: Color { Color(nsColor: nlDynamic(0x1D1D1F, 0xFFFFFF)) }
    static var textSecondary: Color { Color(nsColor: nlDynamic(0x6E6E73, 0xCCCCCC)) }
    static var textTertiary: Color { Color(nsColor: nlDynamic(0x7A7A7A, 0x7A7A7A)) }
    /// --text-destructive: #d70015 / #ff6961
    static var destructive: Color { Color(nsColor: nlDynamic(0xD70015, 0xFF6961)) }

    /// --bg-canvas / --bg-panel / --bg-elevated
    static var canvas: Color { Color(nsColor: nlDynamic(0xFFFFFF, 0x272729)) }
    static var panel: Color { Color(nsColor: nlDynamic(0xF5F5F7, 0x2A2A2C)) }
    static var elevated: Color { Color(nsColor: nlDynamic(0xFAFAFC, 0x333336)) }

    /// --search-bg: sidebar search field background. #ffffff / rgba(255,255,255,.08)
    static var searchBg: Color {
        Color(nsColor: nlDynamic(0xFFFFFF, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.08))
    }

    /// --border-hairline / --border-divider / --border-strong
    static var borderHairline: Color { Color(nsColor: nlDynamic(0xE0E0E0, 0x3A3A3C)) }
    static var borderDivider: Color { Color(nsColor: nlDynamic(0xF0F0F0, 0x2F2F31)) }
    static var borderStrong: Color { Color(nsColor: nlDynamic(0xD2D2D7, 0x48484A)) }

    // MARK: - Metric accents
    //
    // These name a metric, they do not grade it. The stats panel is forced to
    // darkAqua in the notch, so the dark value is what reads there; the light
    // value keeps the settings window and previews legible. Never substitute a
    // load colour (red for "GPU 100%") for one of these — Device Utilization
    // only means the chip had work in flight.
    //
    // The saturated dark values belong to the vivid theme; the standard theme
    // keeps the original muted set. Both are tokens — views never spell a hex.
    private static func metric(_ light: UInt32, _ muted: UInt32, _ vivid: UInt32) -> Color {
        Color(nsColor: nlDynamic(light, NLTheme.current.isVivid ? vivid : muted))
    }

    static var metricCPU: Color { metric(0x185FA5, 0x85B7EB, 0x4A9EFF) }
    static var metricGPU: Color { metric(0x534AB7, 0xAFA9EC, 0xB861FF) }
    static var metricMemory: Color { metric(0x993C1D, 0xF0997B, 0xFF477A) }
    static var metricDisk: Color { metric(0x854F0B, 0xFAC775, 0xFFC942) }
    static var metricNetwork: Color { metric(0x0F6E56, 0x5DCAA5, 0x3DDB66) }
    static var metricUpload: Color { metric(0x0F6E56, 0x5DCAA5, 0x29D6F0) }

    // MARK: - Notch slab
    //
    // A static opaque colour field, not a live blur. It reads as cool glass
    // without depending on a material, so it behaves identically on every
    // supported macOS version and ignores Reduce Transparency.
    static var slabGradient: [Color] {[
        Color(red: 0.085, green: 0.155, blue: 0.205),
        Color(red: 0.105, green: 0.120, blue: 0.160),
        Color(red: 0.145, green: 0.098, blue: 0.155),
    ]}

    /// --fill-neutral
    static var fillNeutral: Color { Color(nsColor: nlDynamic(0xD2D2D7, 0x48484A)) }

    /// --fill-selection: accent@14% / accent@18% (sidebar and list selection — a tint, not a solid).
    static var fillSelection: Color {
        Color(nsColor: nlDynamic(0x0066CC, 0x2997FF, lightAlpha: 0.14, darkAlpha: 0.18))
    }
    /// Table / list row hover (accent@6%).
    static var fillSelectionHover: Color { accent.opacity(0.06) }
    /// Sidebar selection while the window is inactive: fill-neutral@50%.
    static var sidebarSelectionInactive: Color {
        Color(nsColor: nlDynamic(0xD2D2D7, 0x48484A, lightAlpha: 0.5, darkAlpha: 0.5))
    }
    /// --fill-hover: black@5% / white@8%
    static var hoverFill: Color {
        Color(nsColor: nlDynamic(0x000000, 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.08))
    }
    /// Sheet / modal scrim.
    static var scrim: Color {
        Color(nsColor: nlDynamic(0x000000, 0x000000, lightAlpha: 0.25, darkAlpha: 0.45))
    }
}

// MARK: - Notch backdrop

/// The open notch is one system material carrying three possible surfaces.
/// AppKit decides how that material looks, including the frosted replacement
/// when Reduce Transparency is on; the chosen background only decides how much
/// black sits over it and how strong the flat cool field is.
///
/// The closed pill stays pure black so it still reads as part of the physical
/// notch rather than a floating translucent object.
struct NotchBackdrop: View {
    var style: NLBackground
    var isOpen: Bool
    var palette: [NSColor]

    var body: some View {
        ZStack {
            if isOpen {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)

                // A translucent black rather than an opaque fill, so even the
                // deepest theme still has a material faintly present under it.
                Color.black.opacity(style.scrim)

                // The cover's own palette, scattered as soft light.
                NotchScatterLight(palette: palette, strength: style.glowStrength)

                // 底部压暗:状态带的白字正好落在最亮的色团下方,这里保住对比度。
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0),
                        .init(color: .black.opacity(0.30), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

/// 把当前封面的色板铺成几团柔光:主色在封面后面,副色沿面板往外排。
///
/// 光的颜色来自封面本身(封面带粉,光就带粉),而不是一个固定色。三件事
/// 让它读作"光"而不是"染黑":screen 混合(深色只能加光)、颜色朝白提一档、
/// 渐隐到透明。黑白封面没有色板,这层就是空的 —— 没有可散的色,散光缺席。
///
/// 全部是静态层:每次换歌才算一次色板,不逐帧重算。
struct NotchScatterLight: View {
    let palette: [NSColor]
    /// 三档背景给出的强度:deep 0.45 / frosted 1.0 / clear 1.2。
    var strength: Double

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 190
            let spots: [(center: UnitPoint, radius: CGFloat, opacity: Double)] = [
                (UnitPoint(x: 0.14, y: 0.50), 230, 0.50),
                (UnitPoint(x: 0.46, y: 0.30), 180, 0.30),
                (UnitPoint(x: 0.78, y: 0.72), 160, 0.22),
            ]

            ZStack {
                ForEach(Array(zip(palette, spots).prefix(3).enumerated()), id: \.offset) { _, pair in
                    let (colour, spot) = pair
                    RadialGradient(
                        stops: [
                            .init(color: lifted(colour).opacity(spot.opacity * strength), location: 0),
                            .init(color: lifted(colour).opacity(spot.opacity * 0.32 * strength), location: 0.42),
                            .init(color: .clear, location: 1),
                        ],
                        center: spot.center,
                        startRadius: 0,
                        endRadius: spot.radius * scale
                    )
                }
            }
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }

    /// 封面可能很暗;朝白提一档,才读作"发光"而不是"染黑"。
    private func lifted(_ ns: NSColor) -> Color {
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return .white.opacity(0.5) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let lift: CGFloat = 0.34
        return Color(red: r + (1 - r) * lift, green: g + (1 - g) * lift, blue: b + (1 - b) * lift)
    }
}

// MARK: - Type scale

enum NLFont {
    /// 28 / 600 / 1.15 / -0.28px — empty-state and welcome hero titles.
    static var display: Font { .system(size: 28, weight: .semibold) }
    /// 24 / 600 — settings pane title (.pane-title).
    static var paneTitle: Font { .system(size: 24, weight: .semibold) }
    /// 20 / 600 — the icon-and-title block at the top of a settings pane.
    static var hero: Font { .system(size: 20, weight: .semibold) }
    /// 17 / 600 — panel headers and empty-state titles.
    static var titleLg: Font { .system(size: 17, weight: .semibold) }
    /// 13 / 600 — control labels, group headers, table headers.
    static var title: Font { .system(size: 13, weight: .semibold) }
    /// 13 / 400 — body copy and control text.
    static var body: Font { .system(size: 13, weight: .regular) }
    /// 13 / 600 — inline emphasis.
    static var bodyStrong: Font { .system(size: 13, weight: .semibold) }
    /// 11 / 400 — captions and popover shortcuts.
    static var caption: Font { .system(size: 11, weight: .regular) }
    /// 10 / 400 — version and legal lines.
    static var fine: Font { .system(size: 10, weight: .regular) }
    /// 13 / 400 — button titles.
    static var button: Font { .system(size: 13, weight: .regular) }
    /// 12 / 400 — segmented controls and mini buttons.
    static var mini: Font { .system(size: 12, weight: .regular) }
    /// 12 / 400 — sidebar and menu items.
    static var navLink: Font { .system(size: 13, weight: .regular) }
    /// SF Mono 12 — code and numeric columns.
    static var mono: Font { .system(size: 12, design: .monospaced) }
}

// MARK: - Spacing / radii / shadows / motion

enum NLSpace {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s12: CGFloat = 48
    /// Gap between settings groups.
    static let group: CGFloat = 14
    /// Settings side margin, 24pt.
    static let page: CGFloat = 24
    /// Settings row height.
    static let rowHeight: CGFloat = 44
    /// Settings row horizontal padding.
    static let rowPadding: CGFloat = 16
}

enum NLRadius {
    static let control: CGFloat = 6
    static let card: CGFloat = 10
    static let window: CGFloat = 12
    static let pill: CGFloat = 9999
}

/// Window and popover chrome only. Surfaces, controls and cards are flat.
enum NLShadow {
    /// Window: 0 24px 48px rgba(0,0,0,.18) + 0 0 0 1px rgba(0,0,0,.08)
    static let window = (color: Color.black.opacity(0.18), radius: 24.0, y: 24.0)
    static let windowDark = (color: Color.black.opacity(0.45), radius: 24.0, y: 24.0)
    /// Popover: 0 8px 24px rgba(0,0,0,.12) + 0 0 0 1px rgba(0,0,0,.06)
    static let popover = (color: Color.black.opacity(0.12), radius: 12.0, y: 8.0)
    static let popoverDark = (color: Color.black.opacity(0.40), radius: 12.0, y: 8.0)
}

enum NLMotion {
    static let press: Double = 0.10
    static let hover: Double = 0.10
    static let popover: Double = 0.18
    /// Switch knob travel.
    static let toggle: Double = 0.18
}

// MARK: - Notch surface tokens
//
// The notch is always drawn on a dark slab, so its text is a fixed ladder of
// white opacities rather than the dynamic light/dark pairs the settings window
// uses. Centralising them — and the notch's type sizes — keeps every reading in
// StatsView, NotchHomeView and NotchHeader on one disciplined scale instead of
// scattering `.white.opacity(...)` and `.system(size:)` literals through the views.

enum NLNotch {
    // White-on-dark text tints. Hierarchy comes from opacity + size, never colour.
    static let inkStrong: Color = .white.opacity(0.92)
    static let ink: Color = .white.opacity(0.82)
    static let inkSoft: Color = .white.opacity(0.72)
    static let detail: Color = .white.opacity(0.5)
    static let dim: Color = .white.opacity(0.45)
    static let faint: Color = .white.opacity(0.4)
    static let whisper: Color = .white.opacity(0.36)

    // Type — fixed sizes, but declared once so the strip stays coherent.
    static let metricNumber = Font.system(size: 19, weight: .semibold, design: .rounded)
    /// The one hero value on the stats strip — the reading itself. It is the
    /// only thing that earns a large size; everything else defers to it.
    static let metricHero = Font.system(size: 21, weight: .semibold, design: .rounded)
    static let metricUnit = Font.system(size: 9, weight: .semibold)
    static let metricLabel = Font.system(size: 10, weight: .semibold)
    static let metricDetail = Font.system(size: 9, weight: .medium)
    static let ringNumber = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let ringLabel = Font.system(size: 11, weight: .semibold)
    static let captionMedium = Font.system(size: 9, weight: .medium)
    static let footerReading = Font.system(size: 9, weight: .medium)
    static let glyphSmall = Font.system(size: 7, weight: .bold)

    // MARK: - Now Playing (renders on the notch slab)
    // The title owns the heaviest weight on this surface; nothing else exceeds it.
    // Hierarchy comes from size + weight + white opacity, never from the album
    // accent colour — that colour is reserved for the slider and active controls.
    // macOS HIG built-in text styles: Title 3 (15pt, emphasized Semibold),
    // Callout (12pt Regular), Caption 2 (10pt Medium). macOS has no Dynamic
    // Type, so styles are used for Apple's leading/tracking and as a single
    // source of truth, not for scaling. Weights stay explicit because the
    // marquee renderer applies the Font directly, bypassing view modifiers.
    static let playerTitle = Font.system(.title3, design: .default, weight: .semibold)
    static let playerArtist = Font.system(.callout, design: .default, weight: .regular)
    static let playerTime = Font.system(.caption2, design: .default, weight: .medium)
    static let playerTitleInk: Color = .white.opacity(0.95)
    static let playerArtistInk: Color = .white.opacity(0.72)

    // The player and header reuse a few system colours and sizes by name.
    // Sourcing them here keeps every notch surface — stats, player, header —
    // on the same token set instead of scattering literals.
    static let trackFill: Color = .gray.opacity(0.3)
    static let controlGlyph = Font.system(size: 14, weight: .medium)
    static let hudFont = Font.system(.headline, design: .rounded)

    // Now Playing brand accent — Apple Music pink. Reserved for active control
    // states (shuffle / repeat / favourite) only, so it stays a brand signal
    // instead of being diluted into a generic highlight.
    static let musicPink: Color = Color(red: 0.980, green: 0.137, blue: 0.231)

    // Notch container + HUD chrome.
    static let hudForeground: Color = .gray
    // Stats capsule card — standard-theme fill / stroke (vivid uses the metric accent).
    static let cellFill: Color = Color.white.opacity(0.06)
    static let cellStroke: Color = Color.white.opacity(0.08)
    // Network metric default tints (download reads brighter than upload).
    static let netDown: Color = Color.white.opacity(0.85)
    static let netDownSoft: Color = Color.white.opacity(0.78)
    static let netUp: Color = Color.white.opacity(0.4)
    static let netUpSoft: Color = Color.white.opacity(0.45)

    // Stats ring accents — four fixed index colours, one per metric, so the eye
    // maps colour → reading without having to read the label. These are
    // semantic indices, never ambient mood colours: each value is a constant,
    // never sampled from the wallpaper, and none of them ever means "alarm".
    static let statCpu: Color = Color(red: 1.000, green: 0.478, blue: 0.361)   // coral
    static let statGpu: Color = Color(red: 0.655, green: 0.545, blue: 0.980)   // violet
    static let statMemory: Color = Color(red: 0.310, green: 0.765, blue: 0.969) // sky
    static let statDisk: Color = Color(red: 0.239, green: 0.863, blue: 0.592)  // mint

    // MARK: - Lyrics tab (renders on the notch)
    // Current line stays below the song title's weight; the title is the
    // heaviest thing on the notch surface.
    static let lyricCurrent = Font.system(size: 13, weight: .medium)
    static let lyricOther = Font.system(size: 12, weight: .regular)
    /// The unfilled portion of the line currently being sung.
    static let lyricUnfilled: Color = .white.opacity(0.35)
    static let lyricCaption = Font.system(size: 9, weight: .regular)
    static let lyricMuted: Color = .gray.opacity(0.6)
    static let lyricStatic = Font.system(size: 11, weight: .regular)
    static let lyricPlaceholder: Color = .gray.opacity(0.7)

    // MARK: - Live-activity HUD overlays (volume / brightness / battery / events)
    static let hudValue = Font.system(size: 14, weight: .medium)
    static let hudLabel = Font.system(size: 13, weight: .medium)
    static let hudPercent = Font.system(size: 12, weight: .medium)
    static let hudStroke: Color = Color.white.opacity(0.1)
    static let hudBattery: Color = .white.opacity(0.5)
    static let hudEventFont = Font.system(size: 12, weight: .medium)
    static let hudEventGradient: [Color] = [.white, .white.opacity(0.2)]
}

// MARK: - Weather surface tokens
//
// The weather tab renders on its own sky card (a MeshGradient or layered
// LinearGradient with a dark scrim), not the shared black slab. Its white-text
// ladder and feature colours are tuned for that brighter surface, so they live
// in a feature-scoped set rather than being folded into `NLNotch` — keeping the
// shared tokens free of ~30 weather-specific values. Every member wraps the
// expression it replaces, so routing a view to these tokens changes nothing
// visible.

enum NLWeather {
    // White-on-sky text ladder. Hierarchy comes from opacity, never colour.
    static let inkTop: Color = .white.opacity(0.95) // "Now" / today emphasis
    static let inkHigh: Color = .white.opacity(0.90) // place name, curve endpoint
    static let ink: Color = .white.opacity(0.88) // condition, stat chip value
    static let inkMid: Color = .white.opacity(0.80) // weekday normal, empty message
    static let inkLow: Color = .white.opacity(0.70) // hour non-now, refresh, loading
    static let inkDim: Color = .white.opacity(0.65) // H/L range
    static let inkMute: Color = .white.opacity(0.60) // section header, toolbar idle
    static let inkFaint: Color = .white.opacity(0.55) // pin, chip icon, week low, empty icon
    static let inkWhisper: Color = .white.opacity(0.50) // updated label
    static let inkPin: Color = .white.opacity(0.45) // location-fill glyph

    // Surfaces — fills, strokes and the legibility scrim over the sky.
    static let cardFill: Color = .white.opacity(0.13)
    static let cardStroke: Color = .white.opacity(0.12)
    static let chipFill: Color = .white.opacity(0.12)
    static let toolbarOn: Color = .white.opacity(0.22)
    static let toolbarOff: Color = .white.opacity(0.08)
    static let skyScrimTop: Color = .black.opacity(0.18)
    static let skyScrimBottom: Color = .black.opacity(0.34)

    // Feature colours: the precipitation blue and the warm-temperature gold.
    static let precip: Color = Color(red: 0.45, green: 0.82, blue: 1.0)
    static let warm: Color = Color(red: 1.0, green: 0.83, blue: 0.4)

    // Type — role-named, each declared once so the tab stays coherent.
    static let toolbar = Font.system(size: 10, weight: .semibold)
    static let updated = Font.system(size: 9)
    static let refresh = Font.system(size: 10, weight: .semibold)
    static let place = Font.system(size: 12, weight: .semibold)
    static let pin = Font.system(size: 7)
    static let heroTemp = Font.system(size: 36, weight: .thin)
    static let condition = Font.system(size: 12, weight: .medium)
    static let range = Font.system(size: 10, weight: .medium)
    static let chipIcon = Font.system(size: 8, weight: .medium)
    static let chipText = Font.system(size: 9, weight: .semibold)
    static let hourLabel = Font.system(size: 10, weight: .medium)
    static let hourGlyph = Font.system(size: 14)
    static let hourTemp = Font.system(size: 12, weight: .semibold)
    static let curveTemp = Font.system(size: 9, weight: .semibold)
    static let weekday = Font.system(size: 10, weight: .regular)
    static let weekdayEmph = Font.system(size: 10, weight: .semibold)
    static let weekPrecip = Font.system(size: 9, weight: .medium)
    static let weekSymbol = Font.system(size: 11)
    static let weekTemp = Font.system(size: 10, weight: .regular)
    static let weekTempEmph = Font.system(size: 10, weight: .semibold)
    static let sectionIcon = Font.system(size: 8, weight: .semibold)
    static let sectionText = Font.system(size: 9, weight: .semibold)
    static let stateText = Font.system(size: 11)
    static let emptyIcon = Font.system(size: 26)
    static let emptyButton = Font.system(size: 11, weight: .medium)

    // A few one-off sizes/fills that still belong to this surface, not NLNotch.
    static let nowGlyph = Font.system(size: 30)
    static let rangeTrack: Color = .white.opacity(0.18)
    static let emptyButtonFill: Color = .white.opacity(0.16)
}

// MARK: - QuickNote surface tokens
//
// The quick-note tab draws its own dark capsule controls (the comment in the
// source explains why: a bordered system button clashes with the notch's
// self-drawn chrome). Its text ladder, capsule fills and glyph sizes form a
// small coherent set, scoped here so they don't bleed into the shared tokens.
// Semantic system colours (`.accentColor`, `.orange`, `.green`) are left alone.

enum NLQuickNote {
    // White-on-dark text ladder.
    static let inkTop: Color = .white.opacity(0.95)
    static let inkStrong: Color = .white.opacity(0.85)
    static let inkSoft: Color = .white.opacity(0.80)
    static let inkMid: Color = .white.opacity(0.75)
    static let inkMuted: Color = .white.opacity(0.60)
    static let inkDim: Color = .white.opacity(0.55)
    static let inkFaint: Color = .white.opacity(0.50)
    static let inkWhisper: Color = .white.opacity(0.30)

    // Capsule / panel fills.
    static let rowFill: Color = .white.opacity(0.06)
    static let divider: Color = .white.opacity(0.15)
    static let tabOn: Color = .white.opacity(0.22)
    static let tabOff: Color = .white.opacity(0.07)
    static let chipFill: Color = .white.opacity(0.14)
    static let formatOff: Color = .white.opacity(0.08)
    static let editorFill: Color = .white.opacity(0.08)

    // Glyph + label type.
    static let glyphSmall = Font.system(size: 11)
    static let glyphMini = Font.system(size: 10)
    static let title = Font.system(size: 12, weight: .semibold)
    static let caption12 = Font.system(size: 12)
    static let body = Font.system(size: 11)
    static let fine = Font.system(size: 10)
    static let tab = Font.system(size: 10, weight: .regular)
    static let tabEmph = Font.system(size: 10, weight: .semibold)
    static let chip = Font.system(size: 11, weight: .medium)
    static let chipSmall = Font.system(size: 10, weight: .medium)
    static let formatGlyph = Font.system(size: 11, weight: .semibold)

    // Corner radii used by this surface's capsules and panels.
    static let folderRowRadius: CGFloat = 5
    static let formatButtonRadius: CGFloat = 4
    static let editorRadius: CGFloat = 8
}

// MARK: - Shelf surface tokens
//
// The shelf tab is its own surface: a row of file/link/text tiles plus the
// AirDrop share square, drawn on the notch slab. Its tile geometry, the
// share-square drop-zone styling and the drag-preview chip form a small
// coherent set, scoped here so they don't bleed into the shared notch tokens.
// Semantic system colours (`.accentColor`, `.gray`) are left alone.

enum NLShelf {
    // Tile geometry — the file/link/text tile and its thumbnail.
    static let itemWidth: CGFloat = 105
    static let iconSize: CGFloat = 56
    static let cardRadius: CGFloat = 12
    /// Outer panel stroke radius (slightly larger than the tile).
    static let panelRadius: CGFloat = 16

    // Tile / drag-preview name text.
    static let nameFont = Font.system(size: 12, weight: .medium)
    /// Text sitting on the accent-filled drag-preview chip.
    static let nameOnAccent: Color = .white
    /// The drag-preview chip radius (accent-filled label behind the name).
    static let chipRadius: CGFloat = 4

    // MARK: - Drop zone (the AirDrop / share square + the panel outline)
    static let dropTop: Color = .black.opacity(0.35)
    static let dropBottom: Color = .black.opacity(0.20)
    /// Active border is accent-tinted; idle is a faint white hairline.
    static let dropBorderActive: Color = Color.accentColor.opacity(0.9)
    static let dropBorderIdle: Color = Color.white.opacity(0.1)
    static let dropBorderWidth: CGFloat = 3
    static let dropBorderDash: [CGFloat] = [10]
    /// Inner circle fill, brightening when a drop is targeted.
    static let circleFillActive: Color = .white.opacity(0.11)
    static let circleFillIdle: Color = .white.opacity(0.09)
    static let providerText: Color = .white.opacity(0.8)
    static let loadingFill: Color = .black.opacity(0.3)
}

// MARK: - Dividers

struct NLDivider: View {
    var body: some View {
        Rectangle()
            .fill(NLColor.borderDivider)
            .frame(height: 1)
    }
}

/// Row divider: inset to where the row's text starts, which is what makes the
/// hairline read as a separation between rows rather than under the whole card.
/// The inset is 16pt on an icon-less row and 16 + 22 + 10 when an icon precedes
/// the text, so the line always begins under the label.
struct NLRowDivider: View {
    var inset: CGFloat = NLSpace.rowPadding

    init(inset: CGFloat = NLSpace.rowPadding) {
        self.inset = inset
    }

    var body: some View {
        Rectangle()
            .fill(NLColor.borderDivider)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

// MARK: - Badge

struct NLBadge: View {
    let text: String

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(NLFont.caption)
            .foregroundStyle(NLColor.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(NLColor.panel)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(NLColor.borderHairline, lineWidth: 1))
    }
}

// MARK: - Settings group (themed translucent card + radius-card; hairline only in Dark Mode)

struct NLSection<Content: View>: View {
    @Default(.notchBackground) private var background

    private let title: String?
    private let badge: String?
    private let footer: String?
    private let content: Content

    init(
        _ title: String? = nil,
        badge: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.badge = badge
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpace.s2) {
            if title != nil || badge != nil {
                HStack(spacing: NLSpace.s2) {
                    if let title {
                        Text(LocalizedStringKey(title))
                            .font(NLFont.title)
                            .foregroundStyle(NLColor.textSecondary)
                    }
                    if let badge { NLBadge(text: badge) }
                }
            }

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NLSettingsSurface.card(background))
            .clipShape(RoundedRectangle(cornerRadius: NLRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NLRadius.card, style: .continuous)
                    .strokeBorder(NLSettingsSurface.cardStroke(background), lineWidth: 1)
            )

            if let footer {
                Text(LocalizedStringKey(footer))
                    .font(NLFont.caption)
                    .foregroundStyle(NLColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NLSpace.rowPadding)
                    .padding(.top, NLSpace.s1)
            }
        }
    }
}

/// Standalone footnote at the end of a group, outside the card.
struct NLFootnote: View {
    let text: String
    var link: (label: String, url: URL)?

    init(_ text: String, link: (label: String, url: URL)? = nil) {
        self.text = text
        self.link = link
    }

    var body: some View {
        HStack(spacing: NLSpace.s1) {
            Text(LocalizedStringKey(text))
                .font(NLFont.caption)
                .foregroundStyle(NLColor.textSecondary)
            if let link {
                Link(LocalizedStringKey(link.label), destination: link.url)
                    .font(NLFont.caption)
                    .foregroundStyle(NLColor.accent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, NLSpace.rowPadding)
        .padding(.vertical, NLSpace.s1)
    }
}

// MARK: - Settings row (44pt tall, 16pt padding, icon + label left / control right, 1px divider)

/// One row of a settings group.
///
/// Apple's rows lead with a small rounded tile holding a glyph. It is not
/// decoration: the tile anchors the eye, puts every label on one vertical axis,
/// and gives colour somewhere to live on the few rows that have something to say
/// (a red Apple mark, a blue AirDrop mark) without colouring the other forty.
struct NLRow<Trailing: View>: View {
    private let icon: String?
    private let title: String
    private let subtitle: String?
    private let badge: String?
    private let swatch: Color?
    private let showsDivider: Bool
    private let trailing: Trailing

    /// 22pt tile — the same column width the sidebar uses, so the two read as
    /// one system when the window is open.
    private let iconSize: CGFloat = 22
    private let iconGap: CGFloat = 10

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        swatch: Color? = nil,
        showsDivider: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.swatch = swatch
        self.showsDivider = showsDivider
        self.trailing = trailing()
    }

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: NLSpace.s4) {
                HStack(spacing: iconGap) {
                    if let icon {
                        RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                            .fill(NLColor.fillNeutral.opacity(0.35))
                            .frame(width: iconSize, height: iconSize)
                            .overlay(
                                Image(systemName: icon)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(NLColor.textSecondary)
                            )
                    }

                    if let swatch {
                        Circle()
                            .fill(swatch)
                            .frame(width: 10, height: 10)
                    }

                    VStack(alignment: .leading, spacing: NLSpace.s1) {
                        HStack(spacing: NLSpace.s2) {
                            Text(LocalizedStringKey(title))
                                .font(NLFont.body)
                                .foregroundStyle(isEnabled ? NLColor.textPrimary : NLColor.textTertiary)
                            if let badge { NLBadge(text: badge) }
                        }
                        if let subtitle {
                            Text(LocalizedStringKey(subtitle))
                                .font(NLFont.caption)
                                .foregroundStyle(
                                    isEnabled ? NLColor.textSecondary : NLColor.textTertiary
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Spacer(minLength: NLSpace.s3)

                trailing
            }
            .padding(.horizontal, NLSpace.rowPadding)
            .frame(minHeight: NLSpace.rowHeight)

            if showsDivider {
                NLRowDivider(inset: NLSpace.rowPadding + (icon == nil ? 0 : iconSize + iconGap))
            }
        }
    }
}

extension NLRow where Trailing == EmptyView {
    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        swatch: Color? = nil,
        showsDivider: Bool = false
    ) {
        self.init(
            icon: icon, title: title, subtitle: subtitle, badge: badge, swatch: swatch,
            showsDivider: showsDivider
        ) {
            EmptyView()
        }
    }
}

// MARK: - Navigation row (fill-hover on hover, value + 12pt chevron on the right)

struct NLNavRow: View {
    let title: String
    var subtitle: String?
    var value: String?
    var valueIsAccent: Bool = false
    var showsDivider: Bool = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: NLSpace.s2) {
                    VStack(alignment: .leading, spacing: NLSpace.s1) {
                        Text(LocalizedStringKey(title))
                            .font(NLFont.body)
                            .foregroundStyle(isEnabled ? NLColor.textPrimary : NLColor.textTertiary)
                        if let subtitle {
                            Text(LocalizedStringKey(subtitle))
                                .font(NLFont.caption)
                                .foregroundStyle(NLColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: NLSpace.s3)

                    if let value {
                        Text(value)
                            .font(NLFont.body)
                            .foregroundStyle(valueIsAccent ? NLColor.accent : NLColor.textSecondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NLColor.textTertiary)
                }
                .padding(.horizontal, NLSpace.rowPadding)
                .frame(minHeight: NLSpace.rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHovering && isEnabled ? NLColor.hoverFill : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: NLMotion.hover), value: isHovering)

            if showsDivider { NLRowDivider() }
        }
    }
}

// MARK: - Switch (38×24 pill, 20pt white knob, 14pt travel, opacity .5 when disabled)

struct NLSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        SwitchBody(configuration: configuration)
    }

    private struct SwitchBody: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? NLColor.accent : NLColor.fillNeutral)
                    .frame(width: 38, height: 24)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                            .padding(2)
                    }
                    .opacity(isEnabled ? 1 : 0.5)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: NLMotion.toggle),
                        value: configuration.isOn
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
        }
    }
}

struct NLSwitch: View {
    @Binding var isOn: Bool
    var accessibilityLabel: String?

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(NLSwitchToggleStyle())
            .accessibilityLabel(LocalizedStringKey(accessibilityLabel ?? ""))
    }
}

// MARK: - Checkbox / radio (16×16, 1px border-strong, solid accent when on)

struct NLCheckbox: View {
    let title: String
    @Binding var isOn: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: NLSpace.s2) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? NLColor.accent : NLColor.canvas)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(
                                isOn ? NLColor.accent : NLColor.borderStrong, lineWidth: 1)
                    )
                    .frame(width: 16, height: 16)
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(NLColor.textOnAccent)
                        }
                    }

                Text(LocalizedStringKey(title))
                    .font(NLFont.body)
                    .foregroundStyle(isEnabled ? NLColor.textPrimary : NLColor.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Buttons (28pt tall, 32pt large, radius 6, 14pt horizontal padding)
//
// Pill shapes are reserved for switches, tags and segmented containers. The
// primary button is never a pill.

enum NLButtonVariant {
    case primary
    case secondary
    case ghost
    case destructive
}

struct NLButtonStyle: ButtonStyle {
    var variant: NLButtonVariant = .primary
    /// Large button, 32pt. Only 28 and 32 are allowed.
    var large: Bool = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        ButtonBody(configuration: configuration, variant: variant, large: large)
    }

    private struct ButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let variant: NLButtonVariant
        let large: Bool

        @State private var isHovering = false
        @FocusState private var isFocused: Bool
        @Environment(\.isEnabled) private var isEnabled

        private var height: CGFloat { large ? 32 : 28 }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
        }

        /// Disabled primary = accent@40% + white text at 90%.
        private var background: Color {
            guard isEnabled else { return variant == .primary ? NLColor.accent.opacity(0.4) : .clear }
            switch variant {
            case .primary:
                return configuration.isPressed
                    ? NLColor.accentPressed : (isHovering ? NLColor.accentHover : NLColor.accent)
            case .secondary:
                return configuration.isPressed ? NLColor.panel : NLColor.canvas
            case .ghost:
                return isHovering ? NLColor.hoverFill : .clear
            case .destructive:
                return isHovering ? NLColor.destructive.opacity(0.08) : .clear
            }
        }

        private var foreground: Color {
            guard isEnabled else {
                return variant == .primary
                    ? Color.white.opacity(0.9) : NLColor.textTertiary
            }
            switch variant {
            case .primary: return NLColor.textOnAccent
            case .secondary: return NLColor.textPrimary
            case .ghost: return NLColor.accent
            case .destructive: return NLColor.destructive
            }
        }

        private var stroke: Color? {
            guard isEnabled else {
                return variant == .secondary ? NLColor.borderDivider : nil
            }
            switch variant {
            case .secondary: return isHovering ? NLColor.borderStrong : NLColor.borderHairline
            case .destructive: return NLColor.destructive
            default: return nil
            }
        }

        var body: some View {
            configuration.label
                .font(NLFont.button)
                .foregroundStyle(foreground)
                .padding(.horizontal, 14)
                .frame(height: height)
                .background(background)
                .clipShape(shape)
                .overlay {
                    if let stroke { shape.strokeBorder(stroke, lineWidth: 1) }
                }
                .overlay {
                    // Keyboard focus ring: 2px accent-hover, 2px offset
                    if isFocused {
                        shape
                            .strokeBorder(NLColor.accentRing, lineWidth: 2)
                            .padding(-2)
                    }
                }
                .animation(.easeOut(duration: NLMotion.hover), value: isHovering)
                .animation(.easeOut(duration: NLMotion.press), value: configuration.isPressed)
                .contentShape(shape)
                .onHover { isHovering = $0 }
                .focused($isFocused)
        }
    }
}

/// Mini button (22pt tall, 10pt padding, 12pt text, border-strong stroke).
struct NLMiniButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        MiniBody(configuration: configuration)
    }

    private struct MiniBody: View {
        let configuration: ButtonStyleConfiguration

        @State private var isHovering = false
        @FocusState private var isFocused: Bool
        @Environment(\.isEnabled) private var isEnabled

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
        }

        var body: some View {
            configuration.label
                .font(NLFont.mini)
                .foregroundStyle(isEnabled ? NLColor.textPrimary : NLColor.textTertiary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(configuration.isPressed ? NLColor.panel : NLColor.canvas)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        isHovering && isEnabled ? NLColor.textTertiary : NLColor.borderStrong,
                        lineWidth: 1)
                }
                .overlay {
                    if isFocused {
                        shape.strokeBorder(NLColor.accentRing, lineWidth: 2).padding(-2)
                    }
                }
                .contentShape(shape)
                .onHover { isHovering = $0 }
                .focused($isFocused)
        }
    }
}

// MARK: - Pop-up select (22pt tall, 8pt padding, border-strong, 10pt chevrons)
//
// Deliberately not SwiftUI's `Menu`: on macOS 26 it paints its own blue chevron
// over the left edge of the label and discards custom strokes and fills. A
// `Button` plus a `popover` keeps the layout fully under our control.

struct NLSelectOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: String { label }
}

struct NLSelect<Value: Hashable>: View {
    let options: [NLSelectOption<Value>]
    @Binding var selection: Value
    var minWidth: CGFloat = 0
    /// Pass `false` when the labels are product names (e.g. "Apple Music")
    /// that must render verbatim in every language. By default the label is
    /// treated as a localized key, matching the pre-existing behavior.
    var localizesLabel: Bool = true

    @State private var isHovering = false
    @State private var isPresented = false
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var currentLabel: String {
        options.first(where: { $0.value == selection })?.label ?? "—"
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: NLSpace.s2) {
                if localizesLabel {
                    Text(LocalizedStringKey(currentLabel))
                        .font(NLFont.body)
                        .foregroundStyle(isEnabled ? NLColor.textPrimary : NLColor.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(verbatim: currentLabel)
                        .font(NLFont.body)
                        .foregroundStyle(isEnabled ? NLColor.textPrimary : NLColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(NLColor.textSecondary)
            }
            .padding(.horizontal, NLSpace.s2)
            .frame(height: 22)
            .frame(minWidth: minWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                    .fill(NLColor.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? NLColor.accent
                            : (isHovering && isEnabled ? NLColor.textTertiary : NLColor.borderStrong),
                        lineWidth: isFocused ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: NLMotion.hover), value: isHovering)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            NLSelectList(
                options: options, selection: $selection,
                dismiss: { isPresented = false }, localizesLabel: localizesLabel
            )
        }
    }
}

/// The expanded option list (220pt wide, 24pt rows, radius 6, solid accent with white text on hover).
private struct NLSelectList<Value: Hashable>: View {
    let options: [NLSelectOption<Value>]
    @Binding var selection: Value
    let dismiss: () -> Void
    var localizesLabel: Bool = true

    var body: some View {
        NLMenu {
            ForEach(options) { option in
                NLMenuItem(
                    title: option.label,
                    shortcut: nil,
                    isDanger: false,
                    isSelected: option.value == selection,
                    localizesTitle: localizesLabel
                ) {
                    selection = option.value
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Menu / menu item

struct NLMenu<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(6)
        .frame(minWidth: 200, alignment: .leading)
        .background(NLColor.elevated)
        .clipShape(RoundedRectangle(cornerRadius: NLRadius.card, style: .continuous))
    }
}

struct NLMenuItem: View {
    let title: String
    var shortcut: String?
    var isDanger: Bool = false
    var isSelected: Bool = false
    /// Pass `false` for product names that must not be run through the
    /// localization table (see NLSelect.localizesLabel).
    var localizesTitle: Bool = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: NLSpace.s2) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 12)
                    .foregroundStyle(isHovering ? NLColor.textOnAccent : NLColor.accent)
                    .opacity(isSelected ? 1 : 0)

                if localizesTitle {
                    Text(LocalizedStringKey(title))
                        .font(NLFont.body)
                        .foregroundStyle(labelColor)
                } else {
                    Text(verbatim: title)
                        .font(NLFont.body)
                        .foregroundStyle(labelColor)
                }

                Spacer(minLength: NLSpace.s4)

                if let shortcut {
                    Text(shortcut)
                        .font(NLFont.caption)
                        .foregroundStyle(
                            isHovering ? Color.white.opacity(0.75) : NLColor.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                    .fill(isHovering ? (isDanger ? NLColor.destructive : NLColor.accent) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var labelColor: Color {
        if isHovering { return NLColor.textOnAccent }
        return isDanger ? NLColor.destructive : NLColor.textPrimary
    }
}

/// Menu separator (1px, 10pt at the sides, 6pt above and below).
struct NLMenuSeparator: View {
    var body: some View {
        NLDivider()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

// MARK: - Page shell (grey background, 24pt margins, 14pt between groups)

/// The pane header, laid out the way System Settings does it: a large icon tile,
/// the pane name, and one line of description — all centred, inside a card that
/// sits a shade darker than the white group cards underneath. It reads as "you
/// are here" rather than as a document title, which is why the icon leads.
struct NLPageHeader: View {
    @Default(.notchBackground) private var background

    let title: String
    var subtitle: String?
    var icon: String?

    var body: some View {
        VStack(spacing: NLSpace.s2) {
            if let icon {
                RoundedRectangle(cornerRadius: NLRadius.window, style: .continuous)
                    .fill(NLColor.elevated)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(NLColor.textSecondary)
                    )
            }

            Text(LocalizedStringKey(title))
                .font(NLFont.hero)
                .foregroundStyle(NLColor.textPrimary)

            if let subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(NLFont.caption)
                    .foregroundStyle(NLColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
        }
        .padding(.vertical, NLSpace.s6)
        .padding(.horizontal, NLSpace.s4)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(NLSettingsSurface.card(background))
        .clipShape(RoundedRectangle(cornerRadius: NLRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NLRadius.card, style: .continuous)
                .strokeBorder(NLSettingsSurface.cardStroke(background), lineWidth: 1)
        )
    }
}

struct NLPage<Content: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    private let content: Content

    init(_ title: String, subtitle: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpace.group) {
                NLPageHeader(title: title, subtitle: subtitle, icon: icon)

                content
            }
            .padding(.horizontal, NLSpace.page)
            .padding(.top, NLSpace.s4)
            .padding(.bottom, NLSpace.s8)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // No page fill: the window's single scrim sits behind this scroll view.
        // Painting it here as well would stack two translucent layers and make
        // the material disappear behind them.
    }
}

// MARK: - Sidebar (232pt, themed translucent tint, 1px divider on the right, search + account + nav)

struct NLSidebarItem: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
}

struct NLSidebarGroup: Identifiable {
    let id: String
    let title: String?
    let items: [NLSidebarItem]
}

struct NLSidebar: View {
    @Default(.notchBackground) private var background
    @Binding var selection: String
    let groups: [NLSidebarGroup]
    /// Pass a binding to show the search field and filter the nav items by it.
    var searchText: Binding<String>?
    var brandIcon: NSImage?
    var brandTitle: String?
    var brandSubtitle: String?

    private var query: String {
        (searchText?.wrappedValue ?? "").trimmingCharacters(in: .whitespaces)
    }

    private func matches(_ item: NLSidebarItem) -> Bool {
        guard !query.isEmpty else { return true }
        return L(item.label).localizedCaseInsensitiveContains(query)
    }

    private var visibleGroups: [(group: NLSidebarGroup, items: [NLSidebarItem])] {
        groups.compactMap { group in
            let items = group.items.filter(matches)
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let searchText {
                NLSearchField(text: searchText, placeholder: "Search")
                    .padding(.horizontal, 10)
                    .padding(.top, NLSpace.s1)
                    .padding(.bottom, 10)
            }

            if brandTitle != nil {
                NLAccountBlock(
                    icon: brandIcon, title: brandTitle ?? "", subtitle: brandSubtitle ?? ""
                )
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, NLSpace.s3)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(visibleGroups.enumerated()), id: \.element.group.id) { entry in
                        if entry.offset > 0 {
                            Spacer().frame(height: entry.element.group.title == nil ? 8 : 16)
                        }
                        if let title = entry.element.group.title {
                            Text(LocalizedStringKey(title))
                                .font(NLFont.caption)
                                .foregroundStyle(NLColor.textTertiary)
                                .padding(.horizontal, NLSpace.s2)
                                .padding(.bottom, NLSpace.s1)
                        }
                        ForEach(entry.element.items) { item in
                            NLSidebarRow(item: item, isSelected: selection == item.id) {
                                selection = item.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, NLSpace.s2)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, NLSpace.s1)
        .padding(.bottom, 10)
        .frame(width: 232, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NLSettingsSurface.sidebar(background))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NLColor.borderDivider)
                .frame(width: 1)
        }
    }
}

/// Account / brand block at the top of the sidebar (36pt rounded icon, 13/600 name, 11pt subtitle).
struct NLAccountBlock: View {
    var icon: NSImage?
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(NLColor.panel)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 0) {
                Text(LocalizedStringKey(title))
                    .font(NLFont.title)
                    .foregroundStyle(NLColor.textPrimary)
                Text(LocalizedStringKey(subtitle))
                    .font(NLFont.caption)
                    .foregroundStyle(NLColor.textSecondary)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct NLSidebarRow: View {
    let item: NLSidebarItem
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool
    @Environment(\.controlActiveState) private var controlActiveState

    /// Selection turns neutral grey while the window is inactive.
    private var isWindowActive: Bool { controlActiveState != .inactive }

    private var fill: Color {
        if isSelected {
            return isWindowActive ? NLColor.fillSelection : NLColor.sidebarSelectionInactive
        }
        return isHovering ? NLColor.hoverFill : Color.clear
    }

    private var isEmphasized: Bool { isSelected && isWindowActive }

    var body: some View {
        Button(action: action) {
            HStack(spacing: NLSpace.s2) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: isEmphasized ? .semibold : .regular))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(isEmphasized ? NLColor.accent : NLColor.textSecondary)

                Text(LocalizedStringKey(item.label))
                    .font(.system(size: 13, weight: isEmphasized ? .semibold : .regular))
                    .foregroundStyle(NLColor.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, NLSpace.s2)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                    .fill(fill)
            )
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                        .strokeBorder(NLColor.accentRing, lineWidth: 2)
                        .padding(-1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: NLMotion.hover), value: isHovering)
    }
}

// MARK: - Segmented control (bg-panel container, radius 6, 2pt padding, 2pt gap)

struct NLSegmentedOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: String { label }
}

struct NLSegmented<Value: Hashable>: View {
    let options: [NLSegmentedOption<Value>]
    @Binding var selection: Value

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(LocalizedStringKey(option.label))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(
                            isSelected ? NLColor.textPrimary : NLColor.textSecondary
                        )
                        .lineLimit(1)
                        .padding(.horizontal, NLSpace.s3)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isSelected ? NLColor.canvas : Color.clear)
                                .shadow(
                                    color: .black.opacity(isSelected ? 0.1 : 0),
                                    radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                .fill(NLColor.panel)
        )
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Slider (4pt pill track, accent fill, 18pt white knob with border-strong stroke)

struct NLSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var width: CGFloat = 160

    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func setValue(at x: CGFloat) {
        let f = min(max(x / width, 0), 1)
        let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
        let stepped = step > 0 ? (raw / step).rounded() * step : raw
        value = min(max(stepped, range.lowerBound), range.upperBound)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(NLColor.fillNeutral)
                .frame(height: 4)

            Capsule()
                .fill(NLColor.accent)
                .frame(width: max(0, CGFloat(fraction) * width), height: 4)

            Circle()
                .fill(.white)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(NLColor.borderStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                .offset(x: max(0, CGFloat(fraction) * width - 9))
        }
        .frame(width: width, height: 18)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { setValue(at: $0.location.x) }
        )
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                    .strokeBorder(NLColor.accentRing, lineWidth: 2)
                    .padding(-4)
            }
        }
        .focused($isFocused)
        .onKeyPress(.leftArrow) {
            value = max(range.lowerBound, value - step)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            value = min(range.upperBound, value + step)
            return .handled
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Text field (28pt tall, 8pt padding, 1px hairline, 2px accent when focused)

struct NLTextField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat?
    var isError: Bool = false
    var errorText: String?

    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var strokeColor: Color {
        if isError { return NLColor.destructive }
        return isFocused ? NLColor.accent : NLColor.borderHairline
    }

    var body: some View {
        HStack(spacing: NLSpace.s2) {
            HStack(spacing: NLSpace.s2) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(NLFont.body)
                    .foregroundStyle(NLColor.textPrimary)
                    .focused($isFocused)
                    .overlay(alignment: .leading) {
                        if text.isEmpty {
                            Text(LocalizedStringKey(placeholder))
                                .font(NLFont.body)
                                .foregroundStyle(NLColor.textTertiary)
                                .allowsHitTesting(false)
                        }
                    }

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(NLColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
            }
            // On focus the stroke grows to 2px; dropping 1px of padding keeps the text where it was.
            .padding(.horizontal, isFocused ? 7 : NLSpace.s2)
            .frame(height: 28)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                    .fill(NLColor.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: isFocused || isError ? 2 : 1)
            )

            if isError, let errorText {
                Text(LocalizedStringKey(errorText))
                    .font(NLFont.caption)
                    .foregroundStyle(NLColor.destructive)
                    .lineLimit(1)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Search field (28pt tall, radius 6, search-bg fill)

struct NLSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NLColor.textTertiary)

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(NLFont.body)
                .foregroundStyle(NLColor.textPrimary)
                .focused($isFocused)
                .overlay(alignment: .leading) {
                    if text.isEmpty {
                        Text(LocalizedStringKey(placeholder))
                            .font(NLFont.body)
                            .foregroundStyle(NLColor.textTertiary)
                            .allowsHitTesting(false)
                    }
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(NLColor.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, NLSpace.s2)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                .fill(NLColor.searchBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                .strokeBorder(isFocused ? NLColor.accent : NLColor.borderHairline, lineWidth: 1)
        )
    }
}

// MARK: - Empty state (96pt hero block, 17/600 title, 11pt caption, one primary button)

struct NLEmptyState: View {
    var icon: String?
    let title: String
    var message: String?
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NLColor.panel)
                .frame(width: 96, height: 96)
                .overlay {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 36, weight: .regular))
                            .foregroundStyle(NLColor.textTertiary)
                    }
                }
                .padding(.bottom, NLSpace.group)

            Text(LocalizedStringKey(title))
                .font(NLFont.titleLg)
                .foregroundStyle(NLColor.textPrimary)
                .padding(.bottom, NLSpace.s1)

            if let message {
                Text(LocalizedStringKey(message))
                    .font(NLFont.caption)
                    .foregroundStyle(NLColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, NLSpace.group)
            }

            if let actionLabel, let action {
                Button(action: action) { Text(LocalizedStringKey(actionLabel)) }
                    .buttonStyle(NLButtonStyle(variant: .primary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: - List row (28pt tall, solid accent with white text when selected, accent@6% on hover, no stripes)

struct NLListRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var swatch: Color?
    var isSelected: Bool = false
    var showsDivider: Bool = false
    var onTap: (() -> Void)?
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        swatch: Color? = nil,
        isSelected: Bool = false,
        showsDivider: Bool = false,
        onTap: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.swatch = swatch
        self.isSelected = isSelected
        self.showsDivider = showsDivider
        self.onTap = onTap
        self.trailing = trailing()
    }

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: NLSpace.s3) {
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .frame(width: 10, height: 10)
                }

                VStack(alignment: .leading, spacing: NLSpace.s1) {
                    Text(LocalizedStringKey(title))
                        .font(NLFont.body)
                        .foregroundStyle(isSelected ? NLColor.textOnAccent : NLColor.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(LocalizedStringKey(subtitle))
                            .font(NLFont.caption)
                            .foregroundStyle(
                                isSelected
                                    ? NLColor.textOnAccent.opacity(0.8) : NLColor.textSecondary
                            )
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: NLSpace.s3)

                trailing
            }
            .padding(.horizontal, NLSpace.rowPadding)
            .padding(.vertical, subtitle == nil ? 0 : NLSpace.s1)
            .frame(minHeight: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? NLColor.accent
                    : (isHovering && onTap != nil ? NLColor.fillSelectionHover : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            .onHover { isHovering = $0 }

            if showsDivider { NLDivider() }
        }
    }
}

extension NLListRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        swatch: Color? = nil,
        isSelected: Bool = false,
        showsDivider: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.init(
            title: title, subtitle: subtitle, swatch: swatch, isSelected: isSelected,
            showsDivider: showsDivider, onTap: onTap
        ) {
            EmptyView()
        }
    }
}

// MARK: - Icon button (28×28, radius 6, no fill; fill-hover on hover; accent when selected)

struct NLIconButton: View {
    let systemName: String
    var help: String?
    var isEnabled: Bool = true
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private var foreground: Color {
        if !isEnabled { return NLColor.textTertiary }
        if isSelected { return NLColor.accent }
        return isHovering ? NLColor.textPrimary : NLColor.textSecondary
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                        .fill(
                            isSelected
                                ? NLColor.fillSelection
                                : (isHovering && isEnabled ? NLColor.hoverFill : Color.clear))
                )
                .overlay {
                    if isFocused {
                        RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                            .strokeBorder(NLColor.accentRing, lineWidth: 2)
                            .padding(-1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: NLMotion.hover), value: isHovering)
        .help(LocalizedStringKey(help ?? ""))
    }
}

// MARK: - Binding adapters

extension Binding where Value == CGFloat {
    /// Feeds a `CGFloat` binding into a control that only takes `Double` (e.g. `NLSlider`).
    var asDouble: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = CGFloat($0) }
        )
    }
}

// MARK: - Cursor

extension View {
    /// Gives non-Button clickable elements the pointing-hand cursor on macOS.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
