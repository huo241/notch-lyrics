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

public enum NotchViews {
    case home
    case shelf
    case quickNote
    case weather
}

enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
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
