//
//  MusicControlButton.swift
//  Notch Lyrics
//
//  Created by Alexander on 2025-11-16.
//

import Defaults

enum MusicControlButton: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case shuffle
    case previous
    case playPause
    case next
    case repeatMode
    case volume
    case favorite
    case goBackward
    case goForward
    case share
    case none

    var id: String { rawValue }

    static let defaultLayout: [MusicControlButton] = [
        .none,
        .previous,
        .playPause,
        .next,
        .favorite,
        .share
    ]

    static let minSlotCount: Int = 3
    static let maxSlotCount: Int = 6

    static let pickerOptions: [MusicControlButton] = [
        .shuffle,
        .previous,
        .playPause,
        .next,
        .repeatMode,
        .favorite,
        .volume,
        .goBackward,
        .goForward,
        .share
    ]

    var label: String {
        switch self {
        case .shuffle:
            return L("Shuffle")
        case .previous:
            return L("Previous")
        case .playPause:
            return L("Play/Pause")
        case .next:
            return L("Next")
        case .repeatMode:
            return L("Repeat")
        case .volume:
            return L("Volume")
        case .favorite:
            return L("Favorite")
        case .goBackward:
            return L("Back 15 Seconds")
        case .goForward:
            return L("Forward 15 Seconds")
        case .share:
            return L("Share")
        case .none:
            return L("Empty slot")
        }
    }

    var iconName: String {
        switch self {
        case .shuffle:
            return "shuffle"
        case .previous:
            return "backward.fill"
        case .playPause:
            return "playpause"
        case .next:
            return "forward.fill"
        case .repeatMode:
            return "repeat"
        case .volume:
            return "speaker.wave.2.fill"
        case .favorite:
            return "heart"
        case .goBackward:
            return "gobackward.15"
        case .goForward:
            return "goforward.15"
        case .share:
            return "square.and.arrow.up"
        case .none:
            return ""
        }
    }

    var prefersLargeScale: Bool {
        self == .playPause
    }
}
