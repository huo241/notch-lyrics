//
//  NotchShape.swift
//  Notch Lyrics
//
// Created by Kai Azim on 2023-08-24.
// Original source: https://github.com/MrKai77/DynamicNotchKit
// Modified by Alexander on 2025-05-18.

import SwiftUI

struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat
    /// How far the top edge is inset from the slab's full width on each side,
    /// in points. 0 keeps the classic inward-rounded top corners; a positive
    /// value shortens the top edge and lets the slab spread outward as it
    /// descends, so the opening sits in the notch's gap instead of running
    /// across the menu bar and clipping status items.
    private var topFlare: CGFloat
    /// Vertical run of the shoulder sweep, in points. 0 derives it from
    /// `topFlare` so the two never drift apart.
    private var shoulderDrop: CGFloat

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil,
        topFlare: CGFloat = 0,
        shoulderDrop: CGFloat = 0
    ) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
        self.topFlare = topFlare
        self.shoulderDrop = shoulderDrop
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get {
            .init(
                .init(topCornerRadius, bottomCornerRadius),
                topFlare
            )
        }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            topFlare = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = topCornerRadius
        let bottom = bottomCornerRadius
        let f = topFlare
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY

        if f <= 0 {
            // Classic inward-rounded corners. True circular arcs (tangent-arc
            // construction) instead of quadratic Bézier: a quadratic corner
            // approaches the straight edge too slowly and bends too late, which
            // reads as a slightly "squared-off" / not-quite-round corner — most
            // visible on the larger bottom corners.
            path.move(to: CGPoint(x: minX + top, y: minY))
            path.addLine(to: CGPoint(x: maxX - top, y: minY))
            path.addArc(
                tangent1End: CGPoint(x: maxX, y: minY),
                tangent2End: CGPoint(x: maxX, y: minY + top),
                radius: top
            )
            path.addLine(to: CGPoint(x: maxX, y: maxY - bottom))
            path.addArc(
                tangent1End: CGPoint(x: maxX, y: maxY),
                tangent2End: CGPoint(x: maxX - bottom, y: maxY),
                radius: bottom
            )
            path.addLine(to: CGPoint(x: minX + bottom, y: maxY))
            path.addArc(
                tangent1End: CGPoint(x: minX, y: maxY),
                tangent2End: CGPoint(x: minX, y: maxY - bottom),
                radius: bottom
            )
            path.addLine(to: CGPoint(x: minX, y: minY + top))
            path.addArc(
                tangent1End: CGPoint(x: minX, y: minY),
                tangent2End: CGPoint(x: minX + top, y: minY),
                radius: top
            )
            path.closeSubpath()
            return path
        }

        // Narrow-topped slab (open state). The top edge is *inset* by `f` on
        // each side, so the silhouette spreads outward as it descends: a short
        // head sits at the screen's top edge and the slab only reaches its full
        // width below the menu bar, where the status items live. That is what
        // keeps the open panel off the menu bar's icons — a top edge at full
        // width runs straight through them, because the notch's own gap is
        // narrower than the panel.
        //
        // Each side is a quarter ellipse: horizontal tangent where it leaves the
        // head, vertical tangent where it joins the body edge, and nothing in
        // between but one steady bend. Bottom corners stay true circular arcs.
        let inset = min(f, max(0, rect.width / 2 - 1))
        // Vertical run of the sweep. Equal to the inset by default: that makes
        // it a quarter circle, i.e. constant curvature with no visible kink.
        let d = shoulderDrop > 0 ? shoulderDrop : inset
        // Cubic approximation of a quarter ellipse — control points sit
        // 0.5523 · radius along each tangent from the endpoints (kappa circle,
        // max error ~0.02%).
        let kappa: CGFloat = 0.5523
        let tangentOut = inset * kappa
        let tangentDown = d * kappa

        path.move(to: CGPoint(x: minX + inset, y: minY))
        path.addLine(to: CGPoint(x: maxX - inset, y: minY))
        // top-right: out and down from the head into the full-width body
        path.addCurve(
            to: CGPoint(x: maxX, y: minY + d),
            control1: CGPoint(x: maxX - inset + tangentOut, y: minY),
            control2: CGPoint(x: maxX, y: minY + d - tangentDown)
        )
        // right body edge
        path.addLine(to: CGPoint(x: maxX, y: maxY - bottom))
        // bottom-right corner
        path.addArc(
            tangent1End: CGPoint(x: maxX, y: maxY),
            tangent2End: CGPoint(x: maxX - bottom, y: maxY),
            radius: bottom
        )
        // bottom edge
        path.addLine(to: CGPoint(x: minX + bottom, y: maxY))
        // bottom-left corner
        path.addArc(
            tangent1End: CGPoint(x: minX, y: maxY),
            tangent2End: CGPoint(x: minX, y: maxY - bottom),
            radius: bottom
        )
        // left body edge
        path.addLine(to: CGPoint(x: minX, y: minY + d))
        // top-left: out and down from the head into the body
        path.addCurve(
            to: CGPoint(x: minX + inset, y: minY),
            control1: CGPoint(x: minX, y: minY + d - tangentDown),
            control2: CGPoint(x: minX + inset - tangentOut, y: minY)
        )
        path.closeSubpath()

        return path
    }
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}
