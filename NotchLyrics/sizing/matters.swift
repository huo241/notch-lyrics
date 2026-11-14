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

/// Width the panel's *body* keeps when open — the surface that holds the
/// player, the tab strip and the secondary pane. Kept separate from
/// `openNotchSize` because the flare lives outside this box, not inside it.
let openNotchBodyWidth: CGFloat = 640

/// How far the open panel's shoulders spread past the body on each side, in
/// points. This is the Real Notch / Dynamic Island treatment: the slab grows
/// *outward* along the screen's top edge and thins to nothing at the edge, so
/// it reads as material growing out of the bezel. It must never be spent inward
/// — cutting the corners into the body is what makes a panel look chewed.
let openNotchShoulderFlare: CGFloat = 120

/// How far below the screen's top edge the shoulder finishes its sweep and
/// hands over to the straight body edge. Keep it well under the flare: a long,
/// shallow shoulder is what reads as silky; a 1:1 sweep reads as a chamfer.
let openNotchShoulderDrop: CGFloat = 40

/// The slab's full footprint: body plus the flare on both sides. This is what
/// the window and the clipped backdrop use, so the shoulders have room to exist.
let openNotchSize: CGSize = .init(
    width: openNotchBodyWidth + openNotchShoulderFlare * 2,
    height: 190
)
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
/// defaults that leaves 640 − 2 × 31 = 578 pt for 358 + 12 + 208.
let musicPaneWidth: CGFloat = 358
let secondaryPaneWidth: CGFloat = 208
/// Horizontal gap between the two panes.
let openNotchPaneSpacing: CGFloat = 12

let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 32), closed: (top: 6, bottom: 14))

/// Top-corner outward flare, in points — the rounded "ear" at the open
/// window's top corners. Closed state uses 0 so the tiny pill keeps its plain
/// rounded top, and the notch housing block masks with the same plain shape.
let topFlareInsets: (opened: CGFloat, closed: CGFloat) = (
    opened: openNotchShoulderFlare,
    closed: 0
)

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
