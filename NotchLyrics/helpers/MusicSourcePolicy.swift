//
//  MusicSourcePolicy.swift
//  Notch Lyrics
//

import Foundation

/// Decides whether the current now-playing session is music at all.
///
/// macOS reports a Safari tab playing a YouTube video, a Bilibili video and a
/// song in exactly the same shape — a title, an "artist", a duration — so
/// without this filter the notch answers every video with "No lyrics found",
/// which reads as a broken feature rather than an inapplicable one.
///
/// A whitelist is used rather than a list of video apps, because browsers and
/// players keep multiplying and an unknown app would then keep producing the
/// wrong answer. The price is deliberate: music played inside a browser
/// (YouTube Music's web player, for instance) counts as video, because the
/// bundle ID is the browser's and nothing else identifies the page.
enum MusicSourcePolicy {

    /// Bundle IDs of apps whose playback is music.
    static let musicBundleIdentifiers: Set<String> = [
        // Apple Music / Spotify
        "com.apple.Music",
        "com.spotify.client",

        // 网易云、QQ 音乐、酷狗、酷我、汽水音乐
        "com.netease.163music",
        "com.tencent.QQMusicMac",
        "com.tencent.QQMusic",
        "com.kugou.mac",
        "com.kuwo.KuwoMusic",
        "com.luna.music",

        // YouTube Music 桌面版（th-ch/youtube-music）
        "com.github.th-ch.youtube-music",

        // 其余常见桌面播放器
        "com.amazon.music",
        "com.tidal.desktop",
        "com.deezer.deezer-desktop",
        "com.coppertino.Vox",
        "com.brushedtype.Doppler",
        "com.swinsian.Swinsian",
        "com.plexamp.plexamp",
        "sh.cider.genten",
    ]

    /// False for browsers, video players and podcast apps — and for an empty or
    /// missing bundle ID, where there is no way to tell and staying quiet is
    /// the safer answer.
    static func isMusicApp(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return musicBundleIdentifiers.contains(bundleIdentifier)
    }
}
