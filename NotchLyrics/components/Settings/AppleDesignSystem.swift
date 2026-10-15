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
//  - Settings layout: content area on --content-bg (grey) with --card-bg group
//    cards (white, borderless) and 44pt rows.
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

    /// --content-bg: settings content background (grey). #f5f5f7 / #232325
    static var contentBg: Color { Color(nsColor: nlDynamic(0xF5F5F7, 0x232325)) }
    /// --card-bg: settings group card background (white). #ffffff / #333336
    static var cardBg: Color { Color(nsColor: nlDynamic(0xFFFFFF, 0x333336)) }
    /// --search-bg: sidebar search field background. #ffffff / rgba(255,255,255,.08)
    static var searchBg: Color {
        Color(nsColor: nlDynamic(0xFFFFFF, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.08))
    }
    /// --material: titlebar / sidebar material (rgba(249,249,251,.82) / rgba(46,46,48,.82)).
    static var material: Color {
        Color(nsColor: nlDynamic(0xF9F9FB, 0x2E2E30, lightAlpha: 0.82, darkAlpha: 0.82))
    }

    /// For use from the AppKit window layer.
    static var contentNSColor: NSColor { nlDynamic(0xF5F5F7, 0x232325) }
    static var panelNSColor: NSColor { nlDynamic(0xF5F5F7, 0x2A2A2C) }
    static var canvasNSColor: NSColor { nlDynamic(0xFFFFFF, 0x272729) }

    /// --border-hairline / --border-divider / --border-strong
    static var borderHairline: Color { Color(nsColor: nlDynamic(0xE0E0E0, 0x3A3A3C)) }
    static var borderDivider: Color { Color(nsColor: nlDynamic(0xF0F0F0, 0x2F2F31)) }
    static var borderStrong: Color { Color(nsColor: nlDynamic(0xD2D2D7, 0x48484A)) }

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

// MARK: - Type scale

enum NLFont {
    /// 28 / 600 / 1.15 / -0.28px — empty-state and welcome hero titles.
    static var display: Font { .system(size: 28, weight: .semibold) }
    /// 24 / 600 — settings pane title (.pane-title).
    static var paneTitle: Font { .system(size: 24, weight: .semibold) }
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

/// Only three shadows exist. Controls and cards are always flat.
enum NLShadow {
    /// Window: 0 24px 48px rgba(0,0,0,.18) + 0 0 0 1px rgba(0,0,0,.08)
    static let window = (color: Color.black.opacity(0.18), radius: 24.0, y: 24.0)
    static let windowDark = (color: Color.black.opacity(0.45), radius: 24.0, y: 24.0)
    /// Popover: 0 8px 24px rgba(0,0,0,.12) + 0 0 0 1px rgba(0,0,0,.06)
    static let popover = (color: Color.black.opacity(0.12), radius: 12.0, y: 8.0)
    static let popoverDark = (color: Color.black.opacity(0.40), radius: 12.0, y: 8.0)
    /// Hero art (illustrations only): rgba(0,0,0,.22) 3px 5px 30px
    static let hero = (color: Color.black.opacity(0.22), radius: 15.0, y: 5.0)
}

enum NLMotion {
    static let press: Double = 0.10
    static let hover: Double = 0.10
    static let popover: Double = 0.18
    /// Switch knob travel.
    static let toggle: Double = 0.18
}

// MARK: - Dividers

struct NLDivider: View {
    var body: some View {
        Rectangle()
            .fill(NLColor.borderDivider)
            .frame(height: 1)
    }
}

/// Row divider: inset 16pt, aligned with the row label.
struct NLRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(NLColor.borderDivider)
            .frame(height: 1)
            .padding(.leading, NLSpace.rowPadding)
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

// MARK: - Settings group (--card-bg + radius-card, clipped; no stroke, no shadow)

struct NLSection<Content: View>: View {
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
            .background(NLColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: NLRadius.card, style: .continuous))

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

// MARK: - Settings row (44pt tall, 16pt padding, label left / control right, 1px divider)

struct NLRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let badge: String?
    private let swatch: Color?
    private let showsDivider: Bool
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        swatch: Color? = nil,
        showsDivider: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
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

                Spacer(minLength: NLSpace.s3)

                trailing
            }
            .padding(.horizontal, NLSpace.rowPadding)
            .frame(minHeight: NLSpace.rowHeight)

            if showsDivider { NLRowDivider() }
        }
    }
}

extension NLRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        swatch: Color? = nil,
        showsDivider: Bool = false
    ) {
        self.init(
            title: title, subtitle: subtitle, badge: badge, swatch: swatch,
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
                Text(LocalizedStringKey(currentLabel))
                    .font(NLFont.body)
                    .foregroundStyle(isEnabled ? NLColor.textPrimary : NLColor.textTertiary)
                    .lineLimit(1)
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
            NLSelectList(options: options, selection: $selection) { isPresented = false }
        }
    }
}

/// The expanded option list (220pt wide, 24pt rows, radius 6, solid accent with white text on hover).
private struct NLSelectList<Value: Hashable>: View {
    let options: [NLSelectOption<Value>]
    @Binding var selection: Value
    let dismiss: () -> Void

    var body: some View {
        NLMenu {
            ForEach(options) { option in
                NLMenuItem(
                    title: option.label,
                    isSelected: option.value == selection
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

                Text(LocalizedStringKey(title))
                    .font(NLFont.body)
                    .foregroundStyle(labelColor)

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

struct NLPageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpace.s1) {
            Text(LocalizedStringKey(title))
                .font(NLFont.paneTitle)
                .foregroundStyle(NLColor.textPrimary)
            if let subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(NLFont.caption)
                    .foregroundStyle(NLColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NLPage<Content: View>: View {
    let title: String
    var subtitle: String?
    private let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NLSpace.group) {
                NLPageHeader(title: title, subtitle: subtitle)
                    .padding(.bottom, NLSpace.s1)

                content
            }
            .padding(.horizontal, NLSpace.page)
            .padding(.top, NLSpace.group)
            .padding(.bottom, NLSpace.s8)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NLColor.contentBg)
    }
}

// MARK: - Sidebar (232pt, material background, 1px divider on the right, search + account + nav)

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
        .background(NLColor.material)
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
                .shadow(
                    color: NLShadow.hero.color, radius: NLShadow.hero.radius, y: NLShadow.hero.y)
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
