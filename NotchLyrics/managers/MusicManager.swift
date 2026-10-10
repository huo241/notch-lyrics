//
//  MusicManager.swift
//  Notch Lyrics
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import Combine
import Defaults
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

/// Which flavour of lyrics is currently loaded, so the UI can choose a
/// presentation (scrolling lines, static block, or a placeholder).
enum LyricsKind {
    case none
    case synced
    case plain
    case instrumental
}

/// Result of a lyrics lookup, independent of which provider produced it.
struct LyricsPayload {
    let kind: LyricsKind
    let plain: String
    let synced: [(time: Double, text: String)]
}

class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var animations: NotchAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published var currentLyrics: String = ""
    @Published var isFetchingLyrics: Bool = false
    @Published var syncedLyrics: [(time: Double, text: String)] = []
    @Published var lyricsKind: LyricsKind = .none
    /// True while a real track is loaded, regardless of whether it is playing.
    /// Used by the UI to keep the lyrics pane visible across pauses, which
    /// `isPlayerIdle` cannot express (it flips to `true` a few seconds after
    /// playback stops).
    @Published var hasActiveTrack: Bool = false
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false

    /// A favourite toggle the user just performed, held until the read-back
    /// settles. The liked state is read back asynchronously and can briefly
    /// report the pre-toggle value; without this guard that stale value would
    /// undo the tap. Because `toggleFavoriteTrack()` inverts the current state,
    /// an undone tap also made the *next* tap apply the opposite of what was
    /// intended (like → looks unliked → tap again → likes instead of unlikes).
    private var favoriteIntent: (value: Bool, expiresAt: Date)?
    /// How long a tap is protected from being reverted by an out-of-date
    /// read-back.
    ///
    /// Must outlast the controller's write-verify loop, which has a 5s budget
    /// (Music takes 1–4s to reflect a write, and each AppleScript round trip
    /// costs ~200ms under load). This leaves headroom for the write to be
    /// confirmed before the guard lapses; releasing it early is what let a
    /// stale value undo the tap.
    private let favoriteIntentWindow: TimeInterval = 12
    private var favoriteWriteTask: Task<Void, Never>?

    /// Identifies the track the currently loaded lyrics belong to. Used both as
    /// the cache key and to discard responses that arrive after the user has
    /// already skipped to another track.
    private var loadedLyricsTrackKey: String = ""
    /// In-memory cache of resolved lyrics, keyed by `"artist|title"` (lowercased).
    /// Not persisted: lyrics change rarely, but a disk cache is out of scope.
    private var lyricsCache: [String: LyricsPayload] = [:]
    private let lyricsCacheLimit = 50
    private var artworkData: Data? = nil

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Initialize the active controller after deprecation check
            self.setActiveControllerBasedOnPreference()
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else {
            if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
                setActiveController(fallbackController)
            }
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Cancel any existing flip animation
        flipWorkItem?.cancel()

        // Set new active controller
        activeController = controller

        self.canFavoriteTrack = controller.supportsFavorite

        // Get current state from active controller
        forceUpdate()
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        AppleScriptHelper.logDebug("chain: manager received playing=\(state.isPlaying) title=\(state.title)")
        // Playback state is taken at face value here. Deriving "is it really
        // producing sound" from `playbackRate` seemed sensible but froze the UI:
        // MediaRemote pushes updates only every ~20s, so a rate of 0 observed
        // right after a track change latched this false with no correction
        // arriving. `syncPositionFromMusic` below is the authority instead.
        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
                self.updateIdleState(state: state.isPlaying)
            }

            if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

        // Handle artwork and visual transitions for changed content
        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
                if state.title.isEmpty {
                    // Nothing is playing any more. MediaRemote announces this
                    // with an empty snapshot, and the previous artwork used to
                    // linger because the app-icon fallback below finds no
                    // bundle to load an icon for and simply does nothing.
                    self.usingAppIconForArtwork = false
                    self.updateAlbumArt(newAlbumArt: defaultImage)
                } else if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    // A real track with no embedded artwork — show its app icon.
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                }
            }
            self.artworkData = state.artwork

            if artworkChanged || state.artwork == nil {
                // Update last artwork change values
                self.lastArtworkTitle = state.title
                self.lastArtworkArtist = state.artist
                self.lastArtworkAlbum = state.album
                self.lastArtworkBundleIdentifier = state.bundleIdentifier
            }

            // Only update sneak peek if there's actual content and something changed
            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }

            // Fetch lyrics on content change
            self.fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title, artist: state.artist)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
        if state.title != self.songTitle {
            self.songTitle = state.title
            // A different track means any pending toggle belongs to the old one.
            self.favoriteIntent = nil
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            // Update volume control support from active controller
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        // A pending user toggle outranks the read-back, which may still carry
        // the pre-toggle value. Once the read agrees — or the window lapses —
        // the polled value takes over again.
        // The guard is released only when the window lapses, or by the write
        // task once Music has actually accepted the change.
        //
        // It must NOT be released just because a state arrived carrying the
        // expected value: the controller applies an optimistic update straight
        // away, and that update is published back here within milliseconds —
        // long before the AppleScript write has run. Releasing on that echo let
        // the next real read-back (still the old value) overwrite the UI, which
        // is why a tap appeared to undo itself a second later.
        if let intent = favoriteIntent {
            if Date() >= intent.expiresAt {
                favoriteIntent = nil
                if state.isFavorite != self.isFavoriteTrack {
                    self.isFavoriteTrack = state.isFavorite
                }
            }
            // Otherwise: hold the user's value, ignore this state's opinion.
        } else if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged {
            self.volume = state.volume
        }
        
        self.timestampDate = state.lastUpdated
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        // Toggle based on current state
        setFavorite(!isFavoriteTrack)
    }

    @MainActor
    private func toggleAppleMusicFavorite() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application \"Music\"
            if it is running then
                try
                    set loved of current track to (not loved of current track)
                    return loved of current track
                on error
                    return false
                end try
            else
                return false
            end if
        end tell
        """

        if let result = try? await AppleScriptHelper.execute(script) {
            self.isFavoriteTrack = AppleScriptBoolean.isTrue(result)
            self.forceUpdate()
        }
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        // Paint the new state straight away so the tap feels instant; the
        // controller writes to Music and reconciles afterwards. The intent is
        // recorded so the reconcile cannot undo it with a stale read.
        favoriteIntent = (value: favorite, expiresAt: Date().addingTimeInterval(favoriteIntentWindow))
        isFavoriteTrack = favorite

        // A single tap could start several overlapping writes (the button fires
        // more than once, and each write costs a few AppleScript round trips).
        // Overlapping writers fought each other inside Music, so only the newest
        // request is allowed to run — earlier ones are cancelled.
        favoriteWriteTask?.cancel()
        favoriteWriteTask = Task { @MainActor in
            let landed = await controller.setFavorite(favorite)
            guard !Task.isCancelled else { return }
            // Only release the guard when the controller confirmed the write.
            // On failure the guard stays until the window lapses, so the UI
            // keeps showing what the user asked for rather than silently
            // snapping back to a value Music never accepted.
            guard landed, favoriteIntent?.value == favorite else {
                return
            }
            favoriteIntent = nil
        }
    }

    /// Placeholder dislike function
    func dislikeCurrentTrack() {
        setFavorite(false)
    }

    // MARK: - Lyrics
    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String) {
        // Any real track marks the player as non-empty, even when paused.
        hasActiveTrack = !title.isEmpty

        guard Defaults[.enableLyrics], !title.isEmpty else {
            self.cancelLyricsFetch()
            return
        }

        // Playback state is pushed on every progress tick, so this is called
        // repeatedly for the same track. Fetching is only worth doing when the
        // track actually changed, otherwise in-flight work gets cancelled by
        // its own progress updates.
        let key = lyricsTrackKey(artist: artist, title: title)
        guard key != loadedLyricsTrackKey else { return }
        loadedLyricsTrackKey = key

        // Reuse a previous lookup for this track instead of hitting the network.
        if let cached = lyricsCache[key] {
            apply(cached)
            // A plain-only result may have gained a synced version upstream.
            if cached.kind == .plain {
                Task { @MainActor in
                    await self.fetchLyricsFromWeb(title: title, artist: artist, trackKey: key)
                }
            }
            return
        }

        // Prefer native Apple Music lyrics when available.
        //
        // Note: AppleScript's `lyrics` property only ever yields plain text —
        // Apple Music renders its time-synced lyrics through a private API that
        // is not reachable from a script. So this path can rarely produce a
        // timeline; when it cannot, the plain text is kept and the web lookup
        // below (or the background upgrade) is what makes the lyrics scroll.
        if let bundleIdentifier = bundleIdentifier, bundleIdentifier.contains("com.apple.Music") {
            Task { @MainActor in
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                guard !runningApps.isEmpty else {
                    await self.fetchLyricsFromWeb(title: title, artist: artist, trackKey: key)
                    return
                }

                self.isFetchingLyrics = true
                self.currentLyrics = ""
                do {
                    let script = """
                    tell application \"Music\"
                        if it is running then
                            if player state is playing or player state is paused then
                                try
                                    set l to lyrics of current track
                                    if l is missing value then
                                        return \"\"
                                    else
                                        return l
                                    end if
                                on error
                                    return \"\"
                                end try
                            else
                                return \"\"
                            end if
                        else
                            return \"\"
                        end if
                    end tell
                    """
                    if let result = try await AppleScriptHelper.execute(script), let lyricsString = result.stringValue {
                        let native = lyricsString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !native.isEmpty {
                            let parsed = Self.parseLRC(native)
                            if parsed.count >= 2 {
                                // Rare, but some tracks carry LRC in the field.
                                self.apply(LyricsPayload(kind: .synced, plain: native, synced: parsed), trackKey: key)
                                return
                            }
                            self.apply(LyricsPayload(kind: .plain, plain: native, synced: []), trackKey: key)
                            // Try to upgrade this plain text to a synced version.
                            await self.fetchLyricsFromWeb(title: title, artist: artist, trackKey: key)
                            return
                        }
                    }
                } catch {
                    // fall through to web lookup
                }
                await self.fetchLyricsFromWeb(title: title, artist: artist, trackKey: key)
            }
        } else {
            Task { @MainActor in
                self.isFetchingLyrics = true
                self.currentLyrics = ""
                await self.fetchLyricsFromWeb(title: title, artist: artist, trackKey: key)
            }
        }
    }

    private func cancelLyricsFetch() {
        loadedLyricsTrackKey = ""
        isFetchingLyrics = false
        currentLyrics = ""
        syncedLyrics = []
        lyricsKind = .none
    }

    private func lyricsTrackKey(artist: String, title: String) -> String {
        "\(artist.lowercased())|\(title.lowercased())"
    }

    /// Stores a resolved payload, but only if the track is still the current one.
    /// Without this check a slow response for a previous track would overwrite
    /// the lyrics of whatever is playing now.
    private func apply(_ payload: LyricsPayload, trackKey: String) {
        guard trackKey == loadedLyricsTrackKey else { return }
        lyricsCache[trackKey] = payload
        if lyricsCache.count > lyricsCacheLimit {
            lyricsCache.removeAll(keepingCapacity: true)
        }
        switch payload.kind {
        case .synced:
            syncedLyrics = payload.synced
            currentLyrics = payload.plain
        case .plain:
            syncedLyrics = []
            currentLyrics = payload.plain
        case .instrumental, .none:
            syncedLyrics = []
            currentLyrics = ""
        }
        lyricsKind = payload.kind
        isFetchingLyrics = false
    }

    /// Applies a payload that already belongs to the current track (cache hit).
    private func apply(_ payload: LyricsPayload) {
        apply(payload, trackKey: loadedLyricsTrackKey)
    }

    private func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
    }

    /// LRCLIB requires clients to identify themselves.
    private static let lyricsUserAgent: String = {
        let version = Bundle.main.releaseVersionNumber ?? "unknown"
        return "NotchLyrics/\(version) (https://github.com/huo241/notch-lyrics)"
    }()

    /// Percent-encodes one value of a query string.
    ///
    /// `.urlQueryAllowed` is wrong here: it leaves `&`, `=` and `+` intact, so
    /// a title containing one of them silently truncates the query.
    private static let lyricsQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private func lyricsQueryString(title: String, artist: String) -> String? {
        let cleanTitle = normalizedQuery(title)
        let cleanArtist = normalizedQuery(artist)
        guard !cleanTitle.isEmpty,
              let encodedTitle = cleanTitle.addingPercentEncoding(
                withAllowedCharacters: Self.lyricsQueryValueAllowed),
              let encodedArtist = cleanArtist.addingPercentEncoding(
                withAllowedCharacters: Self.lyricsQueryValueAllowed)
        else { return nil }

        return "track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
    }

    /// Looks the track up on LRCLIB.
    ///
    /// Two things make this more than a single request. `/api/get` matches the
    /// artist and title spelling exactly, while a player's metadata is often a
    /// noisy variant of it, so every spelling `LyricsQuery` can derive is
    /// tried. And `/api/search` answers with everything whose metadata merely
    /// *contains* the query, so its results are ranked locally and a record
    /// that does not look like this track is dropped instead of displayed.
    @MainActor
    private func fetchLyricsFromWeb(title: String, artist: String, trackKey: String) async {
        var best: (record: [String: Any], score: Double)?

        /// Keeps the highest-scoring record seen so far, and reports whether it
        /// is good enough to stop looking.
        func consider(_ record: [String: Any]) -> Bool {
            let score = LyricsQuery.score(
                record: record, title: title, artist: artist, duration: songDuration)
            if best == nil || score > best!.score { best = (record, score) }
            return score >= LyricsQuery.minimumScore
        }

        // 1. Exact-signature lookups across every spelling the metadata might
        //    be a noisy variant of. Bounded, because a track nobody has
        //    transcribed would otherwise cost a request per combination.
        var budget = 8
        lookup: for candidate in LyricsQuery.candidates(title: title, artist: artist).prefix(6) {
            guard let base = lyricsQueryString(title: candidate.title, artist: candidate.artist) else { continue }

            // LRCLIB's `duration` filter is the sharpest signal it offers, but
            // it only matches within ±2s — a different master or a re-encoded
            // local file misses outright. The unfiltered lookup therefore goes
            // second rather than being skipped.
            var probes = [base]
            if songDuration >= 1, songDuration <= 3600 {
                probes.insert(base + "&duration=\(Int(songDuration.rounded()))", at: 0)
            }

            for probe in probes {
                guard budget > 0 else { break lookup }
                budget -= 1
                guard let record = await fetchLyricsRecord(path: "api/get", query: probe) else { continue }
                if consider(record) { break lookup }
            }
        }

        // 2. Keyword search, for tracks the exact signature cannot reach.
        if best == nil || best!.score < LyricsQuery.minimumScore {
            let seed = LyricsQuery.cleaned(title: title, artist: artist)
            if let base = lyricsQueryString(title: seed.title, artist: seed.artist) {
                for record in await fetchLyricsRecords(path: "api/search", query: base) {
                    _ = consider(record)
                }
            }
        }

        // A response for a track the user has already skipped past is useless.
        guard trackKey == loadedLyricsTrackKey else { return }

        guard let match = best else {
            self.apply(LyricsPayload(kind: .none, plain: "", synced: []), trackKey: trackKey)
            return
        }

        let record = match.record
        if (record["instrumental"] as? Bool) == true {
            self.apply(LyricsPayload(kind: .instrumental, plain: "", synced: []), trackKey: trackKey)
            return
        }

        let plain = ((record["plainLyrics"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let syncedRaw = ((record["syncedLyrics"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Synced lyrics are the entire point here, so they win when present;
        // plain text is only a fallback.
        let synced = syncedRaw.isEmpty ? [] : Self.parseLRC(syncedRaw)
        if synced.count >= 2 {
            self.apply(
                LyricsPayload(kind: .synced, plain: plain.isEmpty ? syncedRaw : plain, synced: synced),
                trackKey: trackKey)
        } else if !plain.isEmpty {
            self.apply(LyricsPayload(kind: .plain, plain: plain, synced: []), trackKey: trackKey)
        } else {
            self.apply(LyricsPayload(kind: .none, plain: "", synced: []), trackKey: trackKey)
        }
    }

    /// Performs a LRCLIB request, honouring `Retry-After` on throttling.
    /// Returns nil for every non-200 outcome, including the 404 that means
    /// "no match".
    private func lyricsRequest(url: URL, attempt: Int = 0) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(Self.lyricsUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if (http.statusCode == 429 || http.statusCode == 503), attempt < 2 {
                // The rate limiter sits at the network edge and does not
                // guarantee a JSON body, so only the header is consulted.
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 1
                try? await Task.sleep(for: .seconds(min(max(retryAfter, 0.5), 10)))
                return await lyricsRequest(url: url, attempt: attempt + 1)
            }
            guard http.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func fetchLyricsRecord(path: String, query: String) async -> [String: Any]? {
        guard let url = URL(string: "https://lrclib.net/\(path)?\(query)"),
              let data = await lyricsRequest(url: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func fetchLyricsRecords(path: String, query: String) async -> [[String: Any]] {
        guard let url = URL(string: "https://lrclib.net/\(path)?\(query)"),
              let data = await lyricsRequest(url: url) else { return [] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    // MARK: - Synced lyrics helpers

    static func parseLRC(_ lrc: String) -> [(time: Double, text: String)] {
        LyricsParser.parse(lrc)
    }

    /// Index of the line that should be highlighted for the given elapsed time.
    func currentLyricIndex(at elapsed: Double) -> Int? {
        LyricsParser.currentIndex(in: syncedLyrics, at: elapsed)
    }

    func lyricLine(at elapsed: Double) -> String {
        guard !syncedLyrics.isEmpty else { return currentLyrics }
        guard let idx = currentLyricIndex(at: elapsed) else { return currentLyrics }
        return syncedLyrics[idx].text
    }

    private func triggerFlipAnimation() {
        // Cancel any existing animation
        flipWorkItem?.cancel()

        // Create a new animation
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }

        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        withAnimation(.smooth) {
            self.albumArt = newAlbumArt
            if Defaults[.coloredSpectrogram] {
                self.calculateAverageColor()
            }
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        // A rate of 0 while `isPlaying` is true is not a real pause — MediaRemote
        // simply stopped updating the rate after a track change. Multiplying by
        // it pinned the position to the last reported elapsed value, so the
        // progress bar and lyrics sat frozen while audio played on. Assume
        // normal speed in that case.
        let effectiveRate = playbackRate > 0 ? playbackRate : 1
        let estimated = elapsedTime + (timeDifference * effectiveRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        AppleScriptHelper.logDebug("chain: UI playPause tapped, activeController=\(activeController != nil ? "set" : "NIL")")
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
        // Check if bundle identifier is valid and if the app is actually running
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }
        
        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            // For unsupported apps, don't sync volume
            return
        }
        
        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript) {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0
            
            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}
