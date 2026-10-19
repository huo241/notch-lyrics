//
//  NotchSkyLightWindow.swift
//  Notch Lyrics
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

/// Lightweight file logger for the drag-and-drop investigation.
/// Writes to `/tmp/notchlyrics-drag.log` (and NSLog) so the whole drop chain can
/// be inspected after a single repro without opening Console. Temporary.
enum NLDiag {
    // The app is sandboxed, so an absolute /tmp path is not writable. Use the
    // container's temp dir (resolves under ~/Library/Containers/<bundle>/Data/tmp).
    static let url: URL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("notchlyrics-drag.log")
    static func log(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            if let d = line.data(using: .utf8) { h.write(d) }
            try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
        // Also goes to the unified log, readable via:
        //   log show --last 5m --predicate 'eventMessage CONTAINS "[NotchLyrics-Diag]"'
        NSLog("[NotchLyrics-Diag] \(msg)")
    }
}

class NotchSkyLightWindow: NSPanel, NSDraggingDestination {
    private var isSkyLightEnabled: Bool = false
    
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        // Make the window itself a drag destination for files. Doing this at the
        // NSPanel level (rather than relying on SwiftUI .onDrop, whose target can
        // be torn down mid-drag by the auto-expand animation) gives the drop a
        // stable receiver that survives every SwiftUI view rebuild.
        registerForDraggedTypes([.fileURL, .URL])

        // Apply initial sharing type setting
        updateSharingType()
    }

    // MARK: - NSDraggingDestination (window-level file drop)

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let pb = info.draggingPasteboard

        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }

        // Some sources still publish only the legacy file-name list.
        if let names = pb.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           !names.isEmpty {
            return names.map { URL(fileURLWithPath: $0) }
        }

        // …and some publish a single file URL as a raw string.
        if let raw = pb.string(forType: .fileURL), let url = URL(string: raw) {
            return [url]
        }

        return []
    }

    private var didLogUpdate = false

    /// Whether the pointer is currently over the share square (left side).
    private func isOnShareZone(_ info: NSDraggingInfo) -> Bool {
        let zone = NotchViewCoordinator.shared.airDropZoneRect
        guard !zone.isEmpty else { return false }
        return zone.contains(info.draggingLocation)
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        let types = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        NLDiag.log("WINDOW draggingEntered fileURLs=\(urls.count) types=\(types)")
        didLogUpdate = false
        guard !urls.isEmpty else { return [] }
        NotchViewCoordinator.shared.airDropZoneView?.setHighlighted(isOnShareZone(sender))
        // Deliberately do NOT touch any window/notch state in here. Flipping
        // `canBecomeKey` or opening the notch mid-drag rebuilds the SwiftUI tree
        // and the drag session dies before the drop is delivered, which is exactly
        // the "accepts the hover but never the file" symptom. The notch is
        // revealed *after* the drop instead (see performDragOperation).
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Always allow. Re-reading the pasteboard on every update is both costly
        // and fragile: when the read comes back empty we would answer "no drop",
        // which cancels the session on mouse-up and no performDragOperation ever
        // arrives. Validation happens once in performDragOperation.
        if !didLogUpdate {
            didLogUpdate = true
            NLDiag.log("WINDOW draggingUpdated (accepting)")
        }
        // Pure layer-opacity change: no SwiftUI state, so the session survives.
        NotchViewCoordinator.shared.airDropZoneView?.setHighlighted(isOnShareZone(sender))
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        NLDiag.log("WINDOW draggingExited")
        NotchViewCoordinator.shared.airDropZoneView?.setHighlighted(false)
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let ok = !fileURLs(from: sender).isEmpty
        NLDiag.log("WINDOW prepareForDragOperation ok=\(ok) canBecomeKey=\(canBecomeKey)")
        return ok
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        let location = sender.draggingLocation
        let shareZone = NotchViewCoordinator.shared.airDropZoneRect
        let onShareZone = !shareZone.isEmpty && shareZone.contains(location)
        NLDiag.log(
            "WINDOW performDragOperation fileURLs=\(urls.count) loc=\(location) "
                + "shareZone=\(shareZone) onShareZone=\(onShareZone)"
        )
        NotchViewCoordinator.shared.airDropZoneView?.setHighlighted(false)
        guard !urls.isEmpty else { return false }

        // Two landing targets share one window, so the drop has to be routed by
        // where the pointer actually is. On the left square → hand the files to
        // the selected share service (AirDrop by default). Anywhere else →
        // stage them in the shelf.
        if onShareZone {
            NLDiag.log("WINDOW share branch urls=\(urls.count)")
            shareDroppedURLs(urls)
            return true
        }

        NLDiag.log("WINDOW stage branch urls=\(urls.count) -> load(urls:)")
        // Stage first, then reveal: the notch is opened only after the drop has
        // been accepted, so no window/state mutation can cancel the drag session.
        ShelfStateViewModel.shared.load(urls: urls)
        NotchViewCoordinator.shared.didDropFile = true
        NotchViewCoordinator.shared.pendingShelfReveal = true
        return true
    }

    /// Shares files that were dropped straight onto the share square.
    ///
    /// Runs after `performDragOperation` has already returned `true` so nothing
    /// in here can cancel the drag session. Uses the provider the user picked in
    /// Settings (AirDrop out of the box) and falls back to the system sheet.
    private func shareDroppedURLs(_ urls: [URL]) {
        Task { @MainActor in
            // Let the drag session finish (`concludeDragOperation`) before any
            // share UI is raised. Opening a panel while the mouse is still held
            // down makes AppKit drop the share request silently.
            try? await Task.sleep(for: .milliseconds(250))

            let service = QuickShareService.shared
            if service.availableProviders.isEmpty {
                await service.discoverAvailableProviders()
            }

            let wanted = Defaults[.quickShareProvider]
            let provider =
                service.availableProviders.first(where: { $0.id == wanted })
                ?? service.availableProviders.first(where: { $0.id == "AirDrop" })
                ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)

            // Anchor on the real window content view rather than a SwiftUI
            // background view, which can be rebuilt out from under the sheet.
            let anchor = NSApp.windows.first(where: { $0 is NotchSkyLightWindow })?.contentView

            NLDiag.log("SHARE provider=\(provider.id) urls=\(urls.count)")
            await service.shareFilesOrText(urls, using: provider, from: anchor)
            NLDiag.log("SHARE returned provider=\(provider.id)")
        }
    }

    func concludeDragOperation(_ sender: NSDraggingInfo?) {
        NLDiag.log("WINDOW concludeDragOperation")
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    private var observers: Set<AnyCancellable> = []
    
    // Focus is opt-in. The notch must not become the key window on its own —
    // that would pull the keyboard out from under whatever the user is typing
    // in. It is allowed only while the quick-note tab says it wants focus, or
    // while a file is being dragged over the notch. The latter is required so a
    // cross-app drag (e.g. out of Finder) can actually be *delivered*: AppKit
    // refuses to hand the drop to a window that can never become key, and bounces
    // it back. Outside those two cases `canBecomeKey` stays `false`.
    // Read as a computed property because AppKit consults it repeatedly.
    override var canBecomeKey: Bool {
        NotchViewCoordinator.shared.quickNoteWantsFocus
            || NotchViewCoordinator.shared.isDragTargeting
    }
    override var canBecomeMain: Bool {
        NotchViewCoordinator.shared.quickNoteWantsFocus
            || NotchViewCoordinator.shared.isDragTargeting
    }
}
