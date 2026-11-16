//
//  drop.swift
//  Notch Lyrics
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import Foundation
import SwiftUI


/// One set of curves for the whole notch. Expand/collapse, panel switching and
/// gesture release used to each carry their own spring, and a single state
/// change could be wrapped in two different transactions at once. Different
/// parts of the panel then travelled on different curves, so width and height
/// settled at different times. Keeping every curve here makes that impossible.
public enum NotchAnimations {
    /// Expand / collapse. A bounded curve, not a spring: every part of the
    /// panel reaches its final size at the same instant and stops there, with
    /// no overshoot and no long asymptotic tail after the pointer has arrived.
    static let openClose = Animation.timingCurve(0.22, 0.86, 0.24, 1, duration: 0.30)

    /// Switching between panels. A short cross-fade with no scale. The
    /// `.animation` attached to the transition in ContentView is intentional:
    /// `coordinator.currentView` has several callers that change it outside a
    /// `withAnimation` block, and those still need a fade.
    static let panelSwitch = Animation.easeOut(duration: 0.22)

    /// Used only when a gesture ends. While the pointer is still moving the
    /// progress is set directly, so it tracks 1:1 instead of restarting a
    /// spring on every frame.
    static let gestureRelease = Animation.spring(response: 0.28, dampingFraction: 0.9)

    /// The shelf has its own interaction curve. Its drag-in and selection
    /// feedback has always used this bouncy spring; the notch's open/close
    /// timing must not change it.
    static let shelfInteraction = Animation.spring(.bouncy(duration: 0.4))
}
