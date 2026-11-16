//
//  sizeMatters.swift
//  Notch Lyrics
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

// Transparent strip kept under the open slab. The notch deliberately casts no
// shadow: the window is a hard clip box flush with the screen top, so a
// SwiftUI shadow could never wrap the slab — all it produced was a dark band
// under the notch, and re-rasterising it every animated frame made that band
// flicker. The strip is only headroom for the closed-state chin.
let shadowPadding: CGFloat = 20

/// Size of the open slab, measured on screen — it is also the window's width,
/// so this single number decides how much of the menu bar the open panel
/// covers. The notch's own gap is only ~200 pt wide, and the status items sit
/// just outside it, so every point added here eats into them. Widening this is
/// the one change that cannot be compensated for anywhere else.
let openNotchSize: CGSize = .init(width: 580, height: 190)
let windowSize: CGSize = .init(
    width: openNotchSize.width,
    height: openNotchSize.height + shadowPadding
)

/// Width split of the open notch between the music player (left) and the
/// secondary pane holding lyrics / calendar / camera (right).
///
/// The two panes plus `openNotchPaneSpacing` must fit the slab's **inner**
/// width, not `openNotchSize.width`: the content carries a horizontal inset of
/// `cornerRadiusInsets.opened.top` (19) plus the shared 12 pt padding on each
/// side. Adding up to more than that does not make the panes overlap or shrink
/// — the row simply centres and overflows, and the window clips the excess, so
/// the tab strip and the lyrics pane lose their outer few points. With the
/// defaults that leaves 580 − 2 × 31 = 518 pt for 320 + 12 + 186.
let musicPaneWidth: CGFloat = 320
let secondaryPaneWidth: CGFloat = 186
/// Horizontal gap between the two panes.
let openNotchPaneSpacing: CGFloat = 12

/// Height of both open-state cards. The slab gives the row ~149 pt below the
/// header; 142 leaves a 7 pt breathe around the cards so the hairline stroke
/// does not sit flush against the panel edge. Both panes read this one number
/// so the music card and the lyrics card can never drift out of alignment.
let openPaneCardHeight: CGFloat = 142

let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 32), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
