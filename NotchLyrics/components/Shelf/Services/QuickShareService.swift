//
//  QuickShareService.swift
//  Notch Lyrics
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Dynamic representation of a sharing provider discovered at runtime
struct QuickShareProvider: Identifiable, Hashable, Sendable {
    var id: String
    var imageData: Data?
    var supportsRawText: Bool
}

class QuickShareService: ObservableObject {
    static let shared = QuickShareService()
    
    @Published var availableProviders: [QuickShareProvider] = []
    @Published var isPickerOpen = false
    private var cachedServices: [String: NSSharingService] = [:]
    // Hold security-scoped URLs during sharing
    private var sharingAccessingURLs: [URL] = []
    private var lifecycleDelegate: SharingLifecycleDelegate?
   
    init() {
        Task {
            await discoverAvailableProviders()
        }
    }
    
    // MARK: - Provider Discovery
    
    @MainActor
    func discoverAvailableProviders() async {
        let finder = ShareServiceFinder()

        // Use simple test items without creating actual temp files
        // This avoids issues with the Share Sheet retaining references to deleted files
        let testItems: [Any] = [
            URL(string:"http://example.com") ?? URL(fileURLWithPath: "/"),
            "Test Text" as NSString
        ]

        let services = await finder.findApplicableServices(for: testItems)

        var providers: [QuickShareProvider] = []

        for svc in services {
            let title = svc.title
            let imgData = svc.image.tiffRepresentation
            let supportsRawText = svc.canPerform(withItems: ["Test Text"])
            let provider = QuickShareProvider(id: title, imageData: imgData, supportsRawText: supportsRawText)
            if !providers.contains(provider) {
                providers.append(provider)
                cachedServices[title] = svc
            }
        }
        
        if let idx = providers.firstIndex(where: { $0.id == "AirDrop" }) {
            let ad = providers.remove(at: idx)
            providers.insert(ad, at: 0)
        }

        if !providers.contains(where: { $0.id == "System Share Menu" }) {
            providers.append(QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true))
        }

