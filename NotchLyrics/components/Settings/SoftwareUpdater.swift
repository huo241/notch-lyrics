//
//  SoftwareUpdater.swift
//  Notch Lyrics
//
//  Created by Richard Kunkli on 09/08/2024.
//

import SwiftUI
import Sparkle

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater
    
    init(updater: SPUUpdater) {
        self.updater = updater
        
        // Create our view model for our CheckForUpdatesView
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }
    
    var body: some View {
        Button(L("Check for Updates…"), action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

struct UpdaterSettingsView: View {
    private let updater: SPUUpdater

    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    var body: some View {
        NLSection(L("Software updates")) {
            NLRow(title: L("Automatically check for updates"), showsDivider: true) {
                NLSwitch(
                    isOn: $automaticallyChecksForUpdates, accessibilityLabel: L("Automatically check for updates")
                )
            }
            .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                updater.automaticallyChecksForUpdates = newValue
            }

            NLRow(title: L("Automatically download updates")) {
                NLSwitch(
                    isOn: $automaticallyDownloadsUpdates, accessibilityLabel: L("Automatically download updates")
                )
            }
            .disabled(!automaticallyChecksForUpdates)
            .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                updater.automaticallyDownloadsUpdates = newValue
            }
        }
    }
}
