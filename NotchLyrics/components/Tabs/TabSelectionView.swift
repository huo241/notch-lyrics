//
//  TabSelectionView.swift
//  Notch Lyrics
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
    /// Optical weight for outlined symbols (see TabButton.iconWeight). Solid glyphs keep the default.
    var iconWeight: Font.Weight = .regular
}

let tabs = NotchViews.allCases.map { view in
    TabModel(
        label: view.panelName,
        icon: view.panelIcon,
        view: view,
        // The outlined glyphs (laptop, note, cpu) sit at the same optical density
        // as the solid silhouettes only with a touch more weight.
        iconWeight: (view == .home || view == .quickNote || view == .stats)
            ? .semibold : .regular
    )
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    /// Observed directly (not through the coordinator) so the bar rebuilds the
    /// moment a switch is flipped in Settings.
    @Default(.hiddenTabs) private var hiddenTabs: [String]
    @Namespace var animation

    private var visibleTabs: [TabModel] {
        tabs.filter { !hiddenTabs.contains($0.view.rawValue) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view, iconWeight: tab.iconWeight) {
                        withAnimation(NotchAnimations.panelSwitch) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    // The bar only ever gets the strip between the slab's left
                    // edge and the notch cut-out (~168 pt). Letting each tab
                    // grow into an equal share of it means the icons keep a
                    // constant, comfortable gap no matter how wide the notch
                    // is, and the row can never overflow into the cut-out.
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(Capsule())
    }
}

#Preview {
    NotchHeader().environmentObject(NotchViewModel())
}
