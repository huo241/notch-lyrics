//
//  SettingsView.swift
//  Notch Lyrics
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @State private var selectedTab = "General"
    @State private var sidebarSearch = ""
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    /// Sidebar entry for one of the notch panels.
    ///
    /// The name and glyph come from `NotchViews`, which is also what the tab bar
    /// and the Tabs list read. They used to be two independent lists, which is
    /// how this panel ended up called "Media" in the sidebar and "Music" in the
    /// tab bar, with a different icon in each.
    private static func panelItem(_ id: String, _ view: NotchViews) -> NLSidebarItem {
        NLSidebarItem(id: id, label: view.panelName, icon: view.panelIcon)
    }

    /// Sidebar metrics (28pt rows, radius 6, 13pt labels, 16pt icons).
    private static let sidebarGroups: [NLSidebarGroup] = [
        NLSidebarGroup(
            id: "main",
            title: nil,
            items: [
                NLSidebarItem(id: "General", label: L("General"), icon: "gear"),
                NLSidebarItem(id: "Appearance", label: L("Appearance"), icon: "eye"),
            ]
        ),
        NLSidebarGroup(
            id: "features",
            title: L("Features"),
            items: [
                panelItem("Media", .home),
                NLSidebarItem(id: "Calendar", label: L("Calendar"), icon: "calendar"),
                NLSidebarItem(id: "HUD", label: "HUD", icon: "dial.medium.fill"),
                NLSidebarItem(id: "Battery", label: L("Battery"), icon: "battery.100.bolt"),
                panelItem("Shelf", .shelf),
                panelItem("QuickNote", .quickNote),
                panelItem("Weather", .weather),
                panelItem("Stats", .stats),
                NLSidebarItem(id: "Shortcuts", label: L("Shortcuts"), icon: "keyboard"),
            ]
        ),
        NLSidebarGroup(
            id: "system",
            title: nil,
            items: [
                NLSidebarItem(id: "Advanced", label: L("Advanced"), icon: "gearshape.2"),
                NLSidebarItem(id: "About", label: L("About"), icon: "info.circle"),
            ]
        ),
    ]

    var body: some View {
        HStack(spacing: 0) {
            NLSidebar(
                selection: $selectedTab,
                groups: Self.sidebarGroups,
                searchText: $sidebarSearch,
                brandIcon: NSApp.applicationIconImage,
                brandTitle: "Notch Lyrics",
                brandSubtitle: String(localized: "Version \(Bundle.main.releaseVersionNumber ?? "—")")
            )
            detailPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NLColor.contentBg)
        .tint(NLColor.accent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        Group {
            switch selectedTab {
            case "General":
                GeneralSettings()
            case "Appearance":
                Appearance()
            case "Media":
                Media()
            case "Calendar":
                CalendarSettings()
            case "HUD":
                HUD()
            case "Battery":
                Charge()
            case "Shelf":
                Shelf()
            case "QuickNote":
                QuickNoteSettings()
            case "Weather":
                WeatherSettings()
            case "Stats":
                StatsSettings()
            case "Shortcuts":
                Shortcuts()
            case "Advanced":
                Advanced()
            case "About":
                if let controller = updaterController {
                    About(updaterController: controller)
                } else {
                    // Fallback with a default controller
                    About(
                        updaterController: SPUStandardUpdaterController(
                            startingUpdater: false, updaterDelegate: nil,
                            userDriverDelegate: nil))
                }
            default:
                GeneralSettings()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    /// Selected language (`nil` = Follow System). A change needs a restart.
    @State private var language = AppLanguage.override
    @State private var askToRestartForLanguage = false

    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject var coordinator = NotchViewCoordinator.shared

    @Default(.showEmojis) var showEmojis
    @Default(.hiddenTabs) private var hiddenTabs: [String]
    @Default(.menubarIcon) private var menubarIcon
    @Default(.showOnAllDisplays) private var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) private var automaticallySwitchDisplay
    @Default(.notchHeightMode) private var notchHeightMode
    @Default(.notchHeight) private var notchHeight
    @Default(.nonNotchHeightMode) private var nonNotchHeightMode
    @Default(.nonNotchHeight) private var nonNotchHeight
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.enableHaptics) private var enableHaptics
    @Default(.minimumHoverDuration) private var minimumHoverDuration
    @Default(.enableGestures) private var enableGestures
    @Default(.closeGestureEnabled) private var closeGestureEnabled
    @Default(.swipeScalesNotch) private var swipeScalesNotch
    @Default(.gestureSensitivity) private var gestureSensitivity

    /// `LaunchAtLogin` exposes nothing observable, so hold the state here and write it back.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: {
                launchAtLogin = $0
                LaunchAtLogin.isEnabled = $0
            }
        )
    }

    private var displayOptions: [NLSelectOption<String?>] {
        [NLSelectOption(value: String?.none, label: L("Automatic"))]
            + screens.map { NLSelectOption(value: String?.some($0.uuid), label: $0.name) }
    }

    /// Language names are endonyms, each written in its own language, so they
    /// skip `L()`: `NLSelect` falls back to the raw label on a catalog miss,
    /// which is exactly what we want here.
    private var languageOptions: [NLSelectOption<String?>] {
        AppLanguage.options.map { NLSelectOption(value: $0.code, label: $0.label) }
    }

    private static let notchHeightOptions: [NLSelectOption<WindowHeightMode>] = [
        NLSelectOption(value: .matchRealNotchSize, label: L("Match real notch height")),
        NLSelectOption(value: .matchMenuBar, label: L("Match menubar height")),
        NLSelectOption(value: .custom, label: L("Custom height")),
    ]

    private static let nonNotchHeightOptions: [NLSelectOption<WindowHeightMode>] = [
        NLSelectOption(value: .matchMenuBar, label: L("Match menubar height")),
        NLSelectOption(value: .matchRealNotchSize, label: L("Match real notch height")),
        NLSelectOption(value: .custom, label: L("Custom height")),
    ]

    /// Only the panels that are switched on: offering a hidden panel as the home
    /// page would name a destination the notch cannot reach.
    private var homePageOptions: [NLSelectOption<NotchViews>] {
        NotchViews.allCases
            .filter { !hiddenTabs.contains($0.rawValue) }
            .map { NLSelectOption(value: $0, label: $0.panelName) }
    }

    private var gestureSensitivityLabel: String {
        if gestureSensitivity <= 150 { return L("High") }
        if gestureSensitivity <= 250 { return L("Medium") }
        return L("Low")
    }

    var body: some View {
        NLPage(
            L("General"),
            subtitle: L("Appearance, display, hover and gestures."),
            icon: "gear"
        ) {
            languageSection
            systemSection
            notchSizeSection
            behaviourSection
            gestureSection
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        NLSection(
            L("Language"),
            footer: L("Restarts Notch Lyrics.")
        ) {
            NLRow(icon: "globe", title: L("Language")) {
                NLSelect(
                    options: languageOptions,
                    selection: $language,
                    minWidth: 170
                )
            }
            .onChange(of: language) {
                // Only write the preference on a real change, so re-picking the same row does not offer a restart.
                guard language != AppLanguage.override else { return }
                AppLanguage.apply(language)
                askToRestartForLanguage = true
            }
            .alert(
                L("Restart to apply the new language?"),
                isPresented: $askToRestartForLanguage
            ) {
                Button(L("Restart Now")) { ApplicationRelauncher.restart() }
                Button(L("Later"), role: .cancel) {}
            } message: {
                Text(L("The new language applies after a restart."))
            }
        }
    }

    // MARK: - System

    private var systemSection: some View {
        NLSection(L("System")) {
            NLRow(icon: "menubar.rectangle", title: L("Show menu bar icon"), showsDivider: true) {
                NLSwitch(isOn: $menubarIcon, accessibilityLabel: L("Show menu bar icon"))
            }

            NLRow(icon: "power", title: L("Launch at login"), showsDivider: true) {
                NLSwitch(isOn: launchAtLoginBinding, accessibilityLabel: L("Launch at login"))
            }

            NLRow(icon: "display.2", title: L("Show on all displays"), showsDivider: true) {
                NLSwitch(isOn: $showOnAllDisplays, accessibilityLabel: L("Show on all displays"))
            }
            .onChange(of: showOnAllDisplays) {
                NotificationCenter.default.post(
                    name: Notification.Name.showOnAllDisplaysChanged, object: nil)
            }

            NLRow(icon: "display", title: L("Preferred display"), showsDivider: true) {
                NLSelect(
                    options: displayOptions,
                    selection: $coordinator.preferredScreenUUID,
                    minWidth: 160
                )
            }
            .disabled(showOnAllDisplays)

            NLRow(icon: "arrow.left.arrow.right", title: L("Automatically switch displays"), subtitle: L("Follows the pointer.")) {
                NLSwitch(isOn: $automaticallySwitchDisplay, accessibilityLabel: L("Automatically switch displays"))
            }
            .disabled(showOnAllDisplays)
            .onChange(of: automaticallySwitchDisplay) {
                NotificationCenter.default.post(
                    name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
            }
        }
        .onChange(of: NSScreen.screens) {
            screens = NSScreen.screens.compactMap { screen in
                guard let uuid = screen.displayUUID else { return nil }
                return (uuid, screen.localizedName)
            }
        }
    }

    // MARK: - Notch size

    private var notchSizeSection: some View {
        NLSection(
            L("Notch sizing"),
            footer: L("The two match options follow the system. Custom is only for exact alignment.")
        ) {
            NLRow(icon: "menubar.rectangle", title: L("Height on notch displays"), showsDivider: true) {
                NLSelect(
                    options: Self.notchHeightOptions,
                    selection: $notchHeightMode,
                    minWidth: 160
                )
            }
            .onChange(of: notchHeightMode) {
                switch notchHeightMode {
                case .matchRealNotchSize: notchHeight = 38
                case .matchMenuBar: notchHeight = 44
                case .custom: notchHeight = 38
                }
                NotificationCenter.default.post(
                    name: Notification.Name.notchHeightChanged, object: nil)
            }

            if notchHeightMode == .custom {
                NLRow(icon: "arrow.up.and.down", title: L("Custom height"), showsDivider: true) {
                    sliderRow($notchHeight.asDouble, range: 15...45, unit: "px")
                }
                .onChange(of: notchHeight) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }

            NLRow(icon: "display", title: L("Height on other displays"), showsDivider: nonNotchHeightMode == .custom) {
                NLSelect(
                    options: Self.nonNotchHeightOptions,
                    selection: $nonNotchHeightMode,
                    minWidth: 160
                )
            }
            .onChange(of: nonNotchHeightMode) {
                switch nonNotchHeightMode {
                case .matchMenuBar: nonNotchHeight = 24
                case .matchRealNotchSize: nonNotchHeight = 32
                case .custom: nonNotchHeight = 32
                }
                NotificationCenter.default.post(
                    name: Notification.Name.notchHeightChanged, object: nil)
            }

            if nonNotchHeightMode == .custom {
                NLRow(icon: "arrow.up.and.down", title: L("Custom height")) {
                    sliderRow($nonNotchHeight.asDouble, range: 0...40, unit: "px")
                }
                .onChange(of: nonNotchHeight) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        }
    }

    // MARK: - Notch behaviour

    private var behaviourSection: some View {
        NLSection(L("Notch behavior")) {
            NLRow(icon: "cursorarrow.rays", title: L("Open notch on hover"), showsDivider: true) {
                NLSwitch(isOn: $openNotchOnHover, accessibilityLabel: L("Open notch on hover"))
            }

            NLRow(icon: "hand.tap", title: L("Haptic feedback"), showsDivider: true) {
                NLSwitch(isOn: $enableHaptics, accessibilityLabel: L("Haptic feedback"))
            }

            NLRow(icon: "clock.arrow.circlepath", title: L("Remember last tab"), showsDivider: true) {
                NLSwitch(
                    isOn: $coordinator.openLastTabByDefault, accessibilityLabel: L("Remember last tab"))
            }

            NLRow(icon: "house", title: L("Home page"),
                subtitle: L("The tab the notch opens to."),
                showsDivider: openNotchOnHover
            ) {
                NLSelect(
                    options: homePageOptions,
                    selection: $coordinator.defaultHomeView,
                    minWidth: 150
                )
            }
            .disabled(coordinator.openLastTabByDefault)

            if openNotchOnHover {
                NLRow(icon: "timer", title: L("Hover delay")) {
                    sliderRow($minimumHoverDuration, range: 0...1, step: 0.1, unit: L("seconds"))
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        }
    }

    // MARK: - Gestures

    private var gestureSection: some View {
        NLSection(
            L("Gesture control"),
            footer: L("With hover off: swipe up on the notch to close it, swipe down to open it.")
        ) {
            NLRow(icon: "hand.draw", title: L("Enable gestures"), showsDivider: enableGestures) {
                NLSwitch(isOn: $enableGestures, accessibilityLabel: L("Enable gestures"))
            }
            .disabled(!openNotchOnHover)

            if enableGestures {
                NLRow(icon: "hand.point.up.left", title: L("Close gesture"), showsDivider: true) {
                    NLSwitch(isOn: $closeGestureEnabled, accessibilityLabel: L("Close gesture"))
                }

                NLRow(icon: "arrow.up.left.and.arrow.down.right", title: L("Scale the notch while swiping"), showsDivider: true) {
                    NLSwitch(isOn: $swipeScalesNotch, accessibilityLabel: L("Scale the notch while swiping"))
                }

                NLRow(icon: "dial.medium", title: L("Gesture sensitivity")) {
                    sliderRow(
                        $gestureSensitivity.asDouble, range: 100...300, step: 100,
                        overrideText: gestureSensitivityLabel)
                }
            }
        }
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover { enableGestures = true }
        }
    }

    // MARK: - Widgets

    private func sliderRow(
        _ value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        unit: String = "",
        overrideText: String? = nil
    ) -> some View {
        HStack(spacing: NLSpace.s3) {
            Text(overrideText ?? Self.readout(value.wrappedValue, step: step, unit: unit))
                .font(NLFont.mono)
                .foregroundStyle(NLColor.textSecondary)
                .frame(minWidth: 40, alignment: .trailing)
            NLSlider(value: value, range: range, step: step, width: 150)
        }
    }

    private static func readout(_ value: Double, step: Double, unit: String) -> String {
        let number = step < 1 ? String(format: "%.1f", value) : String(format: "%.0f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

struct Charge: View {
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    @Default(.showPowerStatusNotifications) private var showPowerStatusNotifications
    @Default(.showBatteryPercentage) private var showBatteryPercentage
    @Default(.showPowerStatusIcons) private var showPowerStatusIcons

    var body: some View {
        NLPage(L("Battery"), subtitle: L("The battery indicator and power alerts."), icon: "battery.100.bolt") {
            NLSection(L("General")) {
                NLRow(icon: "battery.100", title: L("Show battery indicator"), showsDivider: true) {
                    NLSwitch(isOn: $showBatteryIndicator, accessibilityLabel: L("Show battery indicator"))
                }
                NLRow(icon: "bell", title: L("Show power status notifications")) {
                    NLSwitch(
                        isOn: $showPowerStatusNotifications, accessibilityLabel: L("Show power status notifications"))
                }
            }

            NLSection(L("Display")) {
                NLRow(icon: "percent", title: L("Show battery percentage"), showsDivider: true) {
                    NLSwitch(isOn: $showBatteryPercentage, accessibilityLabel: L("Show battery percentage"))
                }
                NLRow(icon: "bolt", title: L("Show power status icons")) {
                    NLSwitch(isOn: $showPowerStatusIcons, accessibilityLabel: L("Show power status icons"))
                }
            }
        }
        .onAppear {
            Task { @MainActor in
                await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
    }
}

struct HUD: View {
    @EnvironmentObject var vm: NotchViewModel
    @Default(.inlineHUD) private var inlineHUD
    @Default(.enableGradient) private var enableGradient
    @Default(.optionKeyAction) private var optionKeyAction
    @Default(.hudReplacement) private var hudReplacement
    @Default(.systemEventIndicatorShadow) private var systemEventIndicatorShadow
    @Default(.systemEventIndicatorUseAccent) private var systemEventIndicatorUseAccent
    @Default(.showOpenNotchHUD) private var showOpenNotchHUD
    @Default(.showOpenNotchHUDPercentage) private var showOpenNotchHUDPercentage
    @Default(.showClosedNotchHUDPercentage) private var showClosedNotchHUDPercentage
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @State private var accessibilityAuthorized = false

    private static let optionKeyOptions: [NLSelectOption<OptionKeyAction>] =
        OptionKeyAction.allCases.map { NLSelectOption(value: $0, label: $0.displayName) }

    var body: some View {
        NLPage(
            "HUD",
            subtitle: L("Volume, brightness and backlight overlays, in the notch."),
            icon: "dial.medium.fill"
        ) {
            replacementSection
            generalSection
            openNotchSection
            closedNotchSection
        }
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)
        ) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
            }
        }
    }

    // MARK: - System HUD replacement

    private var replacementSection: some View {
        NLSection(L("System HUD")) {
            NLRow(icon: "slider.horizontal.3", title: L("Replace system HUD"),
                subtitle: L("Replaces the macOS volume, brightness and backlight overlay."),
                showsDivider: !accessibilityAuthorized
            ) {
                NLSwitch(isOn: $hudReplacement, accessibilityLabel: L("Replace system HUD"))
            }
            .disabled(!accessibilityAuthorized)

            if !accessibilityAuthorized {
                HStack(alignment: .top, spacing: NLSpace.s3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(NLColor.destructive)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: NLSpace.s2) {
                        Text(L("Accessibility permission required"))
                            .font(NLFont.bodyStrong)
                            .foregroundStyle(NLColor.textPrimary)
                        Text(L("Needs Accessibility permission. Grant it, then turn this on."))
                            .font(NLFont.caption)
                            .foregroundStyle(NLColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L("Grant permission")) {
                            XPCHelperClient.shared.requestAccessibilityAuthorization()
                        }
                        .buttonStyle(NLButtonStyle(variant: .secondary))
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, NLSpace.s4)
                .padding(.vertical, NLSpace.s3)
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        NLSection(L("General")) {
            NLRow(icon: "option", title: L("Option key behavior"), showsDivider: true) {
                NLSelect(options: Self.optionKeyOptions, selection: $optionKeyAction, minWidth: 140)
            }

            NLRow(icon: "chart.bar", title: L("Progress bar style"), showsDivider: true) {
                NLSegmented(
                    options: [
                        NLSegmentedOption(value: false, label: L("Hierarchical")),
                        NLSegmentedOption(value: true, label: L("Gradient")),
                    ],
                    selection: $enableGradient
                )
            }

            NLRow(icon: "sparkles", title: L("Glow effect"), showsDivider: true) {
                NLSwitch(isOn: $systemEventIndicatorShadow, accessibilityLabel: L("Glow effect"))
            }

            NLRow(icon: "paintpalette", title: L("Accent-colored progress bar")) {
                NLSwitch(isOn: $systemEventIndicatorUseAccent, accessibilityLabel: L("Accent-colored progress bar"))
            }
        }
        .disabled(!hudReplacement)
    }

    // MARK: - Open notch

    private var openNotchSection: some View {
        NLSection(L("Open Notch")) {
            NLRow(icon: "rectangle.expand.vertical", title: L("Show HUD in open notch"), showsDivider: true) {
                NLSwitch(isOn: $showOpenNotchHUD, accessibilityLabel: L("Show HUD in open notch"))
            }
            NLRow(icon: "percent", title: L("Show percentage")) {
                NLSwitch(isOn: $showOpenNotchHUDPercentage, accessibilityLabel: L("Show percentage"))
            }
            .disabled(!showOpenNotchHUD)
        }
        .disabled(!hudReplacement)
    }

    // MARK: - Closed notch

    private var closedNotchSection: some View {
        NLSection(L("Closed Notch")) {
            NLRow(icon: "square.on.square", title: L("HUD style"), showsDivider: true) {
                NLSegmented(
                    options: [
                        NLSegmentedOption(value: false, label: L("Default")),
                        NLSegmentedOption(value: true, label: L("Inline")),
                    ],
                    selection: $inlineHUD
                )
            }
            .onChange(of: inlineHUD) {
                if inlineHUD {
                    withAnimation {
                        Defaults[.systemEventIndicatorShadow] = false
                        Defaults[.enableGradient] = false
                    }
                }
            }

            NLRow(icon: "percent", title: L("Show percentage")) {
                NLSwitch(isOn: $showClosedNotchHUDPercentage, accessibilityLabel: L("Show percentage"))
            }
        }
        .disabled(!hudReplacement)
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles

    @Default(.enableLyrics) var enableLyrics
    @Default(.lyricsEndpoint) var lyricsEndpoint
    @Default(.lyricsProxy) var lyricsProxy
    @Default(.keepMusicOpen) var keepMusicOpen
    @Default(.pinnedPlayerBundle) var pinnedPlayerBundle

    /// Observed so the pin row can name the app being followed and enable the
    /// switch only once a real track has been seen.
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        NLPage(
            NotchViews.home.panelName,
            subtitle: L("The player in the notch: what it shows and when it appears."),
            icon: NotchViews.home.panelIcon
        ) {
            mediaSourceSection

            NLSection(L("Playback")) {
                NLRow(icon: "play.rectangle", title: L("Show what's playing"), showsDivider: true) {
                    NLSwitch(
                        isOn: $coordinator.musicLiveActivityEnabled.animation(),
                        accessibilityLabel: L("Show what's playing"))
                }

                NLRow(icon: "eye", title: L("Show sneak peek on playback changes"), showsDivider: true) {
                    NLSwitch(isOn: $enableSneakPeek, accessibilityLabel: L("Show sneak peek on playback changes"))
                }

                NLRow(icon: "square.on.square", title: L("Sneak peek style"), showsDivider: true) {
                    NLSelect(
                        options: SneakPeekStyle.allCases.map {
                            NLSelectOption(value: $0, label: $0.displayName)
                        },
                        selection: $sneakPeekStyles,
                        minWidth: 120
                    )
                }

                NLRow(icon: "clock", title: L("Hide after inactivity"), showsDivider: true) {
                    HStack(spacing: NLSpace.s2) {
                        Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                            .font(NLFont.mono)
                            .foregroundStyle(NLColor.textSecondary)
                        Stepper(
                            "",
                            value: $waitInterval,
                            in: 0...10,
                            step: 1
                        )
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }

                NLRow(icon: "arrow.up.left.and.arrow.down.right", title: L("In full screen")) {
                    NLSelect(
                        options: [
                            NLSelectOption(value: HideNotchOption.always, label: L("Hide for all apps")),
                            NLSelectOption(
                                value: HideNotchOption.nowPlayingOnly, label: L("Hide for the media app")),
                            NLSelectOption(value: HideNotchOption.never, label: L("Never hide")),
                        ],
                        selection: $hideNotchOption,
                        minWidth: 140
                    )
                }
            }

            NLSection(
                L("Controls"),
                footer: L("Which controls appear in the player.")
            ) {
                MusicSlotConfigurationView()
                NLDivider()
                NLRow(icon: "text.quote", title: L("Show lyrics")) {
                    NLSwitch(isOn: $enableLyrics, accessibilityLabel: L("Show lyrics"))
                }

                NLRow(icon: "pin", title: L("Keep lyrics visible"), showsDivider: true) {
                    NLSwitch(
                        isOn: $keepMusicOpen,
                        accessibilityLabel: L("Keep lyrics visible"))
                }
            }

            if enableLyrics {
                lyricsServiceSection
            }
        }
    }

    /// 歌词服务地址与代理。
    ///
    /// 默认值（官方域名 + 系统代理）对大多数人就是对的，所以这一节只在歌词打开时才
    /// 出现。官方域名不可达时可以指到一个能用的镜像；代理则留给「系统没配、但自己
    /// 知道该走哪里」的情况——系统代理默认就会生效，不需要在这里再填一遍。
    private var lyricsServiceSection: some View {
        NLSection(
            L("Lyrics service"),
            footer: L("Empty uses lrclib.net. Use a mirror if it does not respond. Proxy is host:port; empty follows the system.")
        ) {
            NLRow(icon: "network", title: L("Server address"), showsDivider: true) {
                NLTextField(
                    placeholder: LyricsNetwork.official.absoluteString,
                    text: $lyricsEndpoint,
                    width: 220
                )
            }
            NLRow(icon: "arrow.triangle.branch", title: L("Proxy")) {
                NLTextField(
                    placeholder: L("System proxy"),
                    text: $lyricsProxy,
                    width: 220
                )
            }
        }
    }

    private var mediaSourceSection: some View {
        NLSection(L("Playback source")) {
            NLRow(icon: "music.note", title: L("Music source")) {
                NLSelect(
                    options: availableMediaControllers.map {
                        NLSelectOption(value: $0, label: $0.displayName)
                    },
                    selection: $mediaController,
                    minWidth: 140,
                    // Product names render verbatim in every language.
                    localizesLabel: false
                )
                .onChange(of: mediaController) { _, newValue in
                    // The pin only describes a "Now Playing" session. Leaving
                    // that mode would otherwise hide a lock that is still in
                    // force the next time the user comes back to it.
                    if newValue != .nowPlaying {
                        pinnedPlayerBundle = ""
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            }
            if mediaController == .nowPlaying, !MusicManager.shared.isNowPlayingDeprecated {
                NLDivider()
                NLRow(icon: "pin", title: L("Pin to one app"), subtitle: pinSubtitle) {
                    NLSwitch(isOn: pinBinding, accessibilityLabel: L("Pin to one app"))
                }
                NLDivider()
                NLFootnote(pinHint)
            }
            if mediaController == .neteaseCloudMusic {
                NLDivider()
                NLFootnote(L("Tracks the NetEase Cloud Music app only. Lyrics are looked up on NetEase first."))
            }
            if MusicManager.shared.isNowPlayingDeprecated {
                NLDivider()
                NLFootnote(
                    L("YouTube Music requires this third-party app to be installed:"),
                    link: (
                        "pear-desktop",
                        URL(string: "https://github.com/pear-devs/pear-desktop")!
                    )
                )
            } else if mediaController == .nowPlaying {
                NLDivider()
                NLFootnote(L("Works with every media app."))
            }
        }
    }

    // MARK: - Pin to a single app

    /// Whether a pin is in force. The switch reflects the stored bundle id
    /// rather than a separate boolean, so the two can never disagree.
    private var pinBinding: Binding<Bool> {
        Binding(
            get: { !pinnedPlayerBundle.isEmpty },
            set: { isOn in
                guard isOn else {
                    pinnedPlayerBundle = ""
                    return
                }
                // Nothing has been resolved yet (cold launch, or the placeholder
                // track): pinning now would latch onto the fallback bundle id
                // and quietly follow an app the user is not even using.
                guard musicManager.hasResolvedTrack,
                      let bundle = musicManager.bundleIdentifier,
                      !bundle.isEmpty
                else { return }
                pinnedPlayerBundle = bundle
            }
        )
    }

    private var pinSubtitle: String? {
        guard !pinnedPlayerBundle.isEmpty else { return nil }
        return String(
            format: L("Only %@ is tracked"),
            appDisplayName(for: pinnedPlayerBundle))
    }

    /// Explanation shown under the toggle: how to pin, and what is currently
    /// locked once a pin is in force. Only rendered in the Now Playing branch,
    /// so no optional needed here.
    private var pinHint: String {
        if pinnedPlayerBundle.isEmpty {
            return L("Turn this on while the app you want is playing. Only that app is tracked afterwards.")
        }
        return String(
            format: L("Locked to %@. Playback in other apps no longer replaces what the notch shows."),
            appDisplayName(for: pinnedPlayerBundle))
    }

    /// Human name for a bundle id. Known music apps use their English product
    /// names so the wording matches the Music source picker; anything else
    /// falls back to Launch Services (which localizes, e.g. 音乐 for Music).
    private func appDisplayName(for bundle: String) -> String {
        switch bundle {
        case "com.apple.Music": return "Apple Music"
        case "com.spotify.client": return "Spotify"
        case NeteaseMusicClient.bundleIdentifier: return "NetEase Cloud Music"
        default: break
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return bundle
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    // Only show controller options that are available on this macOS version.
    // The NetEase source rides on the same MediaRemote pipeline as "Now
    // Playing", so both go away together when that pipeline is deprecated.
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying && $0 != .neteaseCloudMusic }
        } else {
            return MediaControllerType.allCases
        }
    }
}

// MARK: - Display names for the media page (rawValue stays untouched)
//
// Music app names are intentionally NOT localized: they are product names and
// should read the same in every language (Now Playing, Apple Music, Spotify…),
// matching how the apps brand themselves.

private extension MediaControllerType {
    var displayName: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .youtubeMusic: return "YouTube Music"
        case .neteaseCloudMusic: return "NetEase Cloud Music"
        }
    }
}

private extension SneakPeekStyle {
    var displayName: String {
        switch self {
        case .standard: return L("Default")
        case .inline: return L("Inline")
        }
    }
}


/// Quick note settings: pick the default Notes folder.
///
/// The quick note panel in the notch has its own change entry point; this one is
/// a fixed home for the same choice that does not require opening the notch. The
/// folder list comes from NotesService and needs Automation → Notes access.
struct QuickNoteSettings: View {
    @Default(.quickNoteFolderID) private var folderID
    @Default(.quickNoteFolderLabel) private var folderLabel
    @Default(.quickNoteTarget) private var targetRaw
    @Default(.quickNoteVaultLabel) private var vaultLabel

    @State private var folders: [NoteFolder] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    private var target: QuickNoteTarget {
        QuickNoteTarget(rawValue: targetRaw) ?? .notes
    }

    /// Same two destinations the note panel offers, surfaced here so the
    /// choice can be made without opening the notch. Switching never clears
    /// the other route's configuration, so going back and forth is free.
    private var targetSelection: Binding<String> {
        Binding(
            get: { targetRaw },
            set: { newValue in
                guard newValue != targetRaw else { return }
                targetRaw = newValue
                // The Notes list is only fetched for the Notes route: asking
                // for it means an Apple Events round-trip to Notes, and there
                // is no reason to spend that while Obsidian is the target.
                if (QuickNoteTarget(rawValue: newValue) ?? .notes) == .notes {
                    Task { await loadFolders() }
                }
            }
        )
    }

    private var folderSelection: Binding<String> {
        Binding(
            get: { folderID },
            set: { newValue in
                folderID = newValue
                folderLabel = folders.first { $0.id == newValue }?.displayName ?? ""
            }
        )
    }

    private var targetOptions: [NLSegmentedOption<String>] {
        QuickNoteTarget.allCases.map { NLSegmentedOption(value: $0.rawValue, label: $0.label) }
    }

    private var folderOptions: [NLSelectOption<String>] {
        var options = [NLSelectOption(value: "", label: L("Not selected"))]
        options += folders.map { NLSelectOption(value: $0.id, label: $0.displayName) }
        // The stored folder may have gone missing (deleted, or the list simply
        // failed to load) — keep it visible rather than rendering a blank row.
        if !folderID.isEmpty, !folders.contains(where: { $0.id == folderID }) {
            options.append(
                NLSelectOption(value: folderID, label: folderLabel.isEmpty ? folderID : folderLabel))
        }
        return options
    }

    var body: some View {
        NLPage(
            NotchViews.quickNote.panelName,
            subtitle: L("Where quick notes are saved."),
            icon: NotchViews.quickNote.panelIcon
        ) {
            NLSection(L("Storage")) {
                NLRow(icon: "tray.and.arrow.down", title: L("Save to")) {
                    NLSegmented(options: targetOptions, selection: targetSelection)
                }
            }

            if target == .notes {
                NLSection(L("Notes"), footer: L("Each save creates a new note; existing notes are never changed.")) {
                    NLRow(icon: "folder", title: L("Default folder"), showsDivider: true) {
                        NLSelect(options: folderOptions, selection: folderSelection, minWidth: 180)
                    }

                    NLRow(icon: "folder.badge.gearshape", title: L("Folders"),
                        subtitle: statusMessage
                            ?? (folders.isEmpty
                                ? L("No folders loaded yet.")
                                : String(localized: "\(folders.count) folders loaded."))
                    ) {
                        HStack(spacing: NLSpace.s3) {
                            if isLoading {
                                ProgressView().controlSize(.small)
                            }
                            Button(L("Refresh")) { Task { await loadFolders() } }
                                .buttonStyle(NLButtonStyle(variant: .secondary))
                        }
                    }
                }
            } else {
                NLSection("Obsidian", footer: L("Saved as a .md file, named after the first line.")) {
                    NLRow(icon: "folder", title: L("Folder"),
                        subtitle: vaultLabel.isEmpty ? L("Not selected") : vaultLabel
                    ) {
                        HStack(spacing: NLSpace.s3) {
                            Button(vaultLabel.isEmpty ? L("Choose Folder…") : L("Change Folder…")) {
                                chooseVault()
                            }
                            .buttonStyle(NLButtonStyle(variant: .secondary))

                            if !vaultLabel.isEmpty {
                                Button(L("Clear")) { ObsidianService.shared.forget() }
                                    .buttonStyle(NLButtonStyle(variant: .secondary))
                            }
                        }
                    }
                }
            }
        }
        // Without a title of its own the window keeps showing the *previous*
        // pane's title — SwiftUI only rewrites it when a navigationTitle exists.
        .task { if target == .notes { await loadFolders() } }
    }

    /// Opens the vault picker. The grant is stored as a security-scoped
    /// bookmark; writing a bare path would not survive a relaunch.
    private func chooseVault() {
        _ = ObsidianService.shared.chooseFolder()
    }

    private func loadFolders() async {
        isLoading = true
        statusMessage = nil
        do {
            folders = try await NotesService.shared.listFolders()
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) private var showCalendar: Bool
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @Default(.showFullEventTitles) private var showFullEventTitles

    var body: some View {
        NLPage(L("Calendar"), subtitle: L("Calendar and reminders in the notch."), icon: "calendar") {
            NLSection(L("Display")) {
                NLRow(icon: "calendar", title: L("Show calendar"), showsDivider: true) {
                    NLSwitch(isOn: $showCalendar, accessibilityLabel: L("Show calendar"))
                }
                NLRow(icon: "checkmark.circle", title: L("Hide completed reminders"), showsDivider: true) {
                    NLSwitch(isOn: $hideCompletedReminders, accessibilityLabel: L("Hide completed reminders"))
                }
                NLRow(icon: "calendar.badge.clock", title: L("Hide all-day events"), showsDivider: true) {
                    NLSwitch(isOn: $hideAllDayEvents, accessibilityLabel: L("Hide all-day events"))
                }
                NLRow(icon: "arrow.down.to.line", title: L("Auto-scroll to next event"), showsDivider: true) {
                    NLSwitch(isOn: $autoScrollToNextEvent, accessibilityLabel: L("Auto-scroll to next event"))
                }
                NLRow(icon: "text.alignleft", title: L("Always show full event titles")) {
                    NLSwitch(isOn: $showFullEventTitles, accessibilityLabel: L("Always show full event titles"))
                }
            }

            listSection(
                title: L("Calendar"),
                authorized: calendarManager.calendarAuthorizationStatus == .fullAccess,
                deniedMessage: L("Calendar access is denied. Turn it on in System Settings."),
                settingsURL:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
                items: calendarManager.eventCalendars,
                emptyMessage: L("No calendars in the Calendar app yet.")
            )

            listSection(
                title: L("Reminders"),
                authorized: calendarManager.reminderAuthorizationStatus == .fullAccess,
                deniedMessage: L("Reminders access is denied. Turn it on in System Settings."),
                settingsURL:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders",
                items: calendarManager.reminderLists,
                emptyMessage: L("No lists in the Reminders app yet.")
            )
        }
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }

    @ViewBuilder
    private func listSection(
        title: String,
        authorized: Bool,
        deniedMessage: String,
        settingsURL: String,
        items: [CalendarModel],
        emptyMessage: String
    ) -> some View {
        NLSection(title) {
            if !authorized {
                NLPermissionNotice(message: deniedMessage, settingsURL: settingsURL)
            } else if items.isEmpty {
                NLEmptyState(icon: "calendar.badge.exclamationmark", title: L("No content"), message: emptyMessage)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NLRow(
                        title: item.title,
                        swatch: lighterColor(from: item.color),
                        showsDivider: index < items.count - 1
                    ) {
                        NLSwitch(
                            isOn: Binding(
                                get: { calendarManager.getCalendarSelected(item) },
                                set: { isSelected in
                                    Task {
                                        await calendarManager.setCalendarSelected(
                                            item, isSelected: isSelected)
                                    }
                                }
                            ),
                            accessibilityLabel: item.title
                        )
                    }
                    .disabled(!showCalendar)
                }
            }
        }
    }
}

/// Inline notice for a denied permission (icon, summary, explanation, one secondary button).
struct NLPermissionNotice: View {
    let message: String
    let settingsURL: String

    var body: some View {
        HStack(alignment: .top, spacing: NLSpace.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(NLColor.destructive)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: NLSpace.s2) {
                Text(L("Permission not granted"))
                    .font(NLFont.bodyStrong)
                    .foregroundStyle(NLColor.textPrimary)
                Text(message)
                    .font(NLFont.caption)
                    .foregroundStyle(NLColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Open System Settings")) {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(NLButtonStyle(variant: .secondary))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, NLSpace.s4)
        .padding(.vertical, NLSpace.s3)
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0,0,0,0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow

    var body: some View {
        NLPage(L("About"), subtitle: L("Version, updates and source code."), icon: "info.circle") {
            NLSection(L("Version")) {
                NLRow(icon: "info.circle", title: L("Version"),
                    subtitle: showBuildNumber ? nil : L("Show build number")
                ) {
                    HStack(spacing: NLSpace.s2) {
                        if showBuildNumber {
                            Text(Bundle.main.buildVersionNumber ?? "—")
                                .font(NLFont.mono)
                                .foregroundStyle(NLColor.textTertiary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? L("Unknown"))
                            .font(NLFont.mono)
                            .foregroundStyle(NLColor.textSecondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { showBuildNumber.toggle() }
                    }
                }
            }

            UpdaterSettingsView(updater: updaterController.updater)

            NLSection(L("Project"), footer: L("Notch Lyrics is an independent GPL-3.0 project.")) {
                NLRow(icon: "chevron.left.forwardslash.chevron.right", title: L("Source code"), subtitle: "github.com/huo241/notch-lyrics") {
                    Button(L("Open GitHub")) {
                        if let url = URL(string: "https://github.com/huo241/notch-lyrics") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(NLButtonStyle(variant: .secondary))
                }
            }
        }
        .toolbar {
            CheckForUpdatesView(updater: updaterController.updater)
        }
    }
}

struct Shelf: View {
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) private var quickShareProvider
    @Default(.expandedDragDetection) private var expandedDragDetection: Bool
    @Default(.notchShelf) private var notchShelf
    @Default(.copyOnDrag) private var copyOnDrag
    @Default(.autoRemoveShelfItems) private var autoRemoveShelfItems
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    /// Display name for a share service. `id` is the persisted key — for system
    /// services it is the service's own title, which macOS localizes — so the
    /// swap happens only in the display layer, never in storage.
    private func displayProviderName(_ id: String) -> String {
        id == "System Share Menu" ? L("System share sheet") : id
    }

    init() {
        Task { await QuickShareService.shared.discoverAvailableProviders() }
    }

    var body: some View {
        NLPage(NotchViews.shelf.panelName, subtitle: L("A temporary file shelf, and sharing from it."), icon: NotchViews.shelf.panelIcon) {
            NLSection(L("General")) {
                NLRow(icon: "tray.full", title: L("Enable shelf"), showsDivider: true) {
                    NLSwitch(isOn: $notchShelf, accessibilityLabel: L("Enable shelf"))
                }
                NLRow(icon: "arrow.down.doc", title: L("Larger drop area for dragging"), showsDivider: true) {
                    NLSwitch(isOn: $expandedDragDetection, accessibilityLabel: L("Larger drop area for dragging"))
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                NLRow(icon: "doc.on.doc", title: L("Copy instead of move on drag"), showsDivider: true) {
                    NLSwitch(isOn: $copyOnDrag, accessibilityLabel: L("Copy instead of move on drag"))
                }
                NLRow(icon: "trash", title: L("Remove after dragging")) {
                    NLSwitch(isOn: $autoRemoveShelfItems, accessibilityLabel: L("Remove after dragging"))
                }
            }

            NLSection(
                L("Quick Share"),
                footer: L("Which service shares files from the shelf.")
            ) {
                NLRow(icon: "square.and.arrow.up", title: L("Service"), showsDivider: selectedProvider != nil) {
                    NLSelect(
                        options: quickShareService.availableProviders.map {
                            NLSelectOption(value: $0.id, label: displayProviderName($0.id))
                        },
                        selection: $quickShareProvider,
                        minWidth: 180
                    )
                }

                if let selectedProvider {
                    NLRow(icon: "checkmark.circle", title: L("Current selection"), subtitle: L("Files dropped on the shelf use this service.")) {
                        HStack(spacing: NLSpace.s2) {
                            providerIcon(selectedProvider)
                            Text(displayProviderName(selectedProvider.id))
                                .font(NLFont.body)
                                .foregroundStyle(NLColor.textSecondary)
                        }
                    }
                } else {
                    NLFootnote(L("No sharing services found yet."))
                }
            }
        }
    }

    @ViewBuilder
    private func providerIcon(_ provider: QuickShareProvider) -> some View {
        if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
            Image(nsImage: nsImg)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13))
                .foregroundStyle(NLColor.accent)
                .frame(width: 16, height: 16)
        }
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @Default(.sliderColor) private var sliderColor
    @Default(.settingsIconInNotch) private var settingsIconInNotch
    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.playerColorTinting) private var playerColorTinting
    @Default(.lightingEffect) private var lightingEffect
    @Default(.hiddenTabs) private var hiddenTabs: [String]

    var body: some View {
        NLPage(L("Appearance"), subtitle: L("Tabs and player tinting."), icon: "eye") {
            generalSection
            tabsSection
            mediaSection
        }
    }

    // MARK: - Tabs

    /// Which panels the notch offers.
    ///
    /// Switching one off takes it out of the tab bar and out of the home-page
    /// rotation. Nothing else happens to it: the feature, its settings and its
    /// data stay exactly where they were, so turning it back on restores what was
    /// there instead of starting over.
    private var tabsSection: some View {
        NLSection(L("Tabs"), footer: L("At least one tab always stays visible.")) {
            ForEach(NotchViews.allCases, id: \.self) { view in
                NLRow(
                    icon: view.panelIcon,
                    title: view.panelName,
                    showsDivider: view != NotchViews.allCases.last
                ) {
                    NLSwitch(isOn: visibility(for: view), accessibilityLabel: view.panelName)
                        .disabled(isLastVisible(view))
                }
            }
        }
    }

    /// Reads as "this panel is shown"; writes by adding or removing it from the
    /// hidden list. Hiding the panel that is currently the home page moves the
    /// home page to the first panel still visible, and a panel that disappears
    /// while it is on screen hands the screen to that same fallback.
    private func visibility(for view: NotchViews) -> Binding<Bool> {
        Binding(
            get: { !hiddenTabs.contains(view.rawValue) },
            set: { shown in
                var hidden = hiddenTabs
                if shown {
                    hidden.removeAll { $0 == view.rawValue }
                } else {
                    hidden.append(view.rawValue)
                }
                // Never let the bar empty out — there would be nothing to show.
                guard hidden.count < NotchViews.allCases.count else { return }
                hiddenTabs = hidden
                if hidden.contains(coordinator.defaultHomeView.rawValue) {
                    coordinator.defaultHomeView = coordinator.resolvedHomeView
                }
                coordinator.clampToVisiblePanels()
            }
        )
    }

    /// The switch that would empty the bar is the one that cannot be turned off.
    private func isLastVisible(_ view: NotchViews) -> Bool {
        !hiddenTabs.contains(view.rawValue)
            && hiddenTabs.count == NotchViews.allCases.count - 1
    }

    // MARK: - General

    private var generalSection: some View {
        NLSection(L("General")) {
            NLRow(icon: "menubar.rectangle", title: L("Always show tabs"), showsDivider: true) {
                NLSwitch(isOn: $coordinator.alwaysShowTabs, accessibilityLabel: L("Always show tabs"))
            }
            NLRow(icon: "gearshape", title: L("Show settings icon in notch")) {
                NLSwitch(isOn: $settingsIconInNotch, accessibilityLabel: L("Show settings icon in notch"))
            }
        }
    }

    // MARK: - Media

    private var mediaSection: some View {
        NLSection(L("Player")) {
            NLRow(icon: "waveform", title: L("Colored spectrogram"), showsDivider: true) {
                NLSwitch(isOn: $coloredSpectrogram, accessibilityLabel: L("Colored spectrogram"))
            }
            NLRow(icon: "eyedropper", title: L("Tint player with album art"), showsDivider: true) {
                NLSwitch(isOn: $playerColorTinting, accessibilityLabel: L("Tint player with album art"))
            }
            NLRow(icon: "sparkles", title: L("Enable blur effect behind album art"), showsDivider: true) {
                NLSwitch(isOn: $lightingEffect, accessibilityLabel: L("Enable blur effect behind album art"))
            }
            NLRow(icon: "paintpalette", title: L("Slider color")) {
                NLSelect(
                    options: SliderColorEnum.allCases.map {
                        NLSelectOption(value: $0, label: $0.displayName)
                    },
                    selection: $sliderColor,
                    minWidth: 140
                )
            }
        }
    }
}

struct Advanced: View {
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @Default(.showOnLockScreen) private var showOnLockScreen
    @Default(.hideFromScreenRecording) private var hideFromScreenRecording
    @Default(.cornerRadiusScaling) private var cornerRadiusScaling
    @Default(.hideTitleBar) private var hideTitleBar

    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor? = nil
    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"

    // macOS accent colors
    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"

        var id: String { self.rawValue }

        var displayName: String {
            switch self {
            case .blue: return L("Blue")
            case .purple: return L("Purple")
            case .pink: return L("Pink")
            case .red: return L("Red")
            case .orange: return L("Orange")
            case .yellow: return L("Yellow")
            case .green: return L("Green")
            case .graphite: return L("Graphite")
            }
        }

        var color: Color {
            switch self {
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
            }
        }
    }

    var body: some View {
        NLPage(L("Advanced"), subtitle: L("Accent color, window behavior and app icon."), icon: "gearshape.2") {
            accentSection
            windowAppearanceSection
            iconSection
            windowBehaviourSection
        }
        .onAppear {
            loadCustomColor()
        }
    }

    // MARK: - Accent color

    private var accentSection: some View {
        NLSection(L("Accent color"), footer: L("A custom color only affects this app's controls.")) {
            NLRow(icon: "paintpalette", title: L("Accent color"), showsDivider: true) {
                NLSegmented(
                    options: [
                        NLSegmentedOption(value: false, label: L("Use System")),
                        NLSegmentedOption(value: true, label: L("Custom")),
                    ],
                    selection: $useCustomAccentColor
                )
            }

            if useCustomAccentColor {
                VStack(alignment: .leading, spacing: NLSpace.s4) {
                    VStack(alignment: .leading, spacing: NLSpace.s2) {
                        Text(L("Presets"))
                            .font(NLFont.caption)
                            .foregroundStyle(NLColor.textSecondary)

                        HStack(spacing: NLSpace.s3) {
                            ForEach(PresetAccentColor.allCases) { preset in
                                AccentCircleButton(
                                    isSelected: selectedPresetColor == preset,
                                    color: preset.color,
                                    accessibilityLabel: preset.displayName
                                ) {
                                    selectedPresetColor = preset
                                    customAccentColor = preset.color
                                    saveCustomColor(preset.color)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    NLDivider()

                    HStack(spacing: NLSpace.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Custom color"))
                                .font(NLFont.body)
                                .foregroundStyle(NLColor.textPrimary)
                            Text(L("Pick any color."))
                                .font(NLFont.caption)
                                .foregroundStyle(NLColor.textSecondary)
                        }

                        Spacer(minLength: NLSpace.s3)

                        ColorPicker(
                            "",
                            selection: Binding(
                                get: { customAccentColor },
                                set: { newColor in
                                    customAccentColor = newColor
                                    selectedPresetColor = nil
                                    saveCustomColor(newColor)
                                }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                    }
                }
                .padding(.horizontal, NLSpace.s4)
                .padding(.vertical, NLSpace.s3)
            } else {
                NLRow(icon: "paintpalette", title: L("System accent color")) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(NLColor.borderHairline, lineWidth: 1))
                }
            }
        }
        .onAppear {
            initializeAccentColorState()
        }
    }

    // MARK: - Window appearance

    private var windowAppearanceSection: some View {
        NLSection(L("Window")) {
            NLRow(icon: "square.dashed", title: L("Scale corner radius")) {
                NLSwitch(isOn: $cornerRadiusScaling, accessibilityLabel: L("Scale corner radius"))
            }
        }
    }

    // MARK: - App icon

    private var iconSection: some View {
        NLSection(L("App icon")) {
            HStack {
                Spacer(minLength: 0)
                VStack(spacing: NLSpace.s3) {
                    ForEach(icons, id: \.self) { icon in
                        Image(icon)
                            .resizable()
                            .frame(width: 80, height: 80)
                            .onTapGesture {
                                withAnimation {
                                    selectedIcon = icon
                                }
                                NSApp.applicationIconImage = NSImage(named: icon)
                            }
                        NLBadge(text: L("Default"))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, NLSpace.s6)
            .disabled(true)
        }
    }

    // MARK: - Window behaviour

    private var windowBehaviourSection: some View {
        NLSection(L("Behavior")) {
            NLRow(icon: "rectangle", title: L("Hide title bar"), showsDivider: true) {
                NLSwitch(isOn: $hideTitleBar, accessibilityLabel: L("Hide title bar"))
            }
            NLRow(icon: "lock", title: L("Show notch on lock screen"), showsDivider: true) {
                NLSwitch(isOn: $showOnLockScreen, accessibilityLabel: L("Show notch on lock screen"))
            }
            NLRow(icon: "video.slash", title: L("Hide from screen recording")) {
                NLSwitch(isOn: $hideFromScreenRecording, accessibilityLabel: L("Hide from screen recording"))
            }
        }
    }

    // MARK: - Accent color storage

    private func forceUiUpdate() {
        // Force refresh the UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }

    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(
            withRootObject: nsColor, requiringSecureCoding: false)
        {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }

    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
            let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData)
        {
            customAccentColor = Color(nsColor: nsColor)

            // Check if loaded color matches a preset
            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }

    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)

        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01
            && abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01
            && abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }

    private func initializeAccentColorState() {
        if !useCustomAccentColor {
            selectedPresetColor = nil  // Multicolor is selected when useCustomAccentColor is false
        } else {
            loadCustomColor()
        }
    }
}

// MARK: - Accent Circle Button Component

/// Accent swatch button (accent ring when selected, border-strong on hover, no shadow).
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var accessibilityLabel: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(NLColor.borderHairline, lineWidth: 1))
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(NLColor.accent, lineWidth: 2)
                            .padding(-4)
                    } else if isHovering {
                        Circle()
                            .strokeBorder(NLColor.borderStrong, lineWidth: 1)
                            .padding(-3)
                    }
                }
                .padding(4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: NLMotion.hover), value: isHovering)
        .help(accessibilityLabel ?? "")
    }
}

struct Shortcuts: View {
    var body: some View {
        NLPage(L("Shortcuts"), subtitle: L("Global shortcuts."), icon: "keyboard") {
            NLSection(L("Sneak peek"), footer: L("Shows the title and artist below the notch.")) {
                NLRow(icon: "eye", title: L("Toggle Sneak Peek")) {
                    KeyboardShortcuts.Recorder<EmptyView>(for: .toggleSneakPeek)
                        .frame(width: 150)
                }
            }

            NLSection(L("Notch")) {
                NLRow(icon: "menubar.rectangle", title: L("Toggle Notch Open")) {
                    KeyboardShortcuts.Recorder<EmptyView>(for: .toggleNotchOpen)
                        .frame(width: 150)
                }
            }
        }
    }
}
#Preview {
    HUD()
}

// MARK: - Stats

/// Stats settings — the colour scheme the four rings use, plus the two
/// thresholds that decide when the alert colour appears. The gauges themselves
/// are self-explanatory in the notch.
struct StatsSettings: View {
    @AppStorage(StatsPalette.storageKey) private var paletteRaw: String = StatsPalette.mono.rawValue
    @AppStorage(StatsTuning.hotTemperatureKey) private var hotTemperature: Double = StatsTuning.defaultHotTemperature
    @AppStorage(StatsTuning.lowDiskKey) private var lowDiskGB: Double = StatsTuning.defaultLowDiskGB

    private var palette: Binding<StatsPalette> {
        Binding(
            get: { StatsPalette(rawValue: paletteRaw) ?? .mono },
            set: { paletteRaw = $0.rawValue }
        )
    }

    var body: some View {
        NLPage(
            NotchViews.stats.panelName,
            subtitle: L("CPU, GPU, memory and disk, in the notch."),
            icon: NotchViews.stats.panelIcon
        ) {
            NLSection(L("Appearance")) {
                NLRow(icon: "paintpalette", title: L("Color scheme")) {
                    NLSegmented(
                        options: StatsPalette.allCases.map {
                            NLSegmentedOption(value: $0, label: $0.label)
                        },
                        selection: palette
                    )
                }
            }

            NLSection(
                L("Alerts"),
                footer: L("Red appears only when the temperature is high or disk space is low.")
            ) {
                NLRow(icon: "thermometer.high", title: L("High temperature"), showsDivider: true) {
                    sliderRow($hotTemperature, range: 60...100, step: 1, unit: "°C")
                }
                NLRow(icon: "internaldrive", title: L("Low disk space")) {
                    sliderRow($lowDiskGB, range: 5...50, step: 1, unit: "GB")
                }
            }
        }
    }

    private func sliderRow(
        _ value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        HStack(spacing: NLSpace.s3) {
            Text("\(String(format: "%.0f", value.wrappedValue)) \(unit)")
                .font(NLFont.mono)
                .foregroundStyle(NLColor.textSecondary)
                .frame(minWidth: 48, alignment: .trailing)
            NLSlider(value: value, range: range, step: step, width: 150)
        }
    }
}

// MARK: - Weather

/// Weather settings: how the location is resolved, which city, what is shown.
///
/// Geolocation goes over the network (IP) by default — no permission prompt, no
/// configuration. But a carrier's exit node is not necessarily where you are (it
/// landed on Nanjing in local testing), so picking a city by hand is a required
/// fallback rather than an optional extra.
struct WeatherSettings: View {
    @ObservedObject private var manager = WeatherManager.shared
    @Default(.weatherAutoLocate) private var autoLocate
    @Default(.weatherAnimatedBackground) private var animated
    @Default(.weatherShowWeek) private var showWeek

    @State private var query = ""
    @State private var results: [CitySearchResult] = []
    @State private var isSearching = false
    @State private var searchMessage: String?
    @State private var searchDebounce: Task<Void, Never>?

    private static let fallbackPlace = WeatherPlace(
        name: L("Beijing"), latitude: 39.9042, longitude: 116.4074, detail: L("Beijing · China"))

    private var builtInSelection: Binding<WeatherPlace> {
        Binding(
            get: { manager.manualPlace ?? WeatherManager.builtInPlaces.first ?? Self.fallbackPlace },
            set: { select($0) }
        )
    }

    var body: some View {
        NLPage(NotchViews.weather.panelName, subtitle: L("The weather card: location, display and current data."), icon: NotchViews.weather.panelIcon) {
            locationSection
            displaySection
            statusSection
        }
        .task { await manager.refresh() }
    }

    // MARK: - Location

    private var locationSection: some View {
        NLSection(
            L("Location"),
            footer: autoLocate
                ? L("Uses your network address, so no permission is needed. Turn it off if it picks the wrong city.")
                : L("Search by Chinese, pinyin or English name. Results come from OpenStreetMap.")
        ) {
            NLRow(icon: "location", title: L("Automatic location"), showsDivider: !autoLocate) {
                NLSwitch(isOn: $autoLocate, accessibilityLabel: L("Automatic location"))
            }
            .onChange(of: autoLocate) { _, isOn in
                if isOn {
                    // Back to the network answer; drop the pinned city.
                    manager.manualPlace = nil
                    manager.invalidate()
                } else if manager.manualPlace == nil {
                    // Seed with something so the tab is never left pointing at an
                    // IP guess while showing "pinned".
                    manager.manualPlace = WeatherManager.builtInPlaces.first
                }
                applyChange()
            }

            if !autoLocate {
                NLRow(icon: "mappin", title: L("Selected city"),
                    subtitle: manager.manualPlace?.subtitle.isEmpty == false
                        ? manager.manualPlace?.subtitle : nil,
                    showsDivider: true
                ) {
                    Text(manager.manualPlace?.name ?? L("Not selected"))
                        .font(NLFont.body)
                        .foregroundStyle(NLColor.textSecondary)
                }

                NLRow(icon: "magnifyingglass", title: L("Search city"), subtitle: searchMessage, showsDivider: true) {
                    HStack(spacing: NLSpace.s3) {
                        if isSearching {
                            ProgressView().controlSize(.small)
                        }
                        NLTextField(
                            placeholder: L("e.g. Chun'an / Suzhou / Tokyo"),
                            text: $query,
                            width: 200
                        )
                        .onChange(of: query) { _, text in
                            // Search as the user types, debounced so a burst of
                            // keystrokes is one lookup.
                            searchDebounce?.cancel()
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else {
                                results = []
                                searchMessage = nil
                                return
                            }
                            searchDebounce = Task {
                                try? await Task.sleep(for: .milliseconds(500))
                                guard !Task.isCancelled else { return }
                                await runSearch()
                            }
                        }
                        .onSubmit { Task { await runSearch() } }

                        Button(L("Search")) { Task { await runSearch() } }
                            .buttonStyle(NLButtonStyle(variant: .secondary))
                            .disabled(
                                query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || isSearching)
                    }
                }

                NLRow(icon: "building.2", title: L("Popular cities"), showsDivider: !results.isEmpty) {
                    NLSelect(
                        options: WeatherManager.builtInPlaces.map {
                            NLSelectOption(value: $0, label: $0.name)
                        },
                        selection: builtInSelection,
                        minWidth: 160
                    )
                }

                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    NLListRow(
                        title: result.place.name,
                        subtitle: result.place.subtitle.isEmpty ? nil : result.place.subtitle,
                        showsDivider: index < results.count - 1,
                        onTap: { select(result.place) }
                    ) {
                        if manager.manualPlace?.id == result.place.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NLColor.accent)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        NLSection(L("Display"), footer: L("The background follows the weather and time of day; animating it costs the most battery.")) {
            NLRow(icon: "cloud.sun", title: L("Animated sky background"), showsDivider: true) {
                NLSwitch(isOn: $animated, accessibilityLabel: L("Animated sky background"))
            }
            NLRow(icon: "calendar.day.timeline.left", title: L("Show week view")) {
                NLSwitch(isOn: $showWeek, accessibilityLabel: L("Show week view"))
            }
        }
    }

    // MARK: - State

    private var statusSection: some View {
        NLSection(L("Status"), footer: L("Data from Open-Meteo; no key needed.")) {
            if let snapshot = manager.snapshot {
                NLRow(icon: "mappin.and.ellipse", title: L("Current city"), showsDivider: true) {
                    HStack(spacing: NLSpace.s2) {
                        Text(manager.resolvedPlace?.name ?? snapshot.placeName)
                            .font(NLFont.body)
                            .foregroundStyle(NLColor.textSecondary)
                        if manager.resolvedFromIP {
                            NLBadge(text: L("Network location"))
                        }
                    }
                }

                NLRow(icon: "cloud.sun", title: L("Current conditions"),
                    subtitle: "\(Int(snapshot.temperature.rounded()))° · \(WeatherCode.label(snapshot.code))",
                    showsDivider: true
                )

                NLRow(icon: "clock.arrow.circlepath", title: L("Updated"), showsDivider: true) {
                    Text(snapshot.fetchedAt, style: .time)
                        .font(NLFont.body)
                        .foregroundStyle(NLColor.textSecondary)
                }

                NLRow(icon: "arrow.clockwise", title: L("Refresh")) {
                    HStack(spacing: NLSpace.s3) {
                        if let error = manager.errorMessage {
                            Text(error)
                                .font(NLFont.caption)
                                .foregroundStyle(NLColor.textSecondary)
                        }
                        Button(L("Refresh now")) {
                            Task { await manager.refresh(force: true) }
                        }
                        .buttonStyle(NLButtonStyle(variant: .secondary))
                    }
                }
            } else if manager.isLoading {
                NLRow(icon: "arrow.clockwise", title: L("Fetching…")) {
                    ProgressView().controlSize(.small)
                }
            } else {
                NLRow(icon: "exclamationmark.triangle", title: manager.errorMessage ?? L("No data")) {
                    Button(L("Try Again")) { Task { await manager.refresh(force: true) } }
                        .buttonStyle(NLButtonStyle(variant: .secondary))
                }
            }
        }
    }

    // MARK: - Actions

    /// Nudges an already-open weather tab to reload after a settings change.
    private func applyChange() {
        NotificationCenter.default.post(name: .weatherShouldRefresh, object: nil)
    }

    /// Runs the free-text city lookup and reports an empty result honestly
    /// instead of leaving the field looking broken.
    private func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSearching = true
        searchMessage = nil
        defer { isSearching = false }

        do {
            let found = try await manager.searchCities(text)
            results = found
            if found.isEmpty {
                searchMessage = String(
                    localized: "No results for “\(text)”. Try another spelling (e.g. “Suzhou”).")
            }
        } catch {
            results = []
            searchMessage = String(localized: "Search failed: \(error.localizedDescription)")
        }
    }

    /// Pins the picked city and tells the weather tab to reload.
    private func select(_ place: WeatherPlace) {
        manager.manualPlace = place
        manager.invalidate()
        applyChange()
        searchMessage = String(localized: "Pinned \(place.name).")
    }
}
