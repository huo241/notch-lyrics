//
//  NotchViewModel.swift
//  Notch Lyrics
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

class NotchViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    @Published private(set) var notchState: NotchState = .closed

    /// True for the short window while the panel is expanding or collapsing.
    /// High-frequency timelines drop to a slower tick during that window so
    /// the layout animation gets the main thread; they return to their normal
    /// cadence as soon as it settles (lyric sync accuracy is unchanged at rest).
    @Published private(set) var isExpansionAnimating: Bool = false
    private var expansionWorkItem: DispatchWorkItem?

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    
    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        expansionWorkItem?.cancel()
    }

    /// Marks the layout animation window. The flag is a load-shedding signal,
    /// not a value the user sees animated; several callers reach `open()` and
    /// `close()` from inside `withAnimation`, which does not affect it. Both
    /// callers only mark when the state actually changes, so a repeated hover
    /// or a close on an already-closed panel cannot extend the low-refresh
    /// window.
    func markExpansionAnimation() {
        expansionWorkItem?.cancel()
        isExpansionAnimating = true
        let work = DispatchWorkItem { [weak self] in
            self?.isExpansionAnimating = false
        }
        expansionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34, execute: work)
    }

    init(screenUUID: String? = nil) {
        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)
        
        setupDetectorObserver()
    }
    
    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {
            
            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2
            
            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    func open() {
        guard notchState != .open else {
            // An already-open panel still refreshes the track, as before. It
            // must not restart the expansion window or re-publish a size and
            // state that have not changed.
            MusicManager.shared.forceUpdate()
            return
        }
        markExpansionAnimation()
        self.notchSize = openNotchSize
        self.notchState = .open

        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }

    func close() {
        // Do not close while a share picker or sharing service is active
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        // Every side effect below stays untouched: some callers invoke close()
        // on an already-closed panel to reset the home view and clear transient
        // state. Only the load-shedding window is guarded.
        if notchState != .closed { markExpansionAnimation() }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false

        // Where the panel reopens: a remembered tab wins outright; otherwise it
        // lands on the chosen home page (Settings › General › Home page), or on
        // the first panel that is still visible when that one is switched off.
        // The old "open the shelf if it has files" rule is gone — the shelf is
        // just one of the home pages now.
        if !coordinator.openLastTabByDefault {
            coordinator.currentView = coordinator.resolvedHomeView
        }
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(NotchAnimations.openClose) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
