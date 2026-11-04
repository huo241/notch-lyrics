//
//  generic.swift
//  Notch Lyrics
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Foundation
import Defaults

public enum NotchState {
    case closed
    case open
}

public enum NotchViews: String, CaseIterable {
    case home
    case shelf
    case quickNote
    case weather
    case stats

    /// Name of the panel in Settings. Declared here, next to the cases, so the
    /// tab bar and the "which tabs do I want" list can never disagree about what
    /// exists or what to call it.
    ///
    /// `.home` is the media player, and that is what it is called everywhere —
    /// the sidebar page, the tabs list and the home page picker all read this
    /// one string. It used to be "Music" here and "Media" in the sidebar.
    var panelName: String {
        switch self {
        case .home: return L("Media")
        case .shelf: return L("Shelf")
        case .quickNote: return L("Quick Note")
        case .weather: return L("Weather")
        case .stats: return L("Stats")
        }
    }

    /// The bar's glyph, matched to the sidebar's icon for the same feature.
    var panelIcon: String {
        switch self {
        case .home: return "play.laptopcomputer"
        case .shelf: return "tray.fill"
        case .quickNote: return "note.text"
        case .weather: return "cloud.sun.fill"
        case .stats: return "cpu"
        }
    }
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"

    /// Name shown in the UI. `rawValue` is what gets persisted and stays fixed.
    var displayName: String {
        switch self {
        case .white: return L("White")
        case .albumArt: return L("Match album art")
        case .accent: return L("Accent color")
        }
    }
}