        self.availableProviders = providers

    }
    
    // MARK: - File Picker
    @MainActor
    func showFilePicker(for provider: QuickShareProvider, from view: NSView?) async {
        guard !isPickerOpen else {
            print("⚠️ QuickShareService: File picker already open")
            return
        }

        isPickerOpen = true
        SharingStateManager.shared.beginInteraction()

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Select Files for \(provider.id)"
        panel.message = "Choose files to share via \(provider.id)"

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            defer {
                self?.isPickerOpen = false
                SharingStateManager.shared.endInteraction()
            }

            if response == .OK && !panel.urls.isEmpty {
                Task {
                    await self?.shareFilesOrText(panel.urls, using: provider, from: view)
                }
            }
        }

        let response = panel.runModal()
        completion(response)
    }
    
    // MARK: - Sharing
    @MainActor
    func shareFilesOrText(_ items: [Any], using provider: QuickShareProvider, from view: NSView?) async {
        let fileURLs = items.compactMap { $0 as? URL }.filter { $0.isFileURL }
        // Stop any previous sharing access
        stopSharingAccessingURLs()
        // Start security-scoped access for all file URLs
        sharingAccessingURLs = fileURLs.filter { $0.startAccessingSecurityScopedResource() }

        // Setup lifecycle delegate to keep notch open during picker/service
        let delegate = SharingStateManager.shared.makeDelegate { [weak self] in
            self?.lifecycleDelegate = nil
            self?.stopSharingAccessingURLs()
        }
        lifecycleDelegate = delegate

        if let svc = cachedServices[provider.id], svc.canPerform(withItems: items) {
            // For direct service path, explicitly mark service interaction start
            delegate.markServiceBegan()
            svc.delegate = delegate
            svc.perform(withItems: items)
        } else {
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = delegate
            delegate.markPickerBegan()
            if let view {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        }
    }

    private func stopSharingAccessingURLs() {
        NSLog("Stopping sharing access to URLs")
        for url in sharingAccessingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        sharingAccessingURLs.removeAll()
    }
    // MARK: - Now Playing Share

    /// Shares the currently playing track through the system share sheet: a text
    /// summary plus the album art, and — when the source player exposes one — a
    /// direct link to the song (Apple Music / Spotify). Falls back to
    /// text + artwork when no link is available; never errors out.
    @MainActor
    func shareNowPlaying() async {
        let m = MusicManager.shared
        guard m.hasActiveTrack, !m.songTitle.isEmpty else { return }

        var items: [Any] = []
        var summary = "🎵 \(m.songTitle)"
        if !m.artistName.isEmpty {
            summary += "\n\(m.artistName)"
            if !m.album.isEmpty { summary += " · \(m.album)" }
        }
        items.append(summary as NSString)

        if m.canShareArtwork {
            items.append(m.albumArt)
        }

        if let link = await resolveSourceURL() {
            items.append(link)
        }

        // Anchor the picker to the notch window's content view. Getting the
        // anchor from the real window (rather than an injected NSView kept as a
        // SwiftUI background) avoids compositing artifacts under the music
        // player's drawingGroup.
        let anchor = NSApp.windows.first(where: { $0 is NotchSkyLightWindow })?.contentView

        let systemMenu = QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
        if availableProviders.isEmpty { await discoverAvailableProviders() }
        await shareFilesOrText(items, using: systemMenu, from: anchor)
    }

    /// Resolves a shareable link for the current track when the source player
    /// exposes one. Spotify yields a precise track URL via AppleScript; Apple
    /// Music falls back to a search URL built from track metadata (MusicKit's
    /// `SystemMusicPlayer` is unavailable on macOS). Other players return nil
    /// and the share gracefully degrades to text + artwork.
    private func resolveSourceURL() async -> URL? {
        guard let bundle = MusicManager.shared.bundleIdentifier else { return nil }
        switch bundle {
        case "com.apple.Music":
            return await appleMusicSearchURL()
        case "com.spotify.client":
            return await spotifyTrackURL()
        default:
            return nil
        }
    }

    /// Apple Music on macOS does not expose a public deep link for the
    /// currently-playing track, so we build a store search URL from the
    /// metadata. It opens Apple Music to the matching results.
    private func appleMusicSearchURL() async -> URL? {
        let m = MusicManager.shared
        guard !m.songTitle.isEmpty else { return nil }
        var query = m.songTitle
        if !m.artistName.isEmpty { query += " \(m.artistName)" }
        if !m.album.isEmpty { query += " \(m.album)" }
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://music.apple.com/search?term=\(encoded)") else { return nil }
        return url
    }

    /// Spotify's AppleScript `current track` returns a `spotify:track:<id>` URI,
    /// which maps directly onto the open.spotify.com web link.
    private func spotifyTrackURL() async -> URL? {
        let script = """
        tell application "Spotify"
            if (player state is playing or player state is paused) then
                return id of current track
            else
                return ""
            end if
        end tell
        """
        guard let result = try? await AppleScriptHelper.execute(script),
              let uri = result.stringValue, !uri.isEmpty else { return nil }
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", parts[1] == "track" else { return nil }
        return URL(string: "https://open.spotify.com/track/\(parts[2])")
    }

    func shareDroppedFiles(_ providers: [NSItemProvider], using shareProvider: QuickShareProvider, from view: NSView?) async {
        var itemsToShare: [Any] = []
        var foundText: String?

        for provider in providers {
            if let webURL = await provider.extractURL() {
                itemsToShare.append(webURL)
            } else if foundText == nil, let text = await provider.extractText() {
                foundText = text
            } else if let itemFileURL = await provider.extractItem() {
                let resolvedURL = await resolveShelfItemBookmark(for: itemFileURL) ?? itemFileURL
                itemsToShare.append(resolvedURL)
            }
        }

        // If text was found, prioritize sharing it.
        if let text = foundText {
            if shareProvider.supportsRawText {
                await shareFilesOrText([text], using: shareProvider, from: view)
            } else {
                if let tempTextURL = await TemporaryFileStorageService.shared.createTempFile(for: .text(text)) {
                    await shareFilesOrText([tempTextURL], using: shareProvider, from: view)
                    TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: tempTextURL)
                } else {
                    await shareFilesOrText([text], using: shareProvider, from: view)
                }
            }
        } else if !itemsToShare.isEmpty {
            await shareFilesOrText(itemsToShare, using: shareProvider, from: view)
        }
    }

    private func resolveShelfItemBookmark(for fileURL: URL) async -> URL? {
        let items = await ShelfStateViewModel.shared.items

        for itm in items {
            if let resolved = await ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: itm) {
                if resolved.standardizedFileURL.path == fileURL.standardizedFileURL.path {
                    return resolved
                }
            }
        }
        print("❌ Failed to resolve bookmark for shelf item")
        return nil
    }
}

// MARK: - App Storage Extension for Provider Selection

extension QuickShareProvider {
    static var defaultProvider: QuickShareProvider {
        let svc = QuickShareService.shared

        if let airdrop = svc.availableProviders.first(where: { $0.id == "AirDrop" }) {
            return airdrop
        }
        return svc.availableProviders.first ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
    }
}
