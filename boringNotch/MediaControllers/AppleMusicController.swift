//
//  AppleMusicController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI
import AppKit

class AppleMusicController: MediaControllerProtocol {
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.apple.Music",
        playbackRate: 1
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool {
        return true
    }

    private var notificationTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init() {
        setupPlaybackStateChangeObserver()

        // Safety net for the notification stream above: if Music is running
        // but nothing has arrived for a while, poll once so the UI recovers
        // by itself instead of freezing until the app restarts.
        watchdogTask = Task { @Sendable [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.refreshIfStale()
            }
        }

        // Sleep/wake is the moment the stream above most often dies; pull a
        // fresh snapshot the second the Mac is awake again.
        NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { await self?.updatePlaybackInfo() }
            }
            .store(in: &cancellables)

        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }

    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            while !Task.isCancelled {
                let notifications = DistributedNotificationCenter.default().notifications(
                    named: NSNotification.Name("com.apple.Music.playerInfo")
                )

                for await _ in notifications {
                    await self?.updatePlaybackInfo()
                }

                // The async sequence ended — sleep/wake can terminate the
                // distributed stream while Music keeps running. Resubscribe
                // instead of losing every future state update.
                NSLog("AppleMusicController: playerInfo stream ended, resubscribing")
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    deinit {
        notificationTask?.cancel()
        watchdogTask?.cancel()
    }
    
    // MARK: - Protocol Implementation
    func play() async {
        await executeCommand("play")
        await refreshAfterCommand()
    }

    func pause() async {
        await executeCommand("pause")
        await refreshAfterCommand()
    }

    func togglePlay() async {
        await executeCommand("playpause")
        await refreshAfterCommand()
    }

    func nextTrack() async {
        await executeCommand("next track")
        await refreshAfterCommand()
    }

    func previousTrack() async {
        await executeCommand("previous track")
        await refreshAfterCommand()
    }
    
    func seek(to time: Double) async {
        await executeCommand("set player position to \(time)")
        await updatePlaybackInfo()
    }
    
    func toggleShuffle() async {
        await executeCommand("set shuffle enabled to not shuffle enabled")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func toggleRepeat() async {
        await executeCommand("""
            if song repeat is off then
                set song repeat to all
            else if song repeat is all then
                set song repeat to one
            else
                set song repeat to off
            end if
            """)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == "com.apple.Music" }
    }

    @discardableResult
    func setFavorite(_ favorite: Bool) async -> Bool {
        let script = """
        tell application \"Music\"
            try
                set favorited of current track to " + (favorite ? "true" : "false") + "
            end try
        end tell
        """
        try? await AppleScriptHelper.executeVoid(script)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
        return true
    }
    
    func updatePlaybackInfo() async {
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 11 else { return }
        var updatedState = self.playbackState
        
        updatedState.isPlaying = descriptor.atIndex(1).map(AppleScriptBoolean.isTrue) ?? false
        updatedState.title = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        updatedState.artist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        updatedState.album = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        updatedState.currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        updatedState.duration = descriptor.atIndex(6)?.doubleValue ?? 0
        updatedState.isShuffled = descriptor.atIndex(7).map(AppleScriptBoolean.isTrue) ?? false
        let repeatModeValue = descriptor.atIndex(8)?.int32Value ?? 0
        updatedState.repeatMode = RepeatMode(rawValue: Int(repeatModeValue)) ?? .off
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        updatedState.volume = Double(volumePercentage) / 100.0
        updatedState.artwork = descriptor.atIndex(10)?.data as Data?
        let lovedState = descriptor.atIndex(11).map(AppleScriptBoolean.isTrue) ?? false
        updatedState.isFavorite = lovedState
        updatedState.lastUpdated = Date()
        self.playbackState = updatedState
    }
    
    // MARK: - Private Methods

    /// Music needs a beat to reflect a command, and the playerInfo
    /// notification that would normally refresh us can be dead (see the
    /// watchdog). Refresh twice so a slow commit is still picked up.
    private func refreshAfterCommand() async {
        try? await Task.sleep(for: .milliseconds(350))
        await updatePlaybackInfo()
        try? await Task.sleep(for: .milliseconds(650))
        await updatePlaybackInfo()
    }

    /// Poll exactly once when the notification stream has gone quiet while
    /// Music keeps running — this is what un-freezes the UI after sleep.
    private func refreshIfStale() async {
        guard isActive() else { return }
        if Date().timeIntervalSince(playbackState.lastUpdated) > 25 {
            await updatePlaybackInfo()
        }
    }

    private func executeCommand(_ command: String) async {
        let script = "tell application \"Music\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }
    
    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Music"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffle enabled
                set repeatState to song repeat
                if repeatState is off then
                    set repeatValue to 1
                else if repeatState is one then
                    set repeatValue to 2
                else if repeatState is all then
                    set repeatValue to 3
                end if

                try
                    set artData to data of artwork 1 of current track
                on error
                    set artData to ""
                end try
                
                set currentVolume to sound volume
                set favoriteState to favorited of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatValue, currentVolume, artData, favoriteState}
            on error
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, false, 0, 50, "", false}
            end try
        end tell
        """
        
        return try await AppleScriptHelper.execute(script)
    }
    
}
