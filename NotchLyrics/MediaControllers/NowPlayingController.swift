//
//  NowPlayingController.swift
//  Notch Lyrics
//
//  Created by Alexander on 2025-03-29.
//

import AppKit
import Combine
import Defaults
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    func updatePlaybackInfo() async {
        await fetchFavoriteStateIfSupported()
    }

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music" || bundleID == "com.spotify.client"
    }

    var supportsFavorite: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music"
    }

    /// Bumped on every favourite write. A write loop whose generation no longer
    /// matches is stale and stops, so overlapping requests cannot fight over the
    /// same track.
    private var favoriteGeneration = 0

    @discardableResult
    func setFavorite(_ favorite: Bool) async -> Bool {
        let bundleID = playbackState.bundleIdentifier
        favoriteGeneration += 1
        let generation = favoriteGeneration

        // Reflect the change immediately — waiting on the write made the heart
        // feel unresponsive.
        var optimistic = playbackState
        optimistic.isFavorite = favorite
        playbackState = optimistic

        guard bundleID == "com.apple.Music" else { return true }
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return true }

        let target = favorite ? "true" : "false"
        let writeScript = """
        tell application "Music"
            try
                set favorited of current track to \(target)
            end try
        end tell
        """
        let readScript = """
        tell application "Music"
            try
                return (favorited of current track) as text
            on error
                return "ERR"
            end try
        end tell
        """

        // A single `set favorited` does not reliably stick while Music.app is
        // busy — it can silently keep the previous value for a while. Write,
        // then poll until the read-back agrees.
        //
        // The loop is bounded by wall-clock rather than a poll count, because a
        // single AppleScript round trip costs ~200ms under load: a fixed count
        // of polls both overshot the caller's intent window and could still
        // finish before Music had committed. Music was measured taking 1–4s to
        // reflect a write, so the budget has to cover that.
        let deadline = Date().addingTimeInterval(5)
        var observed = "?"

        pollLoop: for _ in 1...3 {
            guard generation == favoriteGeneration else { return false }
            try? await AppleScriptHelper.executeVoid(writeScript)

            while Date() < deadline {
                try? await Task.sleep(for: .milliseconds(120))
                guard generation == favoriteGeneration else { return false }
                if let r = try? await AppleScriptHelper.execute(readScript),
                   let text = r.stringValue {
                    observed = text
                    if text == target { break pollLoop }
                }
            }
            if Date() >= deadline { break }
        }

        guard generation == favoriteGeneration else { return false }
        await updatePlaybackInfo()
        return observed == target
    }

    private var lastMusicItem:
        (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    /// Guards stream restarts: a superseded generation must not spawn a
    /// second adapter process, and teardown must not spawn one at all.
    private var streamGeneration = 0
    private var isTearingDown = false

    /// The app macOS currently reports as the Now Playing owner.
    ///
    /// Tracked separately from `playbackState.bundleIdentifier` because diff
    /// messages only carry the fields that changed: without remembering the
    /// owner, a later update that omits the bundle id could not be attributed to
    /// any app, and a pin could not tell "another app took over" apart from
    /// "this tick simply had no bundle info".
    private var systemBundleIdentifier: String = ""
    /// Last ignored bundle, so a stream of ticks from the same intruding app
    /// logs once instead of filling the file.
    private var ignoredBundleLogged: String = ""

    /// When non-nil this controller is permanently pinned to one app (used by
    /// the "NetEase Cloud Music" source, which is a Now Playing session locked
    /// to the NetEase client). It takes precedence over the user's pin from
    /// Settings, which only applies to the generic "Now Playing" source.
    private let forcedPin: String?

    /// The bundle id the user pinned the notch to, or `nil` when not pinned.
    /// Read from Defaults on every update so toggling the setting takes effect
    /// immediately without rebuilding the controller or restarting the stream.
    private var pinnedBundleIdentifier: String? {
        if let forcedPin { return forcedPin }
        let pinned = Defaults[.pinnedPlayerBundle]
        return pinned.isEmpty ? nil : pinned
    }

    // MARK: - Initialization
    init?(forcedPin: String? = nil) {
        self.forcedPin = forcedPin
        if let forcedPin {
            // Seed the state with the pinned bundle so isActive(),
            // supportsFavorite and friends describe the right app even before
            // the first snapshot arrives.
            self.playbackState = PlaybackState(bundleIdentifier: forcedPin)
        }

        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework"))
        else {
            return nil
        }

        guard let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString) else { return nil }
        guard let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString) else { return nil }
        guard let MRMediaRemoteSetShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString) else { return nil }
        guard let MRMediaRemoteSetRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString) else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

        Task { await setupNowPlayingObserver() }
    }

    deinit {
        isTearingDown = true
        streamTask?.cancel()
        
        if let pipeHandler = self.pipeHandler {
            Task { await pipeHandler.close()
            }
        }
        
        if let process = self.process {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        self.process = nil
        self.pipeHandler = nil
    }

    // MARK: - Protocol Implementation
    func play() async {
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    func pause() async {
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    func togglePlay() async {
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    func nextTrack() async {
        MRMediaRemoteSendCommandFunction(4, nil)
    }

    func previousTrack() async {
        MRMediaRemoteSendCommandFunction(5, nil)
    }

    func seek(to time: Double) async {
        MRMediaRemoteSetElapsedTimeFunction(time)
    }

    func isActive() -> Bool {
        return true
    }
    
    func toggleShuffle() async {
        // MRMediaRemoteSendCommandFunction(6, nil)
        MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
    }
    
    func toggleRepeat() async {
        // MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }
    
    func setVolume(_ level: Double) async {
        // MediaRemote framework doesn't provide direct volume control for the active audio session
        // As a workaround, try to control the currently active music app directly
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        
        let bundleID = playbackState.bundleIdentifier
        if !bundleID.isEmpty {
            if bundleID == "com.apple.Music" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                if !runningApps.isEmpty {
                    let script = "tell application \"Music\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            } else if bundleID == "com.spotify.client" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
                if !runningApps.isEmpty {
                    let script = "tell application \"Spotify\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            }
        }
        
        playbackState.volume = clampedLevel
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() async {
        await startStream()
    }

    /// Launches the adapter stream. Called again on unexpected stream death —
    /// MediaRemote stops feeding the pipe across sleep/wake and the perl
    /// process eventually exits, which used to freeze the UI forever.
    private func startStream() async {
        streamGeneration &+= 1
        let generation = streamGeneration
        // A fresh stream re-reports the owner with its first snapshot; keeping a
        // stale id from before a sleep/wake could pin the notch to the wrong app.
        systemBundleIdentifier = ""
        ignoredBundleLogged = ""

        // Clean up any previous stream before spawning a new one.
        streamTask?.cancel()
        streamTask = nil
        if let old = self.process {
            if old.isRunning { old.terminate() }
            self.process = nil
        }

        let process = Process()
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
        else {
            assertionFailure("Could not find mediaremote-adapter.pl script or framework path")
            return
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "stream"]

        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()

        self.process = process
        self.pipeHandler = pipeHandler

        do {
            try process.run()
            streamTask = Task { [weak self] in
                await self?.processJSONStream()
            }
        } catch {
            assertionFailure("Failed to launch mediaremote-adapter.pl: \(error)")
            // Retry later instead of giving up for the rest of the app's life.
            scheduleStreamRestart(generation: generation, delay: 5)
        }
    }

    /// Ends the current stream so the restart path kicks in. `terminate()` on
    /// an already-exited process is a no-op.
    private func scheduleStreamRestart(generation: Int, delay: TimeInterval) {
        guard !isTearingDown, generation == streamGeneration else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.isTearingDown, generation == self.streamGeneration else { return }
            NSLog("NowPlayingController: restarting media stream")
            await self.startStream()
        }
    }

    // MARK: - Async Stream Processing
    private func processJSONStream() async {
        guard let pipeHandler = self.pipeHandler else { return }
        let generation = streamGeneration

        await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
            await self?.handleAdapterUpdate(update)
        }

        // The reader returned: EOF (the perl process died) or a broken pipe.
        // Tear the process down and start a fresh stream, or the UI would be
        // frozen at the last pre-sleep state until the app restarts.
        streamTask = nil
        guard !isTearingDown, generation == streamGeneration else { return }
        if let process = self.process, process.isRunning {
            process.terminate()
        }
        NSLog("NowPlayingController: media stream ended, restarting")
        scheduleStreamRestart(generation: generation, delay: 2)
    }

    // MARK: - Update Methods
    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false

        if let incoming = payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier,
           !incoming.isEmpty {
            systemBundleIdentifier = incoming
        }

        // Switching players is announced with a full snapshot that carries no
        // bundle id and no title — MediaRemote clearing its slot before the next
        // app publishes. Without this guard it falls through to the pinned
        // branch below (the remembered owner still matches the pin), blanks the
        // title and artwork, and the notch ends up empty: the exact opposite of
        // what a pin promises.
        if pinnedBundleIdentifier != nil,
           !diff,
           payload.parentApplicationBundleIdentifier == nil,
           payload.bundleIdentifier == nil,
           payload.title == nil {
            LyricsDebug.log("pin: dropping unattributed empty snapshot")
            markPinnedTrackStopped()
            return
        }

        // Pinned: ignore everything that is not the chosen app.
        //
        // The update is dropped whole rather than field by field. A diff message
        // for another app usually carries no bundle id, and letting even the
        // title-less ones through would walk the pinned track's position and
        // state forward one tick at a time until the display belonged to the
        // other app anyway.
        if let pinned = pinnedBundleIdentifier,
           !systemBundleIdentifier.isEmpty,
           systemBundleIdentifier != pinned {
            if ignoredBundleLogged != systemBundleIdentifier {
                ignoredBundleLogged = systemBundleIdentifier
                LyricsDebug.log("pin: ignoring \(systemBundleIdentifier), pinned to \(pinned)")
            }
            markPinnedTrackStopped()
            return
        }
        ignoredBundleLogged = ""

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)
        
        newPlaybackState.title = payload.title ?? (diff ? self.playbackState.title : "")
        newPlaybackState.artist = payload.artist ?? (diff ? self.playbackState.artist : "")
        newPlaybackState.album = payload.album ?? (diff ? self.playbackState.album : "")
        newPlaybackState.duration = payload.duration ?? (diff ? self.playbackState.duration : 0)
        
        if let elapsedTime = payload.elapsedTime {
            newPlaybackState.currentTime = elapsedTime
        } else if diff {
            if payload.playing == false {
                let timeSinceLastUpdate = Date().timeIntervalSince(self.playbackState.lastUpdated)
                newPlaybackState.currentTime = self.playbackState.currentTime + (self.playbackState.playbackRate * timeSinceLastUpdate)
            } else {
                newPlaybackState.currentTime = self.playbackState.currentTime
            }
        } else {
            newPlaybackState.currentTime = 0
        }

        
        if let shuffleMode = payload.shuffleMode {
            newPlaybackState.isShuffled = shuffleMode != 1
        } else if !diff {
            newPlaybackState.isShuffled = false
        } else {
            newPlaybackState.isShuffled = self.playbackState.isShuffled
        }
        if let repeatModeValue = payload.repeatMode {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
        } else if !diff {
            newPlaybackState.repeatMode = .off
        } else {
            newPlaybackState.repeatMode = self.playbackState.repeatMode
        }

        if let artworkDataString = payload.artworkData {
            newPlaybackState.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if !diff {
            newPlaybackState.artwork = nil
        }

        if let dateString = payload.timestamp,
           let date = ISO8601DateFormatter().date(from: dateString) {
            newPlaybackState.lastUpdated = date
        } else if !diff {
            newPlaybackState.lastUpdated = Date()
        } else {
            newPlaybackState.lastUpdated = self.playbackState.lastUpdated
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? self.playbackState.playbackRate : 1.0)
        // `playing` and `playbackRate` arrive in *separate* diff messages, so
        // the two must not be combined into one stored flag: a message carrying
        // `playing: true` while the rate is still 0 would latch the flag to
        // false, and the later rate message would read that false back and AND
        // it again — permanently stuck. The raw value is stored here and the
        // "is it really advancing" question is answered at read time.
        newPlaybackState.isPlaying = payload.playing ?? (diff ? self.playbackState.isPlaying : false)
        newPlaybackState.bundleIdentifier = (
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? self.playbackState.bundleIdentifier : "")
        )
        
        newPlaybackState.volume = payload.volume ?? (diff ? self.playbackState.volume : 0.5)
        // MediaRemote does not report Apple Music's liked state, so it has to be
        // carried over here — otherwise every adapter push resets it to false.
        newPlaybackState.isFavorite = self.playbackState.isFavorite

        self.playbackState = newPlaybackState

        // Refresh the liked state only on a full snapshot (i.e. when the track
        // changes). The value is absent from the payload, so doing it on every
        // diff tick would just be repeated AppleScript traffic. The state is
        // refreshed explicitly after a toggle by `updatePlaybackInfo()`.
        if !diff {
            await fetchFavoriteStateIfSupported()
        }
    }
    
    /// Freezes the pinned track once another app takes over the system player.
    ///
    /// Only the playing flag is cleared. The title, artwork and lyrics stay put
    /// so the notch keeps showing the pinned song, and the position stops
    /// advancing instead of running off the end of the track while nothing is
    /// actually playing. Everything is restored by the next update from the
    /// pinned app itself, i.e. as soon as it becomes the system player again.
    private func markPinnedTrackStopped() {
        guard playbackState.isPlaying else { return }
        var stopped = playbackState
        stopped.isPlaying = false
        stopped.playbackRate = 0
        playbackState = stopped
    }

     private func fetchFavoriteStateIfSupported() async {
         let bundleID = playbackState.bundleIdentifier
        
         if bundleID == "com.apple.Music" {
             let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
             guard !runningApps.isEmpty else { return }
             
             let script = """
             tell application "Music"
                 try
                     return (favorited of current track) as text
                 on error
                     return "false"
                 end try
             end tell
             """
             if let result = try? await AppleScriptHelper.execute(script) {
                 var updated = self.playbackState
                 // Music returns the value as text; `booleanValue` is not
                 // reliable for these descriptors.
                 updated.isFavorite = (result.stringValue ?? "false").trimmingCharacters(in: .whitespaces) == "true"
                 self.playbackState = updated
             } else {
             }
         }
     }
    
}

struct NowPlayingUpdate: Codable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let volume: Double?
}

actor JSONLinesPipeHandler {
    private let pipe: Pipe
    private let fileHandle: FileHandle
    private var buffer = ""
    
    init() {
        self.pipe = Pipe()
        self.fileHandle = pipe.fileHandleForReading
    }
    
    func getPipe() -> Pipe {
        return pipe
    }
    
    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        do {
            try await self.processLines(as: type) { decodedObject in
                await onLine(decodedObject)
            }
        } catch {
            print("Error processing JSON stream: \(error)")
        }
    }
    
    private func processLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async throws {
        while true {
            let data = try await readData()
            guard !data.isEmpty else { break }
            
            if let chunk = String(data: data, encoding: .utf8) {
                buffer.append(chunk)
                
                while let range = buffer.range(of: "\n") {
                    let line = String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])
                    
                    if !line.isEmpty {
                        await processJSONLine(line, as: type, onLine: onLine)
                    }
                }
            }
        }
    }
    
    private func processJSONLine<T: Decodable>(_ line: String, as type: T.Type, onLine: @escaping (T) async -> Void) async {
        guard let data = line.data(using: .utf8) else {
            return
        }
        do {
            let decodedObject = try JSONDecoder().decode(T.self, from: data)
            await onLine(decodedObject)
        } catch {
            // Ignore lines that can't be decoded
        }
    }
    
    private func readData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }
    
    func close() async {
        do {
            fileHandle.readabilityHandler = nil
            try fileHandle.close()
            try pipe.fileHandleForWriting.close()
        } catch {
            print("Error closing pipe handler: \(error)")
        }
    }
}
