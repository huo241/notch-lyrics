//
//  InstrumentalDetector.swift
//  Notch Lyrics
//

import Foundation

/// Guesses from metadata that a track has no vocals at all.
///
/// The lyric sources only flag a minority of instrumentals: LRCLIB carries an
/// `instrumental` field and 网易云 answers `nolyric`, but a nocturne nobody
/// uploaded to either of them looks exactly like a song whose lyrics are
/// missing. The metadata is the evidence that is left, and "纯音乐" is a much
/// better answer than "未找到歌词" for a piano piece.
///
/// The guess leans towards false negatives on purpose. A marker only counts
/// when it is the whole title, sits inside brackets, or trails after a dash, so
/// `Love (Instrumental)` and `Love - Instrumental` are instrumentals while a
/// song that merely has the word in its name is not.
enum InstrumentalDetector {

    /// Markers that describe a recording rather than a version of one, so they
    /// count anywhere in the title or album.
    private static let alwaysMarkers = [
        "纯音乐", "純音樂", "无人声", "無人聲", "无歌词", "無歌詞",
        "没有填词", "沒有填詞",
    ]

    /// Chinese markers for a version of a song — `后来 (伴奏)`, `卡农 钢琴版`.
    /// Matched with `contains`, because Chinese does not put spaces between the
    /// marker and what follows it (`伴奏版` still contains `伴奏`).
    private static let chineseQualifiers = [
        "伴奏", "演奏版", "器乐版", "器樂版", "器乐", "器樂",
        "钢琴版", "鋼琴版", "钢琴曲", "鋼琴曲", "纯音",
        "轻音乐", "輕音樂", "背景音乐", "背景音樂", "音乐盒", "音樂盒",
    ]

    /// Latin markers that only count at the end of a segment or on their own:
    /// `Song (Instrumental)`, `Song - Instrumental`, `Song Inst.`,
    /// `Instrumental`. A song is allowed to be *called* "Instrumental Love",
    /// so a leading position is not enough for these.
    private static let latinTrailingQualifiers = [
        "instrumental", "inst", "pianoversion", "pianosolo",
    ]

    /// Latin markers that may also open the segment — `BGM 合集`,
    /// `Karaoke Version` — because nothing is likely to be titled after them.
    private static let latinLeadingQualifiers = [
        "karaoke", "bgm", "backingtrack", "minusone", "offvocal",
        "novocal", "novocals", "withoutvocals", "musicbox",
    ]

    /// - Parameters:
    ///   - title: the player's raw title.
    ///   - album: the player's raw album name, or an empty string.
    ///
    /// The artist is deliberately not inspected: "Karaoke Hits Band" is an
    /// artist name, not a statement about the recording.
    static func matches(title: String, album: String) -> Bool {
        let normalizedTitle = normalize(title)
        let normalizedAlbum = normalize(album)

        // 只描述录音本身的标记（纯音乐、无歌词），出现在哪儿都算。
        for field in [normalizedTitle, normalizedAlbum] where !field.isEmpty {
            if alwaysMarkers.contains(where: field.contains) { return true }
        }

        // 「版本类」标记只有在修饰歌名时才算证据。
        if qualifierSegments(of: title).contains(where: isQualified) { return true }

        // 专辑名只有整张就叫这个名字时才算，例如单曲碟 "Piano Solo"。
        // "Karaoke Hits" 描述的是合集，不代表这一首没人声。
        if !normalizedAlbum.isEmpty, allQualifierMarkers.contains(normalizedAlbum) {
            return true
        }

        return false
    }

    private static func isQualified(_ segment: String) -> Bool {
        let normalized = normalize(segment)
        guard !normalized.isEmpty else { return false }

        // 中文不靠空格断词，`伴奏版` 里仍然包含 `伴奏`。
        if chineseQualifiers.contains(where: normalized.contains) { return true }
        if latinTrailingQualifiers.contains(where: {
            normalized == $0 || normalized.hasSuffix($0)
        }) { return true }
        if latinLeadingQualifiers.contains(where: {
            normalized == $0 || normalized.hasPrefix($0) || normalized.hasSuffix($0)
        }) { return true }
        return false
    }

    private static let allQualifierMarkers: Set<String> = Set(
        chineseQualifiers + latinTrailingQualifiers + latinLeadingQualifiers)

    // MARK: - Segments

    private static let bracketPairs: [Character: Character] = [
        "(": ")", "（": "）", "[": "]", "【": "】", "「": "」", "《": "》",
    ]

    /// The title itself, every bracketed group inside it, and whatever trails
    /// the last dash — the only places a release qualifier can sit.
    private static func qualifierSegments(of raw: String) -> [String] {
        var segments = [raw]

        var openers: [Character] = []
        var current = ""
        for character in raw {
            if let closer = bracketPairs[character] {
                openers.append(closer)
                current = ""
            } else if let expected = openers.last, character == expected {
                openers.removeLast()
                if !current.isEmpty { segments.append(current) }
                current = ""
            } else if !openers.isEmpty {
                current.append(character)
            }
        }

        // `Song - Instrumental`, including the `Song – Instrumental` en dash
        // that some taggers write instead.
        for separator in [" - ", " – ", " — "] {
            if let range = raw.range(of: separator, options: .backwards) {
                segments.append(String(raw[range.upperBound...]))
            }
        }
        return segments
    }

    /// Lowercased, width- and diacritic-folded, punctuation removed. Unlike
    /// `LyricsQuery.normalize` this keeps bracketed content, which is exactly
    /// where the marker usually lives.
    private static func normalize(_ string: String) -> String {
        string
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
