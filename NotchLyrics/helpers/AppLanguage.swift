//
//  AppLanguage.swift
//  Notch Lyrics
//
//  Per-app language override.
//
//  macOS picks the `.lproj` that `Bundle.main` resolves against once, at process
//  launch, from the `AppleLanguages` preference — it never reads that key again.
//  A language change therefore means writing the preference and restarting; the
//  restart goes through `ApplicationRelauncher`.
//
//  "Follow System" removes the preference and hands the choice back to macOS.
//

import Foundation

enum AppLanguage {

    /// One entry in the picker. `code == nil` means Follow System.
    struct Option: Identifiable, Hashable {
        let code: String?
        /// The endonym, shown as-is whatever the UI language is.
        let label: String
        var id: String { code ?? "system" }
    }

    /// Every language the bundle actually ships a `.lproj` for, English and
    /// Spanish first. This order is the order in the picker; `label` is the
    /// endonym.
    static let options: [Option] = [
        Option(code: nil, label: "Follow System"),
        Option(code: "en", label: "English"),
        Option(code: "en-GB", label: "English (UK)"),
        Option(code: "es", label: "Español"),
        Option(code: "zh-Hans", label: "简体中文"),
        Option(code: "de", label: "Deutsch"),
        Option(code: "fr", label: "Français"),
        Option(code: "it", label: "Italiano"),
        Option(code: "pt-BR", label: "Português (Brasil)"),
        Option(code: "ru", label: "Русский"),
        Option(code: "uk", label: "Українська"),
        Option(code: "pl", label: "Polski"),
        Option(code: "cs", label: "Čeština"),
        Option(code: "hu", label: "Magyar"),
        Option(code: "tr", label: "Türkçe"),
        Option(code: "ko", label: "한국어"),
        Option(code: "ar", label: "العربية"),
    ]

    private static let preferenceKey = "AppleLanguages"

    /// The override this app wrote, or `nil` when it never wrote one
    /// (Follow System).
    ///
    /// Reads the persistent domain rather than
    /// `UserDefaults.standard.object(forKey:)`: the latter merges in
    /// `NSGlobalDomain`, which always carries an `AppleLanguages` (the system
    /// language) that has nothing to do with the per-app choice.
    static var override: String? {
        guard
            let bundleID = Bundle.main.bundleIdentifier,
            let domain = UserDefaults.standard.persistentDomain(forName: bundleID),
            let list = domain[preferenceKey] as? [String],
            let first = list.first,
            options.contains(where: { $0.code == first })
        else { return nil }
        return first
    }

    /// Writes the choice. Pass `nil` to clear the override and hand it back to
    /// the system. Takes effect on the next launch.
    ///
    /// Touches the `AppleLanguages` key and nothing else. Never swap the whole
    /// domain out with `setPersistentDomain` — that would wipe every other
    /// setting `@Default` keeps in the same domain.
    static func apply(_ code: String?) {
        if let code {
            UserDefaults.standard.set([code], forKey: preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
        }
        UserDefaults.standard.synchronize()
    }
}
