//
//  TabButton.swift
//  Notch Lyrics
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    /// Optical weight. Every other icon in this bar is a solid silhouette, so an
    /// outlined symbol at the same weight reads noticeably lighter; this puts the
    /// ink back (defaults to regular, solid glyphs are unaffected).
    var iconWeight: Font.Weight = .regular
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                // 13 pt with a 7 pt gutter: the bar owns only the strip between
                // the slab's left edge and the notch cut-out, which is about
                // (560 − notch) / 2 minus the content inset — ~148 pt. Five tabs
                // have to fit inside that, or the row centres itself and the
                // last icon slides *under* the black cut-out. 13 + 14 of gutter
                // puts each tab at ~30 pt and the row at ~150 pt.
                .font(.system(size: 13, weight: iconWeight))
                .padding(.horizontal, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
