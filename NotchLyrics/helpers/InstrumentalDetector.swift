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

    // MARK: - Classical works

    /// A movement rarely says "Instrumental": a Mahler symphony is just
    /// "Symphony No. 1 in D Major: I. Langsam, schleppend". When every source
    /// comes back empty-handed for a track like that, "Instrumental" is a truer
    /// answer than "No lyrics found" — the movement has no words to find.
    ///
    /// This is only ever consulted *after* a lookup failed, so a classical work
    /// whose words are transcribed still shows them.
    ///
    /// The bar is two signals: a form (symphony, sonata, nocturne …) and a
    /// structure (an opus or movement number, a key, a tempo direction). One
    /// alone is not enough — "Symphony" is also a pop song title, and "Op. 9"
    /// on its own could be anything.
    static func looksClassical(title: String, album: String) -> Bool {
        let fields = [title, album].map(spaced).filter { !$0.isEmpty }

        // 编目号（`Op. 72`、`BWV 846`…）只会挂在正式作品上，本身就够，不必再来一个
        // 曲式词。`18 Pieces, Op. 72: No. 15` 是这么漏掉的。
        if fields.contains(where: hasCatalogueNumber) { return true }

        guard fields.contains(where: { field in
            classicalForms.contains(where: field.contains)
        }) else { return false }

        return fields.contains { field in
            classicalStructure.contains(where: field.contains)
                || tempoDirections.contains(where: field.contains)
                || field.contains(" major") || field.contains(" minor")
                || field.contains(" dur") || field.contains(" moll")
                || field.range(
                    of: #"\b(i|ii|iii|iv|v|vi|vii|viii|ix|x)\b"#,
                    options: .regularExpression) != nil
        }
    }

    /// `op 72` / `opus 72` / `bwv 846` / `k 485` (Mozart) / `d 960` (Schubert) …
    /// Matched against a `spaced` string, so the number is a separate token and
    /// `shop 3` cannot match.
    private static let cataloguePattern = try! NSRegularExpression(
        pattern: #"\b(op|opus|bwv|kv|hob|woo|rv|mww|mwv|anh|k|d)\.?\s\d"#)

    private static func hasCatalogueNumber(_ field: String) -> Bool {
        cataloguePattern.firstMatch(
            in: field, range: NSRange(field.startIndex..., in: field)) != nil
    }

    private static let classicalForms = [
        "symphony", "symphonie", "symphonic", "concerto", "sonata", "sonatina",
        "quartet", "quintet", "sextet", "septet", "octet", "trio", "prelude",
        "nocturne", "etude", "impromptu", "ballade", "rhapsody", "overture",
        "suite", "fugue", "toccata", "mazurka", "polonaise", "arabesque",
        "fantasia", "serenade", "divertimento", "partita", "passacaglia",
        "chaconne", "intermezzo", "variations",
    ]

    /// Padded tokens, matched with `contains` against a `spaced` string.
    private static let classicalStructure = [
        " op ", " opus ", " bwv ", " kv ", " no ", " mvt ", " movement ",
    ]

    private static let tempoDirections = [
        "langsam", "allegro", "adagio", "andante", "andantino", "scherzo",
        "finale", "presto", "largo", "vivace", "moderato", "maestoso",
        "grave", "lento", "allegretto", "prestissimo",
    ]

    /// Lowercased, diacritic-folded, every run of punctuation turned into a
    /// single space, and padded so `" op "` matches a whole token only. Unlike
    /// `normalize` this keeps the word boundaries a tempo or key needs.
    private static func spaced(_ string: String) -> String {
        let folded = string
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
        return " \(String(folded).split(separator: " ").joined(separator: " ")) "
    }

    // MARK: - Genre

    /// 流派里写着「没有词」的那些，用 Apple Music 的拼法。
    ///
    /// 这是最硬的一个信号：流派是曲库自己标的，不必像标题那样猜。`Lyrical Harp`
    /// 和 `Für Alina` 这类钢琴曲，标题里既没有曲式词也没有编目号，标题启发式永远
    /// 抓不到——但它们的流派就是 `Classical`。
    ///
    /// 和标题启发式一样，只在「所有源都没结果」之后才被问到，所以有词的歌不受影响。
    /// 刻意不收 Jazz / Electronic / Opera：这三个里带人声的太常见，把它们判成
    /// 「纯音乐」比「未找到歌词」更糟。
    private static let instrumentalGenres = [
        "classical", "instrumental", "orchestral", "chamber", "piano",
        "soundtrack", "score", "new age", "ambient", "baroque",
        "古典", "器乐", "器樂", "纯音乐", "純音樂", "轻音乐", "輕音樂",
        "原声", "原聲", "配乐", "配樂",
    ]

    static func looksInstrumentalGenre(_ genre: String) -> Bool {
        let normalized = genre
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        guard !normalized.isEmpty else { return false }
        return instrumentalGenres.contains { normalized.contains($0) }
    }
}
