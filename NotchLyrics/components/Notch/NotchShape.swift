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
    /// How far the top edge shoulders outward past the body on each side, in
    /// points. 0 keeps the classic inward-rounded top corners; a positive value
    /// makes the top span the full width and flare out into a rounded "ear" on
    /// each side, so the window reads as wider at the very top than just below.
    /// The body narrows by this amount below the shoulders, but it stays inside
    /// the content's own horizontal padding, so nothing gets clipped.
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

        // Flared top (open state). The top edge spans the slab's full
        // footprint — body plus the flare on both sides — and each shoulder
        // sweeps *outward and down* from it into the narrower body. Outward is
        // the whole point: this is the Dynamic Island treatment, where the
        // panel looks like material growing out of the bezel and thinning to
        // nothing at the screen's top edge. Cutting the same amount *inward*
        // (what an inward chamfer does) reads as a chewed corner instead.
        //
        // Each sweep is a cubic with a horizontal tangent at the top edge and a
        // vertical one at the body edge, so neither end kinks: curvature ramps
        // up from zero and back down, which is what makes a long shoulder read
        // as silky rather than as a straight chamfer. Bottom corners stay true
        // circular arcs (absolutely round).
        let flare = min(f, max(0, rect.width / 2 - 1))
        // The sweep needs vertical room: a shoulder drop much shorter than the
        // flare forces the curve to whip around where it meets the body edge.
        let d = shoulderDrop > 0 ? min(shoulderDrop, flare) : flare * 0.55
        let bodyMinX = minX + flare
        let bodyMaxX = maxX - flare
        // Tangent lengths. The curvature at a cubic's endpoint is
        // (2/3) · (opposite control length) / (adjacent control length)², so
        // giving the vertical control a small fraction of the horizontal one
        // multiplies the curvature at the body junction by a large factor: with
        // the old 0.45·flare / 0.45·d pair the shoulder finished on a ~11 pt
        // radius while starting on a ~245 pt one — a visible whip exactly where
        // the eye expects a smooth hand-off. Keeping the two within a factor of
        // two leaves both ends in the 45–70 pt range, which reads as one
        // continuous roll instead of a taper that suddenly hooks.
        let tangentOut = flare * 0.58
        let tangentDown = d * 0.32

        path.move(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        // top-right shoulder: out at the top edge, down into the body
        path.addCurve(
            to: CGPoint(x: bodyMaxX, y: minY + d),
            control1: CGPoint(x: maxX - tangentOut, y: minY),
            control2: CGPoint(x: bodyMaxX, y: minY + tangentDown)
        )
        // right body edge
        path.addLine(to: CGPoint(x: bodyMaxX, y: maxY - bottom))
        // bottom-right corner
        path.addArc(
            tangent1End: CGPoint(x: bodyMaxX, y: maxY),
            tangent2End: CGPoint(x: bodyMaxX - bottom, y: maxY),
            radius: bottom
        )
        // bottom edge
        path.addLine(to: CGPoint(x: bodyMinX + bottom, y: maxY))
        // bottom-left corner
        path.addArc(
            tangent1End: CGPoint(x: bodyMinX, y: maxY),
            tangent2End: CGPoint(x: bodyMinX, y: maxY - bottom),
            radius: bottom
        )
        // left body edge
        path.addLine(to: CGPoint(x: bodyMinX, y: minY + d))
        // top-left shoulder
        path.addCurve(
            to: CGPoint(x: minX, y: minY),
            control1: CGPoint(x: bodyMinX, y: minY + tangentDown),
            control2: CGPoint(x: minX + tangentOut, y: minY)
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
