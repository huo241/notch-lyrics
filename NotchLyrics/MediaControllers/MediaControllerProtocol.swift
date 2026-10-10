//
//  MediaControllerProtocol.swift
//  Notch Lyrics
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import AppKit
import Combine

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var supportsVolumeControl: Bool { get }
    var supportsFavorite: Bool { get }
    
    /// - Returns: `true` when the write was confirmed to have landed, `false`
    ///   when it timed out or was superseded. Callers use this to decide whether
    ///   the optimistic UI value can be considered authoritative.
    ///   Defaults to `true` for controllers that cannot verify.
    @discardableResult
    func setFavorite(_ favorite: Bool) async -> Bool
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func setVolume(_ level: Double) async
    func isActive() -> Bool
    func updatePlaybackInfo() async
}
