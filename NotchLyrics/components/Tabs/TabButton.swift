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
                // 11 pt with no fixed gutter: the tab no longer sizes itself,
                // the bar splits its own width evenly between the five, so the
                // gap between icons is whatever is left over instead of a
                // constant that has to be squeezed to fit. Dropping to 11 is
                // what buys the extra air between the marks; the row's total
                // width does not change with it.
                .font(.system(size: 11, weight: iconWeight))
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
