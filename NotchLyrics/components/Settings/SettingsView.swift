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
                NLSidebarItem(id: "Media", label: L("Media"), icon: "play.laptopcomputer"),
                NLSidebarItem(id: "Calendar", label: L("Calendar"), icon: "calendar"),
                NLSidebarItem(id: "HUD", label: "HUD", icon: "dial.medium.fill"),
                NLSidebarItem(id: "Battery", label: L("Battery"), icon: "battery.100.bolt"),
                NLSidebarItem(id: "Shelf", label: L("Shelf"), icon: "books.vertical"),
                NLSidebarItem(id: "QuickNote", label: L("Quick Note"), icon: "note.text"),
                NLSidebarItem(id: "Weather", label: L("Weather"), icon: "cloud.sun.fill"),
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
            case "Shortcuts":
                Shortcuts()
            case "Extensions":
                GeneralSettings()
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

    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
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

    private var gestureSensitivityLabel: String {
        if gestureSensitivity <= 150 { return L("High") }
        if gestureSensitivity <= 250 { return L("Medium") }
        return L("Low")
    }

    var body: some View {
        NLPage(
            L("General"),
            subtitle: L("How the notch looks, which display it appears on, and how it responds to the mouse and gestures.")
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
            footer: L("Applies to the whole app. Switching the language restarts Notch Lyrics.")
        ) {
            NLRow(title: L("Language")) {
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
                Text(L("Notch Lyrics will use the new language after it restarts."))
            }
        }
    }

    // MARK: - System features

    private var systemSection: some View {
        NLSection(L("System features")) {
            NLRow(title: L("Show menu bar icon"), showsDivider: true) {
                NLSwitch(isOn: $menubarIcon, accessibilityLabel: L("Show menu bar icon"))
            }

            NLRow(title: L("Launch at login"), showsDivider: true) {
                NLSwitch(isOn: launchAtLoginBinding, accessibilityLabel: L("Launch at login"))
            }

            NLRow(title: L("Show on all displays"), showsDivider: true) {
                NLSwitch(isOn: $showOnAllDisplays, accessibilityLabel: L("Show on all displays"))
            }
            .onChange(of: showOnAllDisplays) {
                NotificationCenter.default.post(
                    name: Notification.Name.showOnAllDisplaysChanged, object: nil)
            }

            NLRow(title: L("Preferred display"), showsDivider: true) {
                NLSelect(
                    options: displayOptions,
                    selection: $coordinator.preferredScreenUUID,
                    minWidth: 160
                )
            }
            .disabled(showOnAllDisplays)

            NLRow(title: L("Automatically switch displays"), subtitle: L("Moves the notch to whichever display the pointer is on.")) {
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
            footer: L("“Match real notch height” and “Match menubar height” follow the system; use a custom height only when you need exact alignment.")
        ) {
            NLRow(title: L("Notch height on notch displays"), showsDivider: true) {
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
                NLRow(title: L("Custom height"), showsDivider: true) {
                    sliderRow($notchHeight.asDouble, range: 15...45, unit: "px")
                }
                .onChange(of: notchHeight) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }

            NLRow(title: L("Notch height on non-notch displays"), showsDivider: nonNotchHeightMode == .custom) {
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
                NLRow(title: L("Custom height")) {
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
            NLRow(title: L("Open notch on hover"), showsDivider: true) {
                NLSwitch(isOn: $openNotchOnHover, accessibilityLabel: L("Open notch on hover"))
            }

            NLRow(title: L("Enable haptic feedback"), showsDivider: true) {
                NLSwitch(isOn: $enableHaptics, accessibilityLabel: L("Enable haptic feedback"))
            }

            NLRow(title: L("Remember last tab"), showsDivider: openNotchOnHover) {
                NLSwitch(
                    isOn: $coordinator.openLastTabByDefault, accessibilityLabel: L("Remember last tab"))
            }

            if openNotchOnHover {
                NLRow(title: L("Hover delay")) {
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
            footer: L("When “Open notch on hover” is off: two-finger swipe up on the notch to close it, swipe down to open it. Scaling is visual feedback only — with it off, a swipe past the sensitivity threshold still closes the notch.")
        ) {
            NLRow(title: L("Enable gestures"), showsDivider: enableGestures) {
                NLSwitch(isOn: $enableGestures, accessibilityLabel: L("Enable gestures"))
            }
            .disabled(!openNotchOnHover)

            if enableGestures {
                NLRow(title: L("Change media with horizontal gestures"), subtitle: L("Not implemented yet."), showsDivider: true) {
                    NLSwitch(isOn: .constant(false), accessibilityLabel: L("Change media with horizontal gestures"))
                }
                .disabled(true)

                NLRow(title: L("Close gesture"), showsDivider: true) {
                    NLSwitch(isOn: $closeGestureEnabled, accessibilityLabel: L("Close gesture"))
                }

                NLRow(title: L("Scale the notch while swiping"), showsDivider: true) {
                    NLSwitch(isOn: $swipeScalesNotch, accessibilityLabel: L("Scale the notch while swiping"))
                }

                NLRow(title: L("Gesture sensitivity")) {
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
        NLPage(L("Battery"), subtitle: L("The battery indicator in the notch, plus status alerts when power is connected or disconnected.")) {
            NLSection(L("General")) {
                NLRow(title: L("Show battery indicator"), showsDivider: true) {
                    NLSwitch(isOn: $showBatteryIndicator, accessibilityLabel: L("Show battery indicator"))
                }
                NLRow(title: L("Show power status notifications")) {
                    NLSwitch(
                        isOn: $showPowerStatusNotifications, accessibilityLabel: L("Show power status notifications"))
                }
            }

            NLSection(L("Battery Information")) {
                NLRow(title: L("Show battery percentage"), showsDivider: true) {
                    NLSwitch(isOn: $showBatteryPercentage, accessibilityLabel: L("Show battery percentage"))
                }
                NLRow(title: L("Show power status icons")) {
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
            subtitle: L("Replacing the system HUD for volume, brightness and keyboard backlight, plus the progress display in the open and closed notch.")
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
            NLRow(
                title: L("Replace system HUD"),
                subtitle: L("Replace the native macOS HUD for volume, brightness and keyboard backlight with a custom style."),
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
                        Text(L("Replacing the system HUD requires Accessibility permission. Grant it to turn this on."))
                            .font(NLFont.caption)
                            .foregroundStyle(NLColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L("Request Accessibility Permission")) {
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
            NLRow(title: L("Option key behaviour"), showsDivider: true) {
                NLSelect(options: Self.optionKeyOptions, selection: $optionKeyAction, minWidth: 140)
            }

            NLRow(title: L("Progress bar style"), showsDivider: true) {
                NLSegmented(
                    options: [
                        NLSegmentedOption(value: false, label: L("Hierarchical")),
                        NLSegmentedOption(value: true, label: L("Gradient")),
                    ],
                    selection: $enableGradient
                )
            }

            NLRow(title: L("Enable glowing effect"), showsDivider: true) {
                NLSwitch(isOn: $systemEventIndicatorShadow, accessibilityLabel: L("Enable glowing effect"))
            }

            NLRow(title: L("Tint progress bar with accent color")) {
                NLSwitch(isOn: $systemEventIndicatorUseAccent, accessibilityLabel: L("Tint progress bar with accent color"))
            }
        }
        .disabled(!hudReplacement)
    }

    // MARK: - Open notch

    private var openNotchSection: some View {
        NLSection(L("Open Notch")) {
            NLRow(title: L("Show HUD in open notch"), showsDivider: true) {
                NLSwitch(isOn: $showOpenNotchHUD, accessibilityLabel: L("Show HUD in open notch"))
            }
            NLRow(title: L("Show percentage")) {
                NLSwitch(isOn: $showOpenNotchHUDPercentage, accessibilityLabel: L("Show percentage"))
            }
            .disabled(!showOpenNotchHUD)
        }
        .disabled(!hudReplacement)
    }

    // MARK: - Closed notch

    private var closedNotchSection: some View {
        NLSection(L("Closed Notch")) {
            NLRow(title: L("HUD style"), showsDivider: true) {
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

            NLRow(title: L("Show percentage")) {
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
    @Default(.keepMusicOpen) var keepMusicOpen
    @Default(.pinnedPlayerBundle) var pinnedPlayerBundle

    /// Observed so the pin row can name the app being followed and enable the
    /// switch only once a real track has been seen.
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        NLPage(
            L("Media"),
            subtitle: L("Beyond the microphone: this page decides how the music player looks in the notch and when it appears.")
        ) {
            mediaSourceSection

            NLSection(L("Media playback live activity")) {
                NLRow(title: L("Show music live activity"), showsDivider: true) {
                    NLSwitch(
                        isOn: $coordinator.musicLiveActivityEnabled.animation(),
                        accessibilityLabel: L("Show music live activity"))
                }

                NLRow(title: L("Show sneak peek on playback changes"), showsDivider: true) {
                    NLSwitch(isOn: $enableSneakPeek, accessibilityLabel: L("Show sneak peek on playback changes"))
                }

                NLRow(title: L("Sneak Peek Style"), showsDivider: true) {
                    NLSelect(
                        options: SneakPeekStyle.allCases.map {
                            NLSelectOption(value: $0, label: $0.displayName)
                        },
                        selection: $sneakPeekStyles,
                        minWidth: 120
                    )
                }

                NLRow(title: L("Media inactivity timeout"), showsDivider: true) {
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

                NLRow(title: L("Full screen behavior")) {
                    NLSelect(
                        options: [
                            NLSelectOption(value: HideNotchOption.always, label: L("Hide for all apps")),
                            NLSelectOption(
                                value: HideNotchOption.nowPlayingOnly, label: L("Hide for media app only")),
                            NLSelectOption(value: HideNotchOption.never, label: L("Never hide")),
                        ],
                        selection: $hideNotchOption,
                        minWidth: 140
                    )
                }
            }

            NLSection(
                L("Media controls"),
                footer: L("Choose which controls appear in the music player. The volume control expands to the right when active.")
            ) {
                MusicSlotConfigurationView()
                NLDivider()
                NLRow(title: L("Show lyrics in the notch")) {
                    NLSwitch(isOn: $enableLyrics, accessibilityLabel: L("Show lyrics in the notch"))
                }

                NLRow(title: L("Keep lyrics on screen while playing"), showsDivider: true) {
                    NLSwitch(
                        isOn: $keepMusicOpen,
                        accessibilityLabel: L("Keep lyrics on screen while playing"))
                }
            }
        }
    }

    private var mediaSourceSection: some View {
        NLSection(L("Media Source")) {
            NLRow(title: L("Music Source")) {
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
                NLRow(title: L("Pin to one app"), subtitle: pinSubtitle) {
                    NLSwitch(isOn: pinBinding, accessibilityLabel: L("Pin to one app"))
                }
                NLDivider()
                NLFootnote(pinHint)
            }
            if mediaController == .neteaseCloudMusic {
                NLDivider()
                NLFootnote(L("Only tracks the NetEase Cloud Music desktop app. Playback in other apps no longer replaces what the notch shows, and lyrics are looked up on NetEase first."))
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
                NLFootnote(L("“Now Playing” was the only option in previous versions and works with every media app."))
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
            return L("Turn this on while the app you want is playing. From then on only that app is tracked — starting playback in another app leaves the notch untouched. This is separate from keeping lyrics on screen.")
        }
        return String(
            format: L("Locked to %@. Playback in other apps no longer replaces what the notch shows."),
            appDisplayName(for: pinnedPlayerBundle))
    }

    /// Human name for a bundle id. Known music apps use their English product
    /// names so the wording matches the Music Source picker; anything else
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
            L("Quick Note"),
            subtitle: L("Where quick notes are saved. Switching destinations keeps the other side's settings, so you can switch back anytime.")
        ) {
            NLSection(L("Quick Note storage")) {
                NLRow(title: L("Save to")) {
                    NLSegmented(options: targetOptions, selection: targetSelection)
                }
            }

            if target == .notes {
                NLSection(L("Notes"), footer: L("Every save creates a new note in the selected folder and never changes existing ones.")) {
                    NLRow(title: L("Default folder"), showsDivider: true) {
                        NLSelect(options: folderOptions, selection: folderSelection, minWidth: 180)
                    }

                    NLRow(
                        title: L("Folders"),
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
                NLSection("Obsidian", footer: L("Quick notes are saved as a new .md file in the selected folder, named after the first line.")) {
                    NLRow(
                        title: L("Folder"),
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
        NLPage(L("Calendar"), subtitle: L("The calendar and reminders in the notch: what to show and what to hide.")) {
            NLSection(L("Display options")) {
                NLRow(title: L("Show calendar"), showsDivider: true) {
                    NLSwitch(isOn: $showCalendar, accessibilityLabel: L("Show calendar"))
                }
                NLRow(title: L("Hide completed reminders"), showsDivider: true) {
                    NLSwitch(isOn: $hideCompletedReminders, accessibilityLabel: L("Hide completed reminders"))
                }
                NLRow(title: L("Hide all-day events"), showsDivider: true) {
                    NLSwitch(isOn: $hideAllDayEvents, accessibilityLabel: L("Hide all-day events"))
                }
                NLRow(title: L("Auto-scroll to next event"), showsDivider: true) {
                    NLSwitch(isOn: $autoScrollToNextEvent, accessibilityLabel: L("Auto-scroll to next event"))
                }
                NLRow(title: L("Always show full event titles")) {
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
                emptyMessage: L("There are no calendars in the system Calendar app yet.")
            )

            listSection(
                title: L("Reminders"),
                authorized: calendarManager.reminderAuthorizationStatus == .fullAccess,
                deniedMessage: L("Reminders access is denied. Turn it on in System Settings."),
                settingsURL:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders",
                items: calendarManager.reminderLists,
                emptyMessage: L("There are no lists in the system Reminders app yet.")
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
        NLPage(L("About"), subtitle: L("Version info, update settings and the project home page.")) {
            NLSection(L("Version")) {
                NLRow(
                    title: L("Version"),
                    subtitle: showBuildNumber ? nil : L("Click to show build number")
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
                NLRow(title: L("Source code"), subtitle: "github.com/huo241/notch-lyrics") {
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
    @Default(.openShelfByDefault) private var openShelfByDefault
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
        NLPage(L("Shelf"), subtitle: L("A temporary file shelf in the notch, plus the system service used to share files.")) {
            NLSection(L("General")) {
                NLRow(title: L("Enable shelf"), showsDivider: true) {
                    NLSwitch(isOn: $notchShelf, accessibilityLabel: L("Enable shelf"))
                }
                NLRow(title: L("Open shelf by default if items are present"), showsDivider: true) {
                    NLSwitch(isOn: $openShelfByDefault, accessibilityLabel: L("Open shelf by default if items are present"))
                }
                NLRow(title: L("Expanded drag detection area"), showsDivider: true) {
                    NLSwitch(isOn: $expandedDragDetection, accessibilityLabel: L("Expanded drag detection area"))
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                NLRow(title: L("Copy items on drag"), showsDivider: true) {
                    NLSwitch(isOn: $copyOnDrag, accessibilityLabel: L("Copy items on drag"))
                }
                NLRow(title: L("Remove from shelf after dragging")) {
                    NLSwitch(isOn: $autoRemoveShelfItems, accessibilityLabel: L("Remove from shelf after dragging"))
                }
            }

            NLSection(
                L("Quick Share"),
                footer: L("Choose the service used to share files from the shelf. Click the shelf button to pick files, or drop files on it to share right away.")
            ) {
                NLRow(title: L("Quick Share Service"), showsDivider: selectedProvider != nil) {
                    NLSelect(
                        options: quickShareService.availableProviders.map {
                            NLSelectOption(value: $0.id, label: displayProviderName($0.id))
                        },
                        selection: $quickShareProvider,
                        minWidth: 180
                    )
                }

                if let selectedProvider {
                    NLRow(title: L("Current selection"), subtitle: L("Files dropped on the shelf will be shared via this service")) {
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
    @Default(.mirrorShape) private var mirrorShape
    @Default(.sliderColor) private var sliderColor
    @Default(.useMusicVisualizer) private var useMusicVisualizer
    @Default(.customVisualizers) private var customVisualizers
    @Default(.selectedVisualizer) private var selectedVisualizer
    @Default(.settingsIconInNotch) private var settingsIconInNotch
    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.playerColorTinting) private var playerColorTinting
    @Default(.lightingEffect) private var lightingEffect
    @Default(.showMirror) private var showMirror
    @Default(.showNotHumanFace) private var showNotHumanFace

    @State private var selectedListVisualizer: CustomVisualizer? = nil
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0

    private static let mirrorShapeOptions: [NLSelectOption<MirrorShapeEnum>] = [
        NLSelectOption(value: .circle, label: L("Circle")),
        NLSelectOption(value: .rectangle, label: L("Square")),
    ]

    var body: some View {
        NLPage(L("Appearance"), subtitle: L("Tabs, player tinting, visualizers and the notch mirror.")) {
            generalSection
            mediaSection
            visualizerAnimationSection
            visualizerListSection
            extrasSection
        }
        .onAppear {
            // While the music visualizer is off, snap the selected animation to the first entry so nothing dangles.
            if selectedVisualizer == nil, let first = customVisualizers.first {
                selectedVisualizer = first
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        NLSection(L("General")) {
            NLRow(title: L("Always show tabs"), showsDivider: true) {
                NLSwitch(isOn: $coordinator.alwaysShowTabs, accessibilityLabel: L("Always show tabs"))
            }
            NLRow(title: L("Show settings icon in notch")) {
                NLSwitch(isOn: $settingsIconInNotch, accessibilityLabel: L("Show settings icon in notch"))
            }
        }
    }

    // MARK: - Media

    private var mediaSection: some View {
        NLSection(L("Media")) {
            NLRow(title: L("Colored spectrogram"), showsDivider: true) {
                NLSwitch(isOn: $coloredSpectrogram, accessibilityLabel: L("Colored spectrogram"))
            }
            NLRow(title: L("Tint player with album art"), showsDivider: true) {
                NLSwitch(isOn: $playerColorTinting, accessibilityLabel: L("Tint player with album art"))
            }
            NLRow(title: L("Enable blur effect behind album art"), showsDivider: true) {
                NLSwitch(isOn: $lightingEffect, accessibilityLabel: L("Enable blur effect behind album art"))
            }
            NLRow(title: L("Slider color")) {
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

    // MARK: - Custom animations

    private var visualizerAnimationSection: some View {
        NLSection(L("Custom music live activity animation")) {
            NLRow(title: L("Use music visualizer spectrogram"), showsDivider: !useMusicVisualizer) {
                NLSwitch(
                    isOn: $useMusicVisualizer.animation(),
                    accessibilityLabel: L("Use music visualizer spectrogram"))
            }
            .disabled(true)

            if !useMusicVisualizer {
                NLRow(title: L("Selected animation")) {
                    if customVisualizers.isEmpty {
                        Text(L("No custom animation available"))
                            .font(NLFont.body)
                            .foregroundStyle(NLColor.textTertiary)
                    } else {
                        NLSelect(
                            options: customVisualizers.map {
                                NLSelectOption(value: $0, label: $0.name)
                            },
                            selection: $selectedVisualizer,
                            minWidth: 160
                        )
                    }
                }
            }
        }
    }

    // MARK: - Visualizer list

    private var visualizerListSection: some View {
        NLSection(L("Custom vizualizers (Lottie)"), badge: countBadge) {
            if customVisualizers.isEmpty {
                NLEmptyState(
                    icon: "sparkles",
                    title: L("No custom visualizer"),
                    message: L("Use the ＋ below to add a Lottie JSON URL.")
                )
            } else {
                ForEach(Array(customVisualizers.enumerated()), id: \.element) { index, visualizer in
                    VisualizerRow(
                        visualizer: visualizer,
                        isSelected: selectedListVisualizer == visualizer,
                        isActive: selectedVisualizer == visualizer,
                        showsDivider: index < customVisualizers.count - 1
                    ) {
                        toggleSelection(visualizer)
                    }
                }
            }

            NLDivider()

            HStack(spacing: NLSpace.s1) {
                NLIconButton(systemName: "plus", help: L("Add new visualizer")) {
                    name = ""
                    url = ""
                    speed = 1.0
                    isPresented = true
                }
                NLIconButton(
                    systemName: "minus",
                    help: L("Remove selected visualizer"),
                    isEnabled: selectedListVisualizer != nil
                ) {
                    removeSelectedVisualizer()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, NLSpace.s3)
            .padding(.vertical, NLSpace.s1)
        }
        .sheet(isPresented: $isPresented) { addVisualizerSheet }
    }

    private var countBadge: String? {
        customVisualizers.isEmpty ? nil : "\(customVisualizers.count)"
    }

    // MARK: - Add visualizer

    private var addVisualizerSheet: some View {
        VStack(alignment: .leading, spacing: NLSpace.s6) {
            VStack(alignment: .leading, spacing: NLSpace.s1) {
                Text(L("Add new visualizer"))
                    .font(NLFont.titleLg)
                    .foregroundStyle(NLColor.textPrimary)
                Text(L("Paste a direct link to a Lottie JSON file."))
                    .font(NLFont.caption)
                    .foregroundStyle(NLColor.textSecondary)
            }

            VStack(alignment: .leading, spacing: NLSpace.s4) {
                sheetField(L("Name"), text: $name, placeholder: L("e.g. Bouncing notes"))
                sheetField(L("Lottie JSON URL"), text: $url, placeholder: "https://…/animation.json")

                HStack(spacing: NLSpace.s3) {
                    Text(L("Speed"))
                        .font(NLFont.body)
                        .foregroundStyle(NLColor.textPrimary)
                        .frame(width: 110, alignment: .leading)
                    Spacer(minLength: 0)
                    Text(String(format: "%.1f×", speed))
                        .font(NLFont.mono)
                        .foregroundStyle(NLColor.textSecondary)
                        .frame(minWidth: 40, alignment: .trailing)
                    NLSlider(value: $speed.asDouble, range: 0...2, step: 0.1, width: 160)
                }
            }

            HStack(spacing: NLSpace.s3) {
                Spacer(minLength: 0)
                Button(L("Cancel")) { isPresented = false }
                    .buttonStyle(NLButtonStyle(variant: .secondary))
                Button(L("Add")) { addVisualizer() }
                    .buttonStyle(NLButtonStyle(variant: .primary))
                    .disabled(!canAddVisualizer)
            }
        }
        .padding(NLSpace.s6)
        .frame(width: 460)
        .background(NLColor.canvas)
    }

    @ViewBuilder
    private func sheetField(
        _ label: String, text: Binding<String>, placeholder: String
    ) -> some View {
        HStack(spacing: NLSpace.s3) {
            Text(label)
                .font(NLFont.body)
                .foregroundStyle(NLColor.textPrimary)
                .frame(width: 110, alignment: .leading)
            NLTextField(placeholder: placeholder, text: text)
        }
    }

    private var canAddVisualizer: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && URL(string: url) != nil
    }

    private func addVisualizer() {
        guard let parsedURL = URL(string: url) else { return }
        let visualizer = CustomVisualizer(UUID: UUID(), name: name, url: parsedURL, speed: speed)
        if !customVisualizers.contains(visualizer) {
            customVisualizers.append(visualizer)
        }
        isPresented = false
    }

    private func removeSelectedVisualizer() {
        guard let visualizer = selectedListVisualizer else { return }
        selectedListVisualizer = nil
        if let index = customVisualizers.firstIndex(of: visualizer) {
            customVisualizers.remove(at: index)
        }
        if visualizer == selectedVisualizer, let first = customVisualizers.first {
            selectedVisualizer = first
        }
    }

    private func toggleSelection(_ visualizer: CustomVisualizer) {
        selectedListVisualizer = selectedListVisualizer == visualizer ? nil : visualizer
    }

    // MARK: - Extras

    private var extrasSection: some View {
        NLSection(L("Additional features")) {
            NLRow(
                title: L("Enable mirror"),
                subtitle: checkVideoInput() ? nil : L("No camera detected."),
                showsDivider: true
            ) {
                NLSwitch(isOn: $showMirror, accessibilityLabel: L("Enable mirror"))
            }
            .disabled(!checkVideoInput())

            NLRow(title: L("Mirror shape"), showsDivider: true) {
                NLSelect(options: Self.mirrorShapeOptions, selection: $mirrorShape, minWidth: 120)
            }

            NLRow(title: L("Show cool face animation while inactive")) {
                NLSwitch(isOn: $showNotHumanFace, accessibilityLabel: L("Show cool face animation while inactive"))
            }
        }
    }

    func checkVideoInput() -> Bool {
        AVCaptureDevice.default(for: .video) != nil
    }
}

/// Visualizer list row: a Lottie preview on the left. Taller than a normal settings row to fit the 30pt preview.
private struct VisualizerRow: View {
    let visualizer: CustomVisualizer
    let isSelected: Bool
    let isActive: Bool
    let showsDivider: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: NLSpace.s3) {
                LottieView(url: visualizer.url, speed: visualizer.speed, loopMode: .loop)
                    .frame(width: 30, height: 30, alignment: .center)

                Text(visualizer.name)
                    .font(NLFont.body)
                    .foregroundStyle(isSelected ? NLColor.textOnAccent : NLColor.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: NLSpace.s3)

                if isActive {
                    Text(L("Selected"))
                        .font(NLFont.caption)
                        .foregroundStyle(
                            isSelected
                                ? NLColor.textOnAccent.opacity(0.8) : NLColor.textSecondary)
                }
            }
            .padding(.horizontal, NLSpace.s4)
            .padding(.vertical, NLSpace.s1)
            .frame(minHeight: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? NLColor.accent : (isHovering ? NLColor.fillSelectionHover : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { isHovering = $0 }

            if showsDivider { NLDivider() }
        }
    }
}

struct Advanced: View {
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @Default(.extendHoverArea) private var extendHoverArea
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
        NLPage(L("Advanced"), subtitle: L("Accent color, window appearance and behavior, plus a few experimental options.")) {
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
        NLSection(L("Accent color"), footer: L("Follow the system accent color or pick your own; a custom color only affects this app's interactive elements.")) {
            NLRow(title: L("Accent color"), showsDivider: true) {
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
                        Text(L("Color Presets"))
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
                            Text(L("Pick a Color"))
                                .font(NLFont.body)
                                .foregroundStyle(NLColor.textPrimary)
                            Text(L("Choose any color"))
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
                NLRow(title: L("Using System Accent"), subtitle: L("Your macOS system accent color")) {
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
        NLSection(L("Window Appearance")) {
            NLRow(title: L("Corner radius scaling")) {
                NLSwitch(isOn: $cornerRadiusScaling, accessibilityLabel: L("Corner radius scaling"))
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
        NLSection(L("Window Behavior")) {
            NLRow(title: L("Extend hover area"), showsDivider: true) {
                NLSwitch(isOn: $extendHoverArea, accessibilityLabel: L("Extend hover area"))
            }
            NLRow(title: L("Hide title bar"), showsDivider: true) {
                NLSwitch(isOn: $hideTitleBar, accessibilityLabel: L("Hide title bar"))
            }
            NLRow(title: L("Show notch on lock screen"), showsDivider: true) {
                NLSwitch(isOn: $showOnLockScreen, accessibilityLabel: L("Show notch on lock screen"))
            }
            NLRow(title: L("Hide from screen recording")) {
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
        NLPage(L("Shortcuts"), subtitle: L("Global shortcuts that work without opening the notch.")) {
            NLSection(L("Media"), footer: L("Sneak Peek shows the media title and artist below the notch for a few seconds.")) {
                NLRow(title: L("Toggle Sneak Peek")) {
                    KeyboardShortcuts.Recorder<EmptyView>(for: .toggleSneakPeek)
                        .frame(width: 150)
                }
            }

            NLSection(L("Notch")) {
                NLRow(title: L("Toggle Notch Open")) {
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
        NLPage(L("Weather"), subtitle: L("The weather card in the notch: how it locates you, display options and current data.")) {
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
                ? L("Infers your location from your network exit point, with no permissions needed. If you use a proxy or the result lands in a nearby city, turn it off and search for your city.")
                : L("Type a city name and press Return, or use Search. Results come from OpenStreetMap and accept Chinese, pinyin or English.")
        ) {
            NLRow(title: L("Automatic location"), showsDivider: !autoLocate) {
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
                NLRow(
                    title: L("Selected city"),
                    subtitle: manager.manualPlace?.subtitle.isEmpty == false
                        ? manager.manualPlace?.subtitle : nil,
                    showsDivider: true
                ) {
                    Text(manager.manualPlace?.name ?? L("Not selected"))
                        .font(NLFont.body)
                        .foregroundStyle(NLColor.textSecondary)
                }

                NLRow(title: L("Search city"), subtitle: searchMessage, showsDivider: true) {
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

                NLRow(title: L("Popular cities"), showsDivider: !results.isEmpty) {
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
        NLSection(L("Display"), footer: L("The background color follows the weather and time of day; the animated background accounts for most of this feature's battery use.")) {
            NLRow(title: L("Animated sky background"), showsDivider: true) {
                NLSwitch(isOn: $animated, accessibilityLabel: L("Animated sky background"))
            }
            NLRow(title: L("Show week view")) {
                NLSwitch(isOn: $showWeek, accessibilityLabel: L("Show week view"))
            }
        }
    }

    // MARK: - State

    private var statusSection: some View {
        NLSection(L("Status"), footer: L("Weather data comes from Open-Meteo — free, with no sign-up or key required.")) {
            if let snapshot = manager.snapshot {
                NLRow(title: L("Current city"), showsDivider: true) {
                    HStack(spacing: NLSpace.s2) {
                        Text(manager.resolvedPlace?.name ?? snapshot.placeName)
                            .font(NLFont.body)
                            .foregroundStyle(NLColor.textSecondary)
                        if manager.resolvedFromIP {
                            NLBadge(text: L("Network location"))
                        }
                    }
                }

                NLRow(
                    title: L("Current conditions"),
                    subtitle: "\(Int(snapshot.temperature.rounded()))° · \(WeatherCode.label(snapshot.code))",
                    showsDivider: true
                )

                NLRow(title: L("Updated"), showsDivider: true) {
                    Text(snapshot.fetchedAt, style: .time)
                        .font(NLFont.body)
                        .foregroundStyle(NLColor.textSecondary)
                }

                NLRow(title: L("Refresh")) {
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
                NLRow(title: L("Fetching…")) {
                    ProgressView().controlSize(.small)
                }
            } else {
                NLRow(title: manager.errorMessage ?? L("No data")) {
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
