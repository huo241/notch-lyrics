//
//  ClickOutsideCloser.swift
//  boringNotch
//
//  Created by Zhuanz on 2026-10-08.
//

import AppKit

/// Closes the notch when the user clicks anywhere outside its window.
///
/// The notch is a floating panel that pins itself above the menu bar on every
/// space; it never participates in normal key-window resigning, so the
/// standard "click outside to dismiss" behaviour of popovers has to be built
/// by hand. Two monitors cover both worlds:
///
/// - *global*: clicks in **other** apps (the common case — the user is working
///   elsewhere and the open notch is in the way);
/// - *local*: clicks in our own windows other than the notch (settings, etc.).
///
/// Clicks landing inside the notch window itself are left alone — they belong
/// to whatever control was hit (tab bar, editor, folder list).
@MainActor
final class ClickOutsideCloser {
    static let shared = ClickOutsideCloser()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onClose: (() -> Void)?

    /// Enables the monitors while the notch is open and tears them down when
    /// it is not, so nothing runs (and nothing can misfire) while closed.
    func setActive(_ active: Bool, onClose: @escaping () -> Void) {
        if active {
            self.onClose = onClose
            install()
        } else {
            self.onClose = nil
            uninstall()
        }
    }

    private func install() {
        guard globalMonitor == nil else { return }

        // Global monitor callbacks arrive off the main thread; hop over before
        // touching windows or app state.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.handleClick() }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            if !(event.window is BoringNotchSkyLightWindow) {
                self?.handleClick()
            }
            return event
        }
    }

    private func uninstall() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleClick() {
        let mouse = NSEvent.mouseLocation
        let inside = NSApp.windows.contains { window in
            window is BoringNotchSkyLightWindow && window.frame.contains(mouse)
        }
        if !inside {
            onClose?()
        }
    }
}
