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
                .fontWeight(iconWeight)
                // 11, not 15: the tab bar only gets the left half of the notch
                // (~225pt), and a fifth icon at 15 pushes the row past that
                // budget and into the cut-out. Five tabs at 11 come to ~170pt,
                // which leaves the selected capsule some breathing room.
                .padding(.horizontal, 11)
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
